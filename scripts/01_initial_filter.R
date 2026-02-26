#!/usr/bin/env Rscript
# scripts/01_initial_filter.R — Pipeline Step 1: Load CSVs and apply initial filters
#
# Prerequisites:
#   - CSV files placed in data/raw/
#   - config/config.R exists (copy from config/config_template.R)
#   - Packages installed via renv::restore()
#
# Output: data/processed/01_initial_filtered.rds

library(here)

source(here("R", "utils.R"))
load_config()

source(here("R", "load_data.R"))
source(here("R", "filter_initial.R"))

log_msg("=== Pipeline Step 1: Data Loading & Initial Filtering ===")

# Load all CSVs from data/raw/
df_raw <- load_reddit_data()
log_msg(paste("Raw records loaded:", nrow(df_raw)))

# Apply initial filters (date, dedup, text length)
df_filtered <- apply_initial_filters(df_raw)

# Save output
output_path <- file.path(CFG$path_processed, "01_initial_filtered.rds")
saveRDS(df_filtered, output_path)
log_msg(paste("Saved:", nrow(df_filtered), "records to", basename(output_path)))

# Summary statistics
log_msg("=== Summary ===")
log_msg(paste("  Posts:", sum(df_filtered$type == "post", na.rm = TRUE)))
log_msg(paste("  Comments:", sum(df_filtered$type == "comment", na.rm = TRUE)))
log_msg(paste("  Subreddits:", length(unique(df_filtered$subreddit))))
log_msg(paste("  Date range:", min(df_filtered$created_at, na.rm = TRUE), "to",
              max(df_filtered$created_at, na.rm = TRUE)))
log_msg("=== Done ===")
