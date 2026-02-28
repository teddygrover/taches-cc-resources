# R/filter_initial.R
# ---------------------------------------------------------------------------
# apply_initial_filters(df, cfg)
#
# Applies rule-based filters to the normalised Reddit tibble produced by
# load_reddit_data(). Filters are applied in sequence and each step is
# logged with before/after counts.
#
# Steps:
#   1. Date filter  — post-based cascade: keep posts >= start_date, keep
#                     comments whose root post is in the valid set
#   2. Deduplication — exact ID duplicates, then content hash within subreddit
#   3. Minimum text length — drop records with < min_text_chars characters
#   4. Provenance columns — filter_stage, filtered_at
# ---------------------------------------------------------------------------

library(dplyr)
library(digest)

apply_initial_filters <- function(df, cfg = CFG) {

  n_start <- nrow(df)
  log_msg(paste("Starting initial filters on", n_start, "records"))

  # ── Step 1: Date filter (post-based, cascade to comments) ─────────────────
  #
  # created_at is populated for posts only; comments have NA.
  # Strategy:
  #   1a. Identify posts created on or after start_date → valid_post_ids
  #   1b. Keep posts in that set; keep comments whose post_id is in that set
  #       Comments whose post_id is absent (pre-2020 or scraped outside dataset)
  #       are dropped.

  n_before_date <- nrow(df)

  valid_post_ids <- df |>
    filter(type == "post", as.Date(created_at) >= cfg$start_date) |>
    pull(id)

  df <- df |>
    filter(
      (type == "post"    & id      %in% valid_post_ids) |
      (type == "comment" & post_id %in% valid_post_ids)
    )

  n_posts_kept    <- sum(df$type == "post",    na.rm = TRUE)
  n_comments_kept <- sum(df$type == "comment", na.rm = TRUE)
  n_dropped_date  <- n_before_date - nrow(df)

  log_msg(paste0(
    "Date filter (>= ", cfg$start_date, "): kept ", n_posts_kept, " posts; kept ",
    n_comments_kept, " comments linked to valid posts; dropped ",
    n_dropped_date, " records total"
  ))

  # ── Step 2a: Deduplication — exact ID ──────────────────────────────────────
  n_before_id_dedup <- nrow(df)
  df <- df |> distinct(id, .keep_all = TRUE)
  n_dropped_id <- n_before_id_dedup - nrow(df)
  log_msg(paste("Dedup (ID): removed", n_dropped_id, "duplicate IDs"))

  # ── Step 2b: Deduplication — content hash within subreddit ─────────────────
  n_before_hash_dedup <- nrow(df)

  df <- df |>
    mutate(
      .text_hash = vapply(
        tolower(trimws(text)),
        function(t) digest::digest(t, algo = "md5"),
        character(1)
      )
    ) |>
    distinct(subreddit, .text_hash, .keep_all = TRUE) |>
    select(-.text_hash)

  n_dropped_hash <- n_before_hash_dedup - nrow(df)
  log_msg(paste("Dedup (text hash): removed", n_dropped_hash, "near-duplicate records"))

  # ── Step 3: Minimum text length ─────────────────────────────────────────────
  n_before_len <- nrow(df)
  df <- df |> filter(nchar(trimws(text)) >= cfg$min_text_chars)
  n_dropped_len <- n_before_len - nrow(df)
  log_msg(paste0(
    "Text length filter: removed ", n_dropped_len,
    " records below ", cfg$min_text_chars, " chars"
  ))

  # ── Step 4: Provenance columns ───────────────────────────────────────────────
  df <- df |>
    mutate(
      filter_stage = "initial_pass",
      filtered_at  = Sys.time()
    )

  log_msg(paste(
    "Initial filtering complete:", nrow(df), "records retained from", n_start,
    paste0("(", round(100 * nrow(df) / n_start, 1), "% kept)")
  ))

  df
}
