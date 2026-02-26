#!/usr/bin/env Rscript
# scripts/02_thread_reconstruct.R — Pipeline Step 2: Thread Reconstruction
#
# Prerequisites:
#   - data/processed/01_initial_filtered.rds exists (from Step 1)
#
# Output: data/processed/02_with_thread_context.rds

library(here)

source(here("R", "utils.R"))
load_config()

source(here("R", "thread_reconstruct.R"))

log_msg("=== Pipeline Step 2: Thread Reconstruction ===")

# Load filtered data
input_path <- file.path(CFG$path_processed, "01_initial_filtered.rds")
if (!file.exists(input_path)) {
  stop("Input file not found: ", input_path, "\nRun scripts/01_initial_filter.R first.")
}
df_filtered <- readRDS(input_path)
log_msg(paste("Loaded", nrow(df_filtered), "records from", basename(input_path)))

# Reconstruct threads (assign thread_id, parent_text, root_post_text, thread_depth)
df_threaded <- reconstruct_threads(df_filtered)

# Build full_context strings for LLM classification
df_threaded <- build_full_context(df_threaded)

# Save output
output_path <- file.path(CFG$path_processed, "02_with_thread_context.rds")
saveRDS(df_threaded, output_path)
log_msg(paste("Thread reconstruction complete:", nrow(df_threaded), "records"))
log_msg(paste("  With resolved parent context:",
              sum(!is.na(df_threaded$parent_text) & df_threaded$type == "comment")))
log_msg(paste("  Saved to:", basename(output_path)))
log_msg("=== Done ===")
