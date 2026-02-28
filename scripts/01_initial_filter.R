# scripts/01_initial_filter.R
# ---------------------------------------------------------------------------
# Pipeline step 01: Load raw Reddit CSVs and apply initial filters.
#
# Prerequisites:
#   - scripts/00_setup.R has been run (renv initialised, packages installed)
#   - Reddit CSV files are present in data/raw/
#   - config/config.R exists (copy from config/config_template.R)
#
# Outputs:
#   data/processed/01_initial_filtered.rds
#
# Usage:
#   Rscript scripts/01_initial_filter.R
# ---------------------------------------------------------------------------

source("R/utils.R");  load_config()
source("R/load_data.R")
source("R/filter_initial.R")

log_msg("=== Pipeline Step 01: Initial Filtering ===")

df_raw      <- load_reddit_data()
df_filtered <- apply_initial_filters(df_raw)

out_path <- file.path(CFG$path_processed, "01_initial_filtered.rds")
saveRDS(df_filtered, out_path)
log_msg(paste("Saved:", nrow(df_filtered), "records to", out_path))
log_msg("Step 01 complete. Next: Rscript scripts/02_thread_reconstruct.R")
