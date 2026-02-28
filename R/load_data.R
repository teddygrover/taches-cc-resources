# R/load_data.R
# ---------------------------------------------------------------------------
# load_reddit_data(path)
#
# Reads all CSV/XLSX files from `path`, validates the exact column schema
# of the proprietary Reddit crawler export, and normalises to the canonical
# pipeline column set.
#
# Returns a single tibble with canonical columns:
#   id, text, title, subreddit, created_at, type, parent_id, post_id,
#   score, author
# ---------------------------------------------------------------------------

library(readr)
library(dplyr)
library(here)

# Required columns that MUST be present in every source file.
# These are the exact camelCase names from the crawler export.
.REQUIRED_COLS <- c(
  "parsedId",
  "body",
  "createdAt",
  "dataType",
  "parsedParentId",
  "parsedPostId",
  "parsedCommunityName",
  "authorName",
  "upVotes",
  "commentUpVotes",
  "title"
)

load_reddit_data <- function(path = CFG$path_raw) {

  # ── 1. Discover files ────────────────────────────────────────────────────
  csv_files  <- list.files(path, pattern = "\\.csv$",  full.names = TRUE, recursive = FALSE)
  xlsx_files <- list.files(path, pattern = "\\.xlsx$", full.names = TRUE, recursive = FALSE)
  all_files  <- c(csv_files, xlsx_files)

  if (length(all_files) == 0) {
    stop("No CSV or XLSX files found in: ", path,
         "\nPlease copy your Reddit data files to data/raw/ before running this script.")
  }

  log_msg(paste("Found", length(all_files), "file(s) in", path))

  # ── 2. Read each file ────────────────────────────────────────────────────
  dfs <- lapply(all_files, function(f) {
    ext <- tolower(tools::file_ext(f))
    df  <- if (ext == "xlsx") {
      readxl::read_excel(f)
    } else {
      readr::read_csv(
        f,
        col_types  = readr::cols(.default = readr::col_character()),
        locale     = readr::locale(encoding = "UTF-8"),
        show_col_types = FALSE
      )
    }
    log_msg(paste("  Loaded", nrow(df), "rows from", basename(f)))
    df
  })

  # ── 3. Row-bind all files ────────────────────────────────────────────────
  combined <- dplyr::bind_rows(dfs)
  log_msg(paste("Total rows after combining:", nrow(combined)))

  # ── 4. Schema validation ─────────────────────────────────────────────────
  missing_cols <- setdiff(.REQUIRED_COLS, names(combined))
  if (length(missing_cols) > 0) {
    stop(
      "Schema validation failed — the following required columns are absent:\n",
      paste("  -", missing_cols, collapse = "\n"),
      "\n\nColumns actually found in the data:\n",
      paste("  ", sort(names(combined)), collapse = "\n")
    )
  }

  # ── 5. Normalise to canonical schema ────────────────────────────────────
  # upVotes and commentUpVotes arrive as character (col_character() above);
  # coerce to integer for scoring.
  canonical <- combined |>
    dplyr::mutate(
      upVotes        = suppressWarnings(as.integer(upVotes)),
      commentUpVotes = suppressWarnings(as.integer(commentUpVotes)),
      # created_at: posts only — comments have NA. Parse as POSIXct.
      created_at     = suppressWarnings(
        readr::parse_datetime(createdAt, locale = readr::locale(tz = "UTC"))
      )
    ) |>
    dplyr::transmute(
      id         = as.character(parsedId),
      text       = as.character(body),       # Both posts and comments
      title      = as.character(title),      # Posts only; NA for comments — do NOT fill
      subreddit  = as.character(parsedCommunityName),
      created_at = created_at,              # POSIXct; NA for all comments
      type       = as.character(dataType),  # Exactly "post" or "comment"
      parent_id  = as.character(parsedParentId),  # Bare IDs, no t3_/t1_ prefix; NA for root posts
      post_id    = as.character(parsedPostId),    # Direct root post link; used for date filtering
      score      = dplyr::coalesce(upVotes, commentUpVotes),  # Posts: upVotes; comments: commentUpVotes
      author     = as.character(authorName)
    )

  log_msg(paste(
    "Schema normalisation complete.",
    nrow(canonical), "records;",
    sum(canonical$type == "post",    na.rm = TRUE), "posts,",
    sum(canonical$type == "comment", na.rm = TRUE), "comments"
  ))

  canonical
}
