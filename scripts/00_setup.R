# scripts/00_setup.R
# ---------------------------------------------------------------------------
# ONE-TIME PROJECT SETUP — run this first, before any other script.
# Requires R >= 4.1 and internet access.
#
# Usage (from project root):
#   Rscript scripts/00_setup.R
# Or interactively in RStudio:
#   source("scripts/00_setup.R")
# ---------------------------------------------------------------------------

cat("=== Reddit ABSA Pipeline — Project Setup ===\n\n")

# ── 1. Bootstrap renv ────────────────────────────────────────────────────────
if (!requireNamespace("renv", quietly = TRUE)) {
  cat("Installing renv...\n")
  install.packages("renv")
}

cat("Initialising renv project library...\n")
renv::init(bare = TRUE)   # bare = TRUE: initialise without auto-installing discovered packages

# Install 'here' first — it is sourced at the top level of utils.R and
# config files, so it must be present before any other script runs.
cat("Installing 'here' (required before all other scripts)...\n")
renv::install("here")

# ── 2. Install required packages ─────────────────────────────────────────────
cat("\nInstalling project packages (this may take several minutes)...\n")

pkgs <- c(
  # Data wrangling
  "tidyverse",
  "data.table",
  "arrow",        # Parquet read/write (Phase 03 Python↔R handoff)
  "janitor",      # clean_names(), tabyl()
  "readxl",       # xlsx ingestion support in load_reddit_data()
  "digest",       # digest() for text hashing in deduplication

  # LLM / API calls
  "ellmer",       # Claude API client (install from CRAN or GitHub below)
  "httr2",        # GPTZero API calls (Phase 01-05)
  "jsonlite",     # JSON parsing for LLM responses

  # Progress / async
  "future",
  "future.apply",
  "progressr",

  # Shiny dashboard (Phase 04)
  "shiny",
  "bslib",
  "DT",
  "plotly",
  "shinyWidgets",

  # Utilities
  "here"          # Portable paths via here::here()
)

# Install ellmer from GitHub if not available on CRAN
tryCatch(
  renv::install("ellmer"),
  error = function(e) {
    cat("ellmer not found on CRAN — installing from GitHub (tidyverse/ellmer)...\n")
    renv::install("tidyverse/ellmer")
  }
)

# Install remaining packages
renv::install(setdiff(pkgs, "ellmer"))

# ── 3. Snapshot to lock versions ─────────────────────────────────────────────
cat("\nSnapshotting package versions to renv.lock...\n")
renv::snapshot()

# ── 4. Verify critical packages ──────────────────────────────────────────────
cat("\nVerifying critical packages load correctly...\n")
stopifnot(
  "tidyverse failed to load" = requireNamespace("tidyverse", quietly = TRUE),
  "ellmer failed to load"    = requireNamespace("ellmer",    quietly = TRUE),
  "here failed to load"      = requireNamespace("here",      quietly = TRUE),
  "httr2 failed to load"     = requireNamespace("httr2",     quietly = TRUE),
  "arrow failed to load"     = requireNamespace("arrow",     quietly = TRUE)
)

cat("\n=== Setup complete ===\n")
cat("Next steps:\n")
cat("  1. Copy your Reddit CSVs to data/raw/\n")
cat("  2. Set ANTHROPIC_API_KEY and GPTZERO_API_KEY in ~/.Renviron\n")
cat("  3. Run: Rscript scripts/01_initial_filter.R\n")
