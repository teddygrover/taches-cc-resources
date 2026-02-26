# R/filter_initial.R — Date, deduplication, and text length filters
#
# Applied sequentially to the canonical schema produced by load_reddit_data().
# These are cheap rule-based operations that should run before any API calls.

library(dplyr)
library(digest)

#' Apply initial filters: date, deduplication, minimum text length
#'
#' @param df Tibble from load_reddit_data() with canonical column names
#' @param cfg Configuration list (default: CFG)
#' @return Filtered tibble with provenance columns added
apply_initial_filters <- function(df, cfg = CFG) {
  n_start <- nrow(df)
  log_msg(paste("Starting initial filters on", n_start, "records"))


  # Step 1: Date filter (>= start_date)
  df <- filter_by_date(df, cfg$start_date)

  # Step 2: Deduplication (exact ID + near-duplicate text hash)
  df <- deduplicate(df)

  # Step 3: Minimum text length
  df <- filter_by_text_length(df, cfg$min_text_chars)

  # Step 4: Add provenance columns
  df$filter_stage <- "initial_pass"
  df$filtered_at  <- Sys.time()

  log_msg(paste("Initial filtering complete:", nrow(df), "/", n_start, "records kept",
                sprintf("(%.1f%%)", 100 * nrow(df) / n_start)))

  df
}

#' Filter records by date (keep only >= start_date)
#' @param df Tibble with created_at column (POSIXct)
#' @param start_date Date threshold
#' @return Filtered tibble
filter_by_date <- function(df, start_date) {
  n_before <- nrow(df)

  # Handle records with unparseable timestamps — keep them (conservative)
  has_date <- !is.na(df$created_at)
  passes <- has_date & as.Date(df$created_at) >= start_date
  no_date <- !has_date

  df <- df[passes | no_date, ]

  n_after <- nrow(df)
  n_no_date <- sum(no_date)
  log_msg(paste0("Date filter (>= ", start_date, "): kept ", n_after, " / ", n_before,
                 " records", if (n_no_date > 0) paste0(" (", n_no_date, " with missing date kept)") else ""))
  df
}

#' Remove duplicate records by ID and by text hash within subreddit
#' @param df Tibble with id, text, subreddit columns
#' @return Deduplicated tibble
deduplicate <- function(df) {
  n_before <- nrow(df)

  # Exact ID duplicates: keep first occurrence
  n_id_dupes <- sum(duplicated(df$id))
  df <- df[!duplicated(df$id), ]
  log_msg(paste("Dedup (ID): removed", n_id_dupes, "exact duplicates"))

  # Near-duplicate text within same subreddit: hash of lowered/trimmed text
  df$text_hash <- vapply(
    paste0(tolower(trimws(df$text)), "||", df$subreddit),
    function(x) digest(x, algo = "md5"),
    character(1)
  )

  n_text_dupes <- sum(duplicated(df$text_hash))
  df <- df[!duplicated(df$text_hash), ]
  df$text_hash <- NULL  # clean up temp column
  log_msg(paste("Dedup (text hash): removed", n_text_dupes, "near-duplicates within same subreddit"))

  df
}

#' Filter records with text below minimum character length
#' @param df Tibble with text column
#' @param min_chars Minimum character count
#' @return Filtered tibble
filter_by_text_length <- function(df, min_chars) {
  n_before <- nrow(df)

  # Use coalesce of text for posts (may include title context)
  text_len <- nchar(trimws(coalesce(df$text, "")))
  df <- df[text_len >= min_chars, ]

  n_removed <- n_before - nrow(df)
  log_msg(paste("Text length filter: removed", n_removed, "records below", min_chars, "chars"))

  df
}
