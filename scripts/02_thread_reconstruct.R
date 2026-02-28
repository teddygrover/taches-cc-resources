# scripts/02_thread_reconstruct.R
# ---------------------------------------------------------------------------
# Pipeline step 02: Reconstruct threads and build LLM context strings.
#
# Prerequisites:
#   - scripts/01_initial_filter.R has been run
#   - data/processed/01_initial_filtered.rds exists
#
# Outputs:
#   data/processed/02_with_thread_context.rds
#
# Usage:
#   Rscript scripts/02_thread_reconstruct.R
# ---------------------------------------------------------------------------

source("R/utils.R"); load_config()
source("R/thread_reconstruct.R")

log_msg("=== Pipeline Step 02: Thread Reconstruction ===")

df_filtered <- readRDS(file.path(CFG$path_processed, "01_initial_filtered.rds"))
log_msg(paste("Loaded", nrow(df_filtered), "records from 01_initial_filtered.rds"))

df_threaded <- reconstruct_threads(df_filtered)
df_threaded <- build_full_context(df_threaded)

out_path <- file.path(CFG$path_processed, "02_with_thread_context.rds")
saveRDS(df_threaded, out_path)

log_msg(paste(
  "Thread reconstruction complete:", nrow(df_threaded), "records;",
  sum(!is.na(df_threaded$parent_text)), "with resolved parent context"
))
log_msg(paste("Saved to", out_path))
log_msg("Step 02 complete. Next: Rscript scripts/03_relevance_classify.R")
