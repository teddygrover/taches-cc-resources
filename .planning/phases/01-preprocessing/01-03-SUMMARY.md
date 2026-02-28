# Phase 01 Plan 03: Thread Reconstruction Summary

**`R/thread_reconstruct.R` written with direct `post_id` thread assignment, iterative depth computation, cycle detection, and full `full_context` string builder; `scripts/02_thread_reconstruct.R` ready to execute.**

## Accomplishments
- `reconstruct_threads()` assigns `thread_id`, resolves `parent_text` and `root_post_text`, and computes `thread_depth` for all records
- `build_full_context()` creates the `full_context` string used by the LLM relevance classifier — format varies by post/direct-reply/nested/unresolved
- Cycle detection prevents infinite loops on malformed data
- Depth capped at 10 levels as a safety guard
- `scripts/02_thread_reconstruct.R` is the executable pipeline entry point

## Files Created/Modified
- `R/thread_reconstruct.R` — parent linking, thread ID, full_context builder
- `scripts/02_thread_reconstruct.R` — executable pipeline script

## Decisions Made

**Thread ID assignment:** `post_id` (from `parsedPostId`) is used directly for all comments — no chain-walking required. This is correct for this dataset (confirmed in whats-next.md).

**Prefix stripping:** NOT applied. `parent_id` values are already bare IDs (confirmed in whats-next.md). Using `parsedParentId` directly.

**Parent text for posts:** Root posts use their own `title + "\n\n" + text` as `root_post_text`; `parent_text` is NA (they have no parent).

**`full_context` truncation limits:**
- Root post body in direct-reply context: 500 chars
- Direct parent text in nested-comment context: 300 chars

**Unresolved parents:** Comments whose parent post was filtered out in 01-02 (pre-2020 or absent from dataset) get `parent_text = NA`, `root_post_text = NA`, `thread_depth = NA`. Their `full_context` includes a "(parent context unavailable)" note. They are still passed to the LLM classifier with their own text only.

## Issues Encountered
- None. All schema decisions were pre-resolved in `whats-next.md`.

## Next Step
Code complete. Awaiting user to run the pipeline sequence:
1. `Rscript scripts/00_setup.R` (once, sets up renv)
2. Copy CSVs to `data/raw/`
3. `Rscript scripts/01_initial_filter.R`
4. `Rscript scripts/02_thread_reconstruct.R`

Ready for 01-04-PLAN.md — LLM relevance classification (has a human-review dry-run gate).
