#!/usr/bin/env Rscript
# scripts/03_classify_relevance.R — Pipeline Step 3: LLM Relevance Classification
#
# COST ESTIMATE: ~$0.60 per 1000 records at Claude Sonnet pricing (~200 tokens/call).
# For 50k records: ~$30. Run DRY_RUN = TRUE first to validate classification quality.
#
# Prerequisites:
#   - data/processed/02_with_thread_context.rds exists (from Step 2)
#   - ANTHROPIC_API_KEY set in .Renviron or config/config.R
#
# Output:
#   - data/processed/03_relevance_classified.rds     (relevant records only)
#   - data/processed/03_relevance_classified_all.rds  (all records with labels, for audit)

# ---- CONFIGURATION ----
DRY_RUN <- TRUE  # Set to FALSE after reviewing dry run results
DRY_RUN_SIZE <- 50
# ---- END CONFIGURATION ----

library(here)

source(here("R", "utils.R"))
load_config()

source(here("R", "classify_relevance.R"))

log_msg("=== Pipeline Step 3: LLM Relevance Classification ===")
if (DRY_RUN) log_msg("*** DRY RUN MODE — processing first 50 records only ***", level = "WARN")

# Load threaded data
input_path <- file.path(CFG$path_processed, "02_with_thread_context.rds")
if (!file.exists(input_path)) {
  stop("Input file not found: ", input_path, "\nRun scripts/02_thread_reconstruct.R first.")
}
df_threaded <- readRDS(input_path)
log_msg(paste("Loaded", nrow(df_threaded), "records from", basename(input_path)))

# Dry run: subset
if (DRY_RUN) {
  df_threaded <- head(df_threaded, DRY_RUN_SIZE)
  log_msg(paste("Dry run: using first", DRY_RUN_SIZE, "records"))
}

# Estimate cost
n_records <- nrow(df_threaded)
est_cost <- (n_records / 1000) * 0.60
log_msg(paste("Estimated API cost:", sprintf("$%.2f", est_cost), "for", n_records, "records"))

# Run classification
relevance_results <- classify_relevance_batch(df_threaded)

# Join results back
df_classified <- df_threaded |>
  dplyr::left_join(relevance_results, by = "id")

# Summary
n_relevant   <- sum(df_classified$is_relevant == TRUE, na.rm = TRUE)
n_irrelevant <- sum(df_classified$is_relevant == FALSE, na.rm = TRUE)
n_error      <- sum(is.na(df_classified$is_relevant))
log_msg(paste("Relevance results \u2014 Relevant:", n_relevant,
              "| Not relevant:", n_irrelevant, "| Errors:", n_error))

if (DRY_RUN) {
  # Print sample results for review
  log_msg("=== DRY RUN RESULTS (review before running full batch) ===")
  review_cols <- c("id", "type", "subreddit", "is_relevant", "relevance_confidence", "relevance_reason")
  review_cols <- intersect(review_cols, names(df_classified))
  print(df_classified[, review_cols], n = DRY_RUN_SIZE)
  log_msg("*** Review the above. If quality is good, set DRY_RUN <- FALSE and re-run. ***")
} else {
  # Save full results (including non-relevant, for audit)
  saveRDS(df_classified, file.path(CFG$path_processed, "03_relevance_classified_all.rds"))

  # Save relevant-only for downstream pipeline
  df_relevant <- dplyr::filter(df_classified, is_relevant == TRUE)
  saveRDS(df_relevant, file.path(CFG$path_processed, "03_relevance_classified.rds"))
  log_msg(paste("Saved", nrow(df_relevant), "relevant records to 03_relevance_classified.rds"))
  log_msg(paste("Saved", nrow(df_classified), "total records to 03_relevance_classified_all.rds (audit)"))
}

log_msg("=== Done ===")
