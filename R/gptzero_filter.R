# R/gptzero_filter.R — GPTZero AI-detection filtering with quota tracking
#
# Uses GPTZero API to score records for AI-generated content probability.
# Records above the threshold are flagged as AI-generated and excluded from
# the downstream pipeline.
#
# API: POST https://api.gptzero.me/v2/predict/text
# Auth: x-api-key header
# Monthly word quota: 300,000 (tracked carefully)

library(httr2)
library(jsonlite)
library(dplyr)

#' Count words in a text string
#' @param text Character string
#' @return Integer word count
count_words <- function(text) {
  vapply(text, function(t) {
    if (is.na(t) || nchar(trimws(t)) == 0) return(0L)
    length(strsplit(trimws(t), "\\s+")[[1]])
  }, integer(1), USE.NAMES = FALSE)
}

#' Estimate total word quota usage for a dataset
#' @param df Tibble with text column
#' @return Total word count (invisible), with log output
estimate_word_quota <- function(df) {
  word_counts <- count_words(df$text)
  total <- sum(word_counts)

  log_msg(paste("Word quota estimate:", format(total, big.mark = ","), "words"))
  log_msg(paste("  Monthly limit: 300,000 |",
                sprintf("%.1f%%", 100 * total / 300000), "of quota"))

  if (total > 0.8 * 300000) {
    log_msg("WARNING: Estimated usage exceeds 80% of monthly quota!", level = "WARN")
  }

  invisible(total)
}

#' Call GPTZero API for a single document
#'
#' @param text Character string to analyse
#' @param api_key GPTZero API key
#' @return List with completely_generated_prob, average_generated_prob, predicted_class
call_gptzero_single <- function(text, api_key) {
  tryCatch({
    resp <- request("https://api.gptzero.me/v2/predict/text") |>
      req_headers(
        `x-api-key`   = api_key,
        `Content-Type` = "application/json"
      ) |>
      req_body_json(list(document = text)) |>
      req_retry(max_tries = 3, backoff = ~ 2) |>
      req_timeout(30) |>
      req_perform()

    body <- resp_body_json(resp)

    list(
      completely_generated_prob = body$documents[[1]]$completely_generated_prob %||% NA_real_,
      average_generated_prob    = body$documents[[1]]$average_generated_prob %||% NA_real_,
      predicted_class           = body$documents[[1]]$predicted_class %||% NA_character_
    )
  }, error = function(e) {
    log_msg(paste("GPTZero API error:", conditionMessage(e)), level = "WARN")
    list(
      completely_generated_prob = NA_real_,
      average_generated_prob    = NA_real_,
      predicted_class           = NA_character_
    )
  })
}

#' Run GPTZero filtering on a dataset with checkpointing and quota tracking
#'
#' @param df Tibble with id and text columns
#' @param cfg Configuration list (default: CFG)
#' @return Tibble with id, gptzero_prob, gptzero_class, is_ai_generated
run_gptzero_filter <- function(df, cfg = CFG) {
  ai_threshold <- cfg$gptzero_ai_threshold %||% 0.75
  api_key <- cfg$gptzero_api_key

  if (is.null(api_key) || nchar(api_key) == 0 || api_key == "") {
    stop("GPTZero API key not set. Add GPTZERO_API_KEY to .Renviron or config/config.R")
  }

  # Check for existing checkpoint
  checkpoint <- load_latest_checkpoint("gptzero")
  already_done <- character(0)
  results <- list()
  words_used <- 0

  if (!is.null(checkpoint)) {
    already_done <- checkpoint$id
    results <- split(checkpoint, seq_len(nrow(checkpoint)))
    results <- lapply(results, as.list)
    words_used <- sum(count_words(df$text[df$id %in% already_done]))
    log_msg(paste("Resuming from checkpoint:", length(already_done),
                  "records already processed (~", format(words_used, big.mark = ","), "words)"))
  }

  # Pre-flight quota check
  total_words <- estimate_word_quota(df |> filter(!id %in% already_done))

  # Filter to unprocessed records
  remaining <- df |> filter(!id %in% already_done)
  n_total <- nrow(df)
  n_remaining <- nrow(remaining)
  log_msg(paste("Records to process:", n_remaining, "/", n_total))

  if (n_remaining == 0) {
    log_msg("All records already processed — returning checkpoint data")
    return(checkpoint)
  }

  # Process records one at a time
  checkpoint_interval <- 200
  for (i in seq_len(n_remaining)) {
    record <- remaining[i, ]

    # Check word quota before sending
    record_words <- count_words(record$text)
    if (words_used + record_words > cfg$gptzero_monthly_word_limit * 0.95) {
      log_msg(paste("Approaching monthly word limit (",
                    format(words_used, big.mark = ","), "/",
                    format(cfg$gptzero_monthly_word_limit, big.mark = ","),
                    "). Stopping gracefully."), level = "WARN")
      break
    }

    # Call API
    result <- call_gptzero_single(record$text, api_key)
    words_used <- words_used + record_words

    results[[length(results) + 1]] <- list(
      id              = record$id,
      gptzero_prob    = result$completely_generated_prob,
      gptzero_class   = result$predicted_class,
      is_ai_generated = if (!is.na(result$completely_generated_prob)) {
        result$completely_generated_prob >= ai_threshold
      } else {
        NA
      }
    )

    # Rate limiting (be respectful to API)
    Sys.sleep(0.2)

    # Progress logging
    n_done <- length(already_done) + i
    if (i %% 100 == 0 || i == n_remaining) {
      log_msg(paste0("Progress: ", n_done, "/", n_total,
                     " (", sprintf("%.1f%%", 100 * n_done / n_total), ")",
                     " | Words used: ", format(words_used, big.mark = ",")))
    }

    # Checkpoint
    if (i %% checkpoint_interval == 0 || i == n_remaining) {
      results_df <- bind_rows(lapply(results, as.data.frame))
      save_checkpoint(results_df, "gptzero")
    }
  }

  # Final result
  results_df <- bind_rows(lapply(results, as.data.frame))

  n_ai    <- sum(results_df$is_ai_generated == TRUE, na.rm = TRUE)
  n_human <- sum(results_df$is_ai_generated == FALSE, na.rm = TRUE)
  n_na    <- sum(is.na(results_df$is_ai_generated))
  log_msg(paste("GPTZero complete. AI-flagged:", n_ai,
                "| Human:", n_human, "| Unscored:", n_na))
  log_msg(paste("Total words sent:", format(words_used, big.mark = ",")))

  results_df
}

# Null coalescing operator (if not already available)
if (!exists("%||%")) `%||%` <- function(x, y) if (is.null(x)) y else x
