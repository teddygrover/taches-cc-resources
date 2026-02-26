#!/usr/bin/env Rscript
# scripts/04_gptzero_filter.R — Pipeline Step 4: GPTZero AI-Detection Filtering
#
# Uses GPTZero API to flag AI-generated content. Records above the threshold
# are excluded from the downstream pipeline (but kept in the audit file).
#
# QUOTA: 300,000 words/month. Check estimate before running full batch.
#
# Prerequisites:
#   - data/processed/03_relevance_classified.rds exists (from Step 3)
#   - GPTZERO_API_KEY set in .Renviron or config/config.R
#
# Output:
#   - data/processed/04_human_filtered.rds   (human-only records for ABSA pipeline)
#   - data/processed/04_gptzero_audit.rds    (all records with GPTZero scores, for audit)

# ---- CONFIGURATION ----
DRY_RUN <- TRUE  # Set to FALSE after reviewing dry run results
DRY_RUN_SIZE <- 20
# ---- END CONFIGURATION ----

library(here)

source(here("R", "utils.R"))
load_config()

source(here("R", "gptzero_filter.R"))

log_msg("=== Pipeline Step 4: GPTZero AI-Detection Filtering ===")
if (DRY_RUN) log_msg("*** DRY RUN MODE — processing first 20 records only ***", level = "WARN")

# Load relevant records
input_path <- file.path(CFG$path_processed, "03_relevance_classified.rds")
if (!file.exists(input_path)) {
  stop("Input file not found: ", input_path, "\nRun scripts/03_classify_relevance.R first.")
}
df_relevant <- readRDS(input_path)
log_msg(paste("Loaded", nrow(df_relevant), "relevant records from", basename(input_path)))

# Dry run: subset
if (DRY_RUN) {
  df_relevant <- head(df_relevant, DRY_RUN_SIZE)
  log_msg(paste("Dry run: using first", DRY_RUN_SIZE, "records"))
}

# Pre-flight quota check
total_words <- sum(count_words(df_relevant$text))
log_msg(paste("Total words to analyse:", format(total_words, big.mark = ","),
              "/ Monthly limit: 300,000"))
if (total_words > 300000) {
  log_msg(paste("WARNING: Dataset exceeds monthly quota.",
                "Consider processing in batches across months,",
                "or filtering to highest-priority records first."), level = "WARN")
}

# Run GPTZero
gptzero_results <- run_gptzero_filter(df_relevant)

# Join results
df_gptzero <- df_relevant |>
  dplyr::left_join(gptzero_results, by = "id")

# Summary
n_ai       <- sum(df_gptzero$is_ai_generated == TRUE, na.rm = TRUE)
n_human    <- sum(df_gptzero$is_ai_generated == FALSE, na.rm = TRUE)
n_no_score <- sum(is.na(df_gptzero$is_ai_generated))
log_msg(paste("GPTZero results \u2014 AI-flagged:", n_ai,
              "| Human:", n_human, "| Unscored:", n_no_score))

if (DRY_RUN) {
  log_msg("=== DRY RUN RESULTS ===")
  review_cols <- c("id", "type", "subreddit", "gptzero_prob", "gptzero_class", "is_ai_generated")
  review_cols <- intersect(review_cols, names(df_gptzero))
  print(df_gptzero[, review_cols], n = DRY_RUN_SIZE)
  log_msg("*** Review the above. If results look correct, set DRY_RUN <- FALSE and re-run. ***")
} else {
  # Save audit file (all records with scores)
  saveRDS(df_gptzero, file.path(CFG$path_processed, "04_gptzero_audit.rds"))

  # Save human-only for downstream pipeline
  # Records with NA scores (unscored due to quota exhaustion) are KEPT — conservative approach
  df_human <- dplyr::filter(df_gptzero, is_ai_generated == FALSE | is.na(is_ai_generated))
  saveRDS(df_human, file.path(CFG$path_processed, "04_human_filtered.rds"))
  log_msg(paste("Final human-filtered dataset:", nrow(df_human), "records saved to 04_human_filtered.rds"))
  log_msg(paste("Audit file:", nrow(df_gptzero), "records saved to 04_gptzero_audit.rds"))
}

log_msg("=== Phase 01 Preprocessing Complete ===")
log_msg("Next: Phase 02 — ABSA Labelling (02-01-PLAN.md)")
log_msg("=== Done ===")
