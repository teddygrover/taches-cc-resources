# R/utils.R — Shared helper functions for the Reddit AI-in-Healthcare pipeline

#' Load project configuration from config/config.R
#' Sets CFG in the global environment
load_config <- function() {
  config_path <- here::here("config", "config.R")
  if (!file.exists(config_path)) {
    stop(
      "Missing config/config.R — copy config/config_template.R and fill in values.\n",
      "  cp config/config_template.R config/config.R"
    )
  }
  source(config_path, local = FALSE)
  invisible(CFG)
}

#' Log a timestamped message to console
#' @param msg Character message to log
#' @param level One of "INFO", "WARN", "ERROR"
log_msg <- function(msg, level = "INFO") {
  timestamp <- format(Sys.time(), "[%Y-%m-%d %H:%M:%S]")
  cat(sprintf("%s [%s] %s\n", timestamp, level, msg))
}

#' Save a checkpoint RDS with timestamp
#' @param data The data to save
#' @param name Checkpoint name prefix (e.g., "relevance", "gptzero")
save_checkpoint <- function(data, name) {
  dir <- here::here("data", "checkpoints")
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  path <- file.path(dir, paste0(name, "_", timestamp, ".rds"))
  saveRDS(data, path)
  log_msg(paste("Checkpoint saved:", basename(path)))
  invisible(path)
}

#' Load the most recent checkpoint matching a name pattern
#' @param name Checkpoint name prefix to match
#' @return The loaded data, or NULL if no checkpoint found
load_latest_checkpoint <- function(name) {
  dir <- here::here("data", "checkpoints")
  if (!dir.exists(dir)) return(NULL)

  files <- list.files(dir, pattern = paste0("^", name, "_.*\\.rds$"), full.names = TRUE)
  if (length(files) == 0) return(NULL)

  # Sort by modification time, pick newest
  latest <- files[which.max(file.mtime(files))]
  log_msg(paste("Resuming from checkpoint:", basename(latest)))
  readRDS(latest)
}

#' Truncate text to a maximum number of characters
#' @param text Character string to truncate
#' @param max_chars Maximum allowed characters
#' @return Truncated string with "..." appended if truncated
truncate_text <- function(text, max_chars = 500) {
  ifelse(
    !is.na(text) & nchar(text) > max_chars,
    paste0(substr(text, 1, max_chars), "..."),
    text
  )
}
