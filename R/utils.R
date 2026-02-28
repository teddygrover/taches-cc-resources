# R/utils.R
# Shared utility functions sourced by all pipeline scripts.

library(here)

# ---------------------------------------------------------------------------
# load_config()
# Sources config/config.R and assigns CFG to the global environment.
# ---------------------------------------------------------------------------
load_config <- function(config_path = here::here("config", "config.R")) {
  if (!file.exists(config_path)) {
    stop(
      "Missing config/config.R — copy config/config_template.R and fill in your values.\n",
      "Expected path: ", config_path
    )
  }
  source(config_path, local = FALSE)  # assigns CFG in global env
  invisible(CFG)
}

# ---------------------------------------------------------------------------
# log_msg(msg, level)
# Writes a timestamped message to the console.
# ---------------------------------------------------------------------------
log_msg <- function(msg, level = "INFO") {
  ts <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  cat(sprintf("[%s] [%s] %s\n", ts, level, msg))
}

# ---------------------------------------------------------------------------
# save_checkpoint(data, name)
# Saves data as an RDS file to data/checkpoints/{name}_{timestamp}.rds.
# Uses CFG$path_checkpoints if available, otherwise falls back to here().
# ---------------------------------------------------------------------------
save_checkpoint <- function(data, name) {
  chk_dir <- tryCatch(
    CFG$path_checkpoints,
    error = function(e) here::here("data", "checkpoints")
  )
  if (!dir.exists(chk_dir)) dir.create(chk_dir, recursive = TRUE)
  ts  <- format(Sys.time(), "%Y%m%d_%H%M%S")
  out <- file.path(chk_dir, paste0(name, "_", ts, ".rds"))
  saveRDS(data, out)
  log_msg(paste("Checkpoint saved:", out))
  invisible(out)
}

# ---------------------------------------------------------------------------
# load_latest_checkpoint(name)
# Loads the most recent checkpoint file matching {name}_*.rds.
# ---------------------------------------------------------------------------
load_latest_checkpoint <- function(name) {
  chk_dir <- tryCatch(
    CFG$path_checkpoints,
    error = function(e) here::here("data", "checkpoints")
  )
  pattern <- paste0("^", name, "_.*\\.rds$")
  files   <- list.files(chk_dir, pattern = pattern, full.names = TRUE)
  if (length(files) == 0) {
    stop("No checkpoint found matching pattern: ", name, "_*.rds in ", chk_dir)
  }
  latest <- files[which.max(file.mtime(files))]
  log_msg(paste("Loading checkpoint:", latest))
  readRDS(latest)
}
