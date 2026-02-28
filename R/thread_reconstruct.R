# R/thread_reconstruct.R
# ---------------------------------------------------------------------------
# reconstruct_threads(df)  — adds thread_id, parent_text, root_post_text,
#                            and thread_depth to every record.
#
# build_full_context(df)   — adds full_context string used by the LLM
#                            relevance classifier (Plan 01-04).
#
# Schema notes (confirmed against actual data):
#   - parent_id values are already bare IDs — NO t3_/t1_ prefix stripping.
#   - post_id (from parsedPostId) directly identifies the root post; no
#     chain-walking needed for thread_id assignment.
#   - Root posts have parent_id == NA.
#   - dataType values are exactly "post" or "comment".
# ---------------------------------------------------------------------------

library(dplyr)

# ---------------------------------------------------------------------------
# Helper: truncate text to max_chars, appending "..." if truncated.
# ---------------------------------------------------------------------------
.truncate <- function(text, max_chars) {
  ifelse(
    !is.na(text) & nchar(text) > max_chars,
    paste0(substr(text, 1, max_chars), "..."),
    text
  )
}

# ---------------------------------------------------------------------------
# reconstruct_threads(df)
# ---------------------------------------------------------------------------
reconstruct_threads <- function(df) {

  # ── 1. Assign thread_id ──────────────────────────────────────────────────
  # Posts:    thread_id = own id
  # Comments: thread_id = post_id (direct root post link — no chain walk)
  df <- df |>
    mutate(
      thread_id = dplyr::if_else(type == "post", id, post_id)
    )

  # ── 2. Build id → text lookup tables ────────────────────────────────────
  # Posts: combine title + body for richer context
  post_lookup <- df |>
    filter(type == "post") |>
    mutate(full_text = paste0(
      dplyr::if_else(!is.na(title) & nchar(trimws(title)) > 0,
                     paste0(title, "\n\n"), ""),
      dplyr::if_else(!is.na(text), text, "")
    )) |>
    select(id, full_text, title)

  # All records: id → text (for parent lookups)
  all_text_lookup <- df |>
    select(id, text)

  post_text_map  <- setNames(post_lookup$full_text, post_lookup$id)
  post_title_map <- setNames(post_lookup$title,     post_lookup$id)
  all_text_map   <- setNames(all_text_lookup$text,  all_text_lookup$id)

  # ── 3. Resolve parent_text and root_post_text ─────────────────────────────
  df <- df |>
    mutate(
      parent_text    = dplyr::if_else(
        is.na(parent_id),
        NA_character_,
        all_text_map[parent_id]
      ),
      root_post_text = dplyr::if_else(
        type == "post",
        text,                         # A post is its own root
        post_text_map[post_id]        # NA if root post filtered/absent
      ),
      root_post_title = dplyr::if_else(
        type == "post",
        title,
        post_title_map[post_id]
      )
    )

  # ── 4. Compute thread_depth ───────────────────────────────────────────────
  # Posts = 0.  Comments = iterative chain walk up parent_id until a post
  # is reached or the parent is not in the dataset.  Capped at 10 levels.
  id_to_parent <- setNames(df$parent_id, df$id)
  id_to_type   <- setNames(df$type,      df$id)

  compute_depth <- function(rec_id, rec_type, rec_parent) {
    if (rec_type == "post") return(0L)
    if (is.na(rec_parent))  return(NA_integer_)

    depth   <- 1L
    current <- rec_parent
    visited <- character(0)

    repeat {
      if (is.na(current) || !current %in% names(id_to_type)) break
      # Cycle detection
      if (current %in% visited) return(NA_integer_)
      visited <- c(visited, current)

      if (id_to_type[[current]] == "post") break
      depth   <- depth + 1L
      current <- id_to_parent[[current]]

      if (depth > 10L) {
        depth <- NA_integer_
        break
      }
    }
    depth
  }

  df$thread_depth <- mapply(
    compute_depth,
    df$id, df$type, df$parent_id,
    USE.NAMES = FALSE
  )
  df$thread_depth <- as.integer(df$thread_depth)

  # ── 5. Log resolution stats ───────────────────────────────────────────────
  n_resolved   <- sum(!is.na(df$parent_text[df$type == "comment"]))
  n_unresolved <- sum( is.na(df$parent_text[df$type == "comment"]))
  n_comments   <- sum(df$type == "comment")

  log_msg(paste0(
    "Thread reconstruction: ", n_comments, " comments — ",
    n_resolved, " with resolved parent (", round(100 * n_resolved / max(n_comments, 1), 1), "%), ",
    n_unresolved, " unresolved (parent filtered/absent — expected)"
  ))

  df
}

# ---------------------------------------------------------------------------
# build_full_context(df)
# Creates the full_context field used by the LLM relevance classifier.
# ---------------------------------------------------------------------------
build_full_context <- function(df) {

  df <- df |>
    mutate(
      full_context = dplyr::case_when(

        # Root post
        thread_depth == 0 ~ paste0(
          "[POST in r/", subreddit, "]\n",
          "Title: ", dplyr::if_else(!is.na(title), title, "(no title)"), "\n\n",
          dplyr::if_else(!is.na(text), text, "")
        ),

        # Direct reply to a post
        thread_depth == 1 ~ paste0(
          "[COMMENT in r/", subreddit, " replying to post]\n",
          "Parent post title: ", dplyr::if_else(!is.na(root_post_title), root_post_title, "(no title)"), "\n",
          "Parent post body: ", .truncate(root_post_text, 500), "\n\n",
          "[COMMENT TEXT]\n",
          dplyr::if_else(!is.na(text), text, "")
        ),

        # Nested comment (depth >= 2)
        thread_depth >= 2 ~ paste0(
          "[NESTED COMMENT in r/", subreddit, "]\n",
          "Root post title: ", dplyr::if_else(!is.na(root_post_title), root_post_title, "(no title)"), "\n",
          "Direct parent: ", .truncate(parent_text, 300), "\n\n",
          "[COMMENT TEXT]\n",
          dplyr::if_else(!is.na(text), text, "")
        ),

        # Unresolved parent (thread_depth == NA)
        TRUE ~ paste0(
          "[COMMENT in r/", subreddit, " \u2014 parent context unavailable]\n",
          dplyr::if_else(!is.na(text), text, "")
        )
      )
    )

  log_msg(paste(
    "full_context built for", nrow(df), "records;",
    sum(df$thread_depth == 0, na.rm = TRUE), "posts,",
    sum(df$thread_depth == 1, na.rm = TRUE), "direct replies,",
    sum(df$thread_depth >= 2, na.rm = TRUE), "nested comments,",
    sum(is.na(df$thread_depth)), "unresolved"
  ))

  df
}
