# R/classify_relevance.R — LLM-based relevance classification via ellmer
#
# Uses Claude (via ellmer::chat_anthropic) to classify each record as relevant
# or not relevant to AI use in healthcare. The full_context field (built in Step 2)
# is passed so comments are evaluated with their parent thread context.
#
# Features: checkpointing, rate-limit handling, cost estimation, resumability

library(ellmer)
library(jsonlite)
library(dplyr)

# System prompt for relevance classification
RELEVANCE_SYSTEM_PROMPT <- paste0(
  "You are classifying Reddit discussion excerpts for relevance to AI use in healthcare.\n\n",
  "Relevant discussions address: AI/ML tools in clinical settings, medical diagnosis/imaging AI, ",
  "clinical decision support systems, AI in drug discovery, healthcare data/EHR AI, robotic surgery AI, ",
  "AI regulation in medicine, bias in medical AI, clinician attitudes toward AI tools, patient safety ",
  "from AI errors, or related policy/ethical discussions about AI in medical contexts.\n\n",
  "NOT relevant: general AI discussions without healthcare context, general healthcare discussions ",
  "without AI, personal medical advice, non-clinical AI (e.g. art, coding assistants), AI in ",
  "non-medical scientific research.\n\n",
  "Respond with valid JSON only \u2014 no markdown, no explanation outside the JSON:\n",
  "{\"relevant\": true/false, \"confidence\": \"high\"/\"medium\"/\"low\", \"reason\": \"one sentence\"}"
)

#' Classify a single record for relevance
#'
#' @param full_context Character string (the full_context field from thread reconstruction)
#' @param chat Chat object from ellmer::chat_anthropic()
#' @return List with is_relevant (logical), confidence (character), reason (character)
classify_single <- function(full_context, chat) {
  tryCatch({
    response <- chat$chat(full_context)

    # Parse JSON from response
    parsed <- tryCatch(
      fromJSON(response),
      error = function(e) {
        # Try to extract JSON from response if it contains extra text
        json_match <- regmatches(response, regexpr("\\{[^}]+\\}", response))
        if (length(json_match) > 0) {
          fromJSON(json_match[1])
        } else {
          stop("No valid JSON found")
        }
      }
    )

    list(
      is_relevant = as.logical(parsed$relevant),
      confidence  = as.character(parsed$confidence %||% "unknown"),
      reason      = as.character(parsed$reason %||% "")
    )
  }, error = function(e) {
    list(
      is_relevant = NA,
      confidence  = "error",
      reason      = paste("parse_error:", conditionMessage(e))
    )
  })
}

#' Classify a batch of records for relevance with checkpointing
#'
#' @param df Tibble with id and full_context columns
#' @param cfg Configuration list (default: CFG)
#' @return Tibble with id, is_relevant, relevance_confidence, relevance_reason
classify_relevance_batch <- function(df, cfg = CFG) {
  # Check for existing checkpoint
  checkpoint <- load_latest_checkpoint("relevance")
  already_done <- character(0)
  results <- list()

  if (!is.null(checkpoint)) {
    already_done <- checkpoint$id
    results <- split(checkpoint, seq_len(nrow(checkpoint)))
    results <- lapply(results, as.list)
    log_msg(paste("Resuming from checkpoint:", length(already_done), "records already classified"))
  }

  # Filter to unclassified records
  remaining <- df |> filter(!id %in% already_done)
  n_total <- nrow(df)
  n_remaining <- nrow(remaining)
  log_msg(paste("Records to classify:", n_remaining, "/", n_total))

  if (n_remaining == 0) {
    log_msg("All records already classified — returning checkpoint data")
    return(checkpoint)
  }

  # Create ellmer chat session
  chat <- chat_anthropic(
    model  = cfg$llm_model,
    system = RELEVANCE_SYSTEM_PROMPT,
    api_key = cfg$anthropic_api_key
  )
  chat@turns <- list()  # ensure clean state

  # Rate limit tracking
  sleep_time <- 0.1
  n_429s <- 0
  cost_estimate <- 0

  # Process records
  batch_size <- 100  # checkpoint interval
  for (i in seq_len(n_remaining)) {
    record <- remaining[i, ]

    # Reset chat turns to avoid context accumulation
    chat@turns <- list()

    # Classify
    result <- classify_single(record$full_context, chat)

    results[[length(results) + 1]] <- list(
      id                   = record$id,
      is_relevant          = result$is_relevant,
      relevance_confidence = result$confidence,
      relevance_reason     = result$reason
    )

    # Rate limiting
    Sys.sleep(sleep_time)

    # Cost tracking (~200 tokens per call, ~$3/M input tokens for Sonnet)
    cost_estimate <- cost_estimate + (200 / 1e6) * 3

    # Progress logging
    n_done <- length(already_done) + i
    if (i %% 50 == 0 || i == n_remaining) {
      log_msg(paste0("Progress: ", n_done, "/", n_total,
                     " (", sprintf("%.1f%%", 100 * n_done / n_total), ")",
                     " | Est. cost so far: $", sprintf("%.2f", cost_estimate)))
    }

    # Checkpoint every batch_size records
    if (i %% batch_size == 0 || i == n_remaining) {
      results_df <- bind_rows(lapply(results, as.data.frame))
      save_checkpoint(results_df, "relevance")
    }
  }

  # Final result
  results_df <- bind_rows(lapply(results, as.data.frame))
  log_msg(paste("Classification complete.", nrow(results_df), "records processed"))
  log_msg(paste("  Relevant:", sum(results_df$is_relevant == TRUE, na.rm = TRUE),
                "| Not relevant:", sum(results_df$is_relevant == FALSE, na.rm = TRUE),
                "| Errors:", sum(is.na(results_df$is_relevant))))
  log_msg(paste("  Estimated API cost: $", sprintf("%.2f", cost_estimate)))

  results_df
}

# Null coalescing operator (if not already available)
`%||%` <- function(x, y) if (is.null(x)) y else x
