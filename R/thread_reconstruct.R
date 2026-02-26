# R/thread_reconstruct.R — Link comments to parent posts, build thread context
#
# IMPORTANT: parsedParentId in this dataset is already a bare ID (no t3_/t1_ prefixes).
# Do NOT apply prefix stripping — use parent_id directly as the join key.
# parsedPostId provides a direct link to the root post for any comment.

library(dplyr)

#' Reconstruct threads: assign thread_id, parent_text, root_post_text, thread_depth
#'
#' @param df Tibble from 01_initial_filtered.rds with canonical column names
#' @return Tibble augmented with thread context fields
reconstruct_threads <- function(df) {
  log_msg(paste("Starting thread reconstruction for", nrow(df), "records"))

  n_posts    <- sum(df$type == "post", na.rm = TRUE)
  n_comments <- sum(df$type == "comment", na.rm = TRUE)
  log_msg(paste("  Posts:", n_posts, "| Comments:", n_comments))

  # Build lookup tables
  # Post lookup: id → title + text
  posts <- df |>
    filter(type == "post") |>
    select(id, title, text) |>
    mutate(post_combined = ifelse(
      !is.na(title) & nchar(trimws(title)) > 0,
      paste0(title, "\n\n", text),
      text
    ))
  post_lookup <- setNames(posts$post_combined, posts$id)
  post_title_lookup <- setNames(posts$title, posts$id)

  # All records lookup: id → text
  text_lookup <- setNames(df$text, df$id)

  # Assign thread_id
  # For posts: thread_id = own id
  # For comments: thread_id = post_id (parsedPostId maps directly to root post)
  df$thread_id <- ifelse(df$type == "post", df$id, df$post_id)

  # Compute thread_depth
  # 0 = post, 1 = direct reply to post, 2+ = nested
  df$thread_depth <- compute_thread_depth(df)

  # Assign parent_text
  df$parent_text <- text_lookup[df$parent_id]

  # Assign root_post_text (the full post text for any record in the thread)
  df$root_post_text <- post_lookup[df$thread_id]

  # Assign root_post_title (for context building)
  df$root_post_title <- post_title_lookup[df$thread_id]

  # Log resolution stats
  comments <- df |> filter(type == "comment")
  n_resolved_parent <- sum(!is.na(comments$parent_text))
  n_resolved_root   <- sum(!is.na(comments$root_post_text))
  n_total_comments  <- nrow(comments)

  log_msg(paste("Thread resolution: ",
                n_resolved_parent, "/", n_total_comments, "comments have resolved parent text",
                sprintf("(%.1f%%)", 100 * n_resolved_parent / max(n_total_comments, 1))))
  log_msg(paste("Root post resolution:",
                n_resolved_root, "/", n_total_comments, "comments have resolved root post",
                sprintf("(%.1f%%)", 100 * n_resolved_root / max(n_total_comments, 1))))

  df
}

#' Compute thread depth for each record
#'
#' post = 0, direct reply to post = 1, nested = 2+
#' Uses iterative parent-chain walking with cycle detection.
#' @param df Tibble with id, type, parent_id, post_id columns
#' @return Integer vector of thread depths
compute_thread_depth <- function(df) {
  depths <- rep(NA_integer_, nrow(df))

  # Posts are always depth 0
  depths[df$type == "post"] <- 0L

  # Build parent lookup: id → parent_id
  parent_lookup <- setNames(df$parent_id, df$id)

  # Build set of post IDs for checking if parent is a post

  post_ids <- df$id[df$type == "post"]

  # Process comments
  comment_idx <- which(df$type == "comment")

  for (i in comment_idx) {
    pid <- df$parent_id[i]
    depth <- 0L
    visited <- character(0)
    max_depth <- 10L  # prevent infinite loops on malformed data

    # Walk up the parent chain until we hit a post or exhaust the chain
    while (!is.na(pid) && depth < max_depth) {
      depth <- depth + 1L

      # Cycle detection
      if (pid %in% visited) {
        depth <- NA_integer_
        break
      }
      visited <- c(visited, pid)

      # If parent is a post, we're done
      if (pid %in% post_ids) break

      # Walk up one level
      next_pid <- parent_lookup[pid]
      if (is.na(next_pid) || next_pid == pid) break
      pid <- next_pid
    }

    depths[i] <- depth
  }

  # Log depth distribution
  depth_table <- table(depths, useNA = "ifany")
  log_msg(paste("Thread depth distribution:", paste(names(depth_table), depth_table, sep = "=", collapse = ", ")))

  depths
}

#' Build full_context field for LLM relevance classification
#'
#' Constructs a context string that includes parent/root post information
#' so the LLM can evaluate comment relevance in context.
#' @param df Tibble from reconstruct_threads() with thread context fields
#' @return Tibble with full_context column added
build_full_context <- function(df) {
  log_msg("Building full_context strings for LLM classification")

  df$full_context <- vapply(seq_len(nrow(df)), function(i) {
    row <- df[i, ]

    if (row$type == "post") {
      # Root posts: include title and body
      title_str <- if (!is.na(row$title) && nchar(trimws(row$title)) > 0) {
        paste0("Title: ", row$title, "\n\n")
      } else {
        ""
      }
      paste0("[POST in r/", coalesce(row$subreddit, "unknown"), "]\n",
             title_str, row$text)

    } else if (!is.na(row$thread_depth) && row$thread_depth == 1L) {
      # Direct replies to a post
      root_title <- if (!is.na(row$root_post_title) && nchar(trimws(row$root_post_title)) > 0) {
        paste0("Parent post title: ", row$root_post_title, "\n")
      } else {
        ""
      }
      root_body <- if (!is.na(row$root_post_text)) {
        paste0("Parent post body: ", truncate_text(row$root_post_text, 500), "\n\n")
      } else {
        ""
      }
      paste0("[COMMENT in r/", coalesce(row$subreddit, "unknown"), " replying to post]\n",
             root_title, root_body,
             "[COMMENT TEXT]\n", row$text)

    } else if (!is.na(row$thread_depth) && row$thread_depth >= 2L) {
      # Nested comments
      root_title <- if (!is.na(row$root_post_title) && nchar(trimws(row$root_post_title)) > 0) {
        paste0("Root post title: ", row$root_post_title, "\n")
      } else {
        ""
      }
      parent_str <- if (!is.na(row$parent_text)) {
        paste0("Direct parent: ", truncate_text(row$parent_text, 300), "\n\n")
      } else {
        ""
      }
      paste0("[NESTED COMMENT in r/", coalesce(row$subreddit, "unknown"), "]\n",
             root_title, parent_str,
             "[COMMENT TEXT]\n", row$text)

    } else {
      # Unresolved parent context (thread_depth == NA)
      paste0("[COMMENT in r/", coalesce(row$subreddit, "unknown"),
             " \u2014 parent context unavailable]\n", row$text)
    }
  }, character(1))

  log_msg(paste("Built full_context for", nrow(df), "records"))
  log_msg(paste("  Context length stats — min:", min(nchar(df$full_context)),
                "median:", median(nchar(df$full_context)),
                "max:", max(nchar(df$full_context))))

  df
}
