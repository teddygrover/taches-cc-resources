# R/load_data.R — Load raw Reddit CSVs and normalise to canonical schema
#
# Actual CSV schema (from user's crawler data):
#   authorId, authorName, body, bodyHtml, commentCreatedAt, commentUpVotes,
#   commentsCount, communityId, communityName, contentUrl, crawledAt, createdAt,
#   dataType, flair, id, images.0, parentId, parsedAuthorId, parsedCommunityId,
#   parsedCommunityName, parsedId, parsedParentId, parsedPostId, parsedSubredditId,
#   postId, postType, postUrl, subredditId, subredditName, title, upVotes, url
#
# Key mappings (actual → canonical):
#   parsedId / id           → id
#   body                    → text
#   title                   → title (posts only; NA for comments)
#   createdAt               → created_at (POSIXct)
#   dataType                → type ("post" or "comment")
#   parsedParentId          → parent_id (bare ID, no t3_/t1_ prefixes)
#   parsedPostId            → post_id (link to root post)
#   parsedCommunityName     → subreddit (preferred over subredditName)
#   authorName              → author
#   upVotes / commentUpVotes → score (coalesced)
#   postType                → post_type
#   flair                   → flair
#   url                     → url
#   postUrl                 → post_url

library(readr)
library(dplyr)

# Columns required in the raw CSV
REQUIRED_COLS <- c("body", "createdAt", "dataType", "parsedId")

# Columns we want to keep (if present)
KEEP_COLS <- c(
  "id", "parsedId", "body", "title", "createdAt", "commentCreatedAt",
  "dataType", "parentId", "parsedParentId", "parsedPostId",
  "subredditName", "parsedCommunityName", "authorName",
  "upVotes", "commentUpVotes", "postType", "flair", "url", "postUrl"
)

#' Load all Reddit CSV files from a directory and normalise to canonical schema
#'
#' @param path Directory containing CSV files (default: CFG$path_raw)
#' @return A tibble with canonical column names
load_reddit_data <- function(path = CFG$path_raw) {
  csv_files <- list.files(path, pattern = "\\.csv$", full.names = TRUE, ignore.case = TRUE)

  if (length(csv_files) == 0) {
    stop("No CSV files found in: ", path, "\nPlease copy your Reddit CSVs to data/raw/")
  }

  log_msg(paste("Found", length(csv_files), "CSV file(s) in", path))

  all_data <- lapply(csv_files, function(f) {
    log_msg(paste("Reading:", basename(f)))
    df <- read_csv(f, col_types = cols(.default = col_character()), locale = locale(encoding = "UTF-8"),
                   show_col_types = FALSE)
    log_msg(paste("  ->", nrow(df), "rows,", ncol(df), "columns"))

    # Validate required columns
    missing <- setdiff(REQUIRED_COLS, names(df))
    if (length(missing) > 0) {
      stop(
        "Missing required columns in ", basename(f), ": ", paste(missing, collapse = ", "),
        "\nColumns found: ", paste(names(df), collapse = ", ")
      )
    }

    # Keep only columns we need (silently ignore missing optional ones)
    cols_present <- intersect(KEEP_COLS, names(df))
    df[, cols_present, drop = FALSE]
  })

  combined <- bind_rows(all_data)
  log_msg(paste("Combined:", nrow(combined), "total rows from", length(csv_files), "file(s)"))

  # Normalise to canonical schema
  normalise_schema(combined)
}

#' Normalise raw CSV columns to canonical pipeline names
#'
#' @param df Raw tibble with original column names
#' @return Tibble with canonical column names
normalise_schema <- function(df) {
  canonical <- tibble(
    # ID: prefer parsedId, fall back to id
    id = if ("parsedId" %in% names(df)) {
      coalesce(df$parsedId, df$id)
    } else {
      df$id
    },

    # Text content
    text = df$body,
    title = if ("title" %in% names(df)) df$title else NA_character_,

    # Timestamp: use createdAt as primary (reliable for both posts and comments)
    created_at = parse_datetime_flexible(df$createdAt),

    # Record type: "post" or "comment"
    type = df$dataType,

    # Parent linking: use parsedParentId (bare ID, no t3_/t1_ prefixes)
    parent_id = if ("parsedParentId" %in% names(df)) df$parsedParentId else df$parentId,

    # Root post ID
    post_id = if ("parsedPostId" %in% names(df)) df$parsedPostId else NA_character_,

    # Subreddit: prefer parsedCommunityName (cleaner)
    subreddit = if ("parsedCommunityName" %in% names(df)) {
      coalesce(df$parsedCommunityName, df$subredditName)
    } else if ("subredditName" %in% names(df)) {
      df$subredditName
    } else {
      NA_character_
    },

    # Author
    author = if ("authorName" %in% names(df)) df$authorName else NA_character_,

    # Score: coalesce upVotes (posts) and commentUpVotes (comments)
    score = coalesce_score(df),

    # Extra metadata
    post_type = if ("postType" %in% names(df)) df$postType else NA_character_,
    flair = if ("flair" %in% names(df)) df$flair else NA_character_,
    url = if ("url" %in% names(df)) df$url else NA_character_,
    post_url = if ("postUrl" %in% names(df)) df$postUrl else NA_character_
  )

  # Clean up type values
  canonical$type <- tolower(trimws(canonical$type))

  # Log type distribution
  type_counts <- table(canonical$type, useNA = "ifany")
  log_msg(paste("Record types:", paste(names(type_counts), type_counts, sep = "=", collapse = ", ")))

  # Log subreddit distribution (top 10)
  sub_counts <- sort(table(canonical$subreddit, useNA = "ifany"), decreasing = TRUE)
  top_subs <- head(sub_counts, 10)
  log_msg(paste("Top subreddits:", paste(names(top_subs), top_subs, sep = "=", collapse = ", ")))

  canonical
}

#' Parse datetime strings flexibly
#' Handles ISO 8601 and common timestamp formats
#' @param x Character vector of datetime strings
#' @return POSIXct vector
parse_datetime_flexible <- function(x) {
  # Try ISO 8601 first (most likely from crawler)
  parsed <- suppressWarnings(as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%S", tz = "UTC"))

  # Fall back to other common formats for any NAs
  still_na <- is.na(parsed) & !is.na(x)
  if (any(still_na)) {
    parsed[still_na] <- suppressWarnings(
      as.POSIXct(x[still_na], format = "%Y-%m-%d %H:%M:%S", tz = "UTC")
    )
  }

  # Try Unix epoch as last resort
  still_na <- is.na(parsed) & !is.na(x)
  if (any(still_na)) {
    numeric_vals <- suppressWarnings(as.numeric(x[still_na]))
    valid_epoch <- !is.na(numeric_vals) & numeric_vals > 1e9 & numeric_vals < 2e10
    if (any(valid_epoch)) {
      parsed[still_na][valid_epoch] <- as.POSIXct(numeric_vals[valid_epoch], origin = "1970-01-01", tz = "UTC")
    }
  }

  n_failed <- sum(is.na(parsed) & !is.na(x))
  if (n_failed > 0) {
    log_msg(paste("WARNING:", n_failed, "timestamps could not be parsed"), level = "WARN")
  }

  parsed
}

#' Coalesce score from upVotes (posts) and commentUpVotes (comments)
#' @param df Raw tibble
#' @return Integer vector of scores
coalesce_score <- function(df) {
  up <- if ("upVotes" %in% names(df)) suppressWarnings(as.integer(df$upVotes)) else NA_integer_
  cup <- if ("commentUpVotes" %in% names(df)) suppressWarnings(as.integer(df$commentUpVotes)) else NA_integer_

  if (is.integer(up) && length(up) == 1 && is.na(up)) up <- rep(NA_integer_, nrow(df))
  if (is.integer(cup) && length(cup) == 1 && is.na(cup)) cup <- rep(NA_integer_, nrow(df))

  coalesce(up, cup)
}
