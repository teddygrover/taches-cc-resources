# Phase 01 Plan 02: Data Loading & Initial Filtering Summary

**`R/load_data.R` and `R/filter_initial.R` written with exact schema mappings; `scripts/01_initial_filter.R` ready to execute once data is present.**

## Accomplishments
- `load_reddit_data()` reads all CSV/XLSX from `data/raw/`, validates exact required columns, normalises to canonical schema
- Schema validation uses exact column names (no flexible guessing): fails loudly with clear error if any required column is missing
- `apply_initial_filters()` implements post-based date cascade, ID deduplication, content-hash deduplication within subreddit, and min-text-length filter — each step logged with before/after counts
- `scripts/01_initial_filter.R` is the executable pipeline entry point

## Files Created/Modified
- `R/load_data.R` — CSV/XLSX ingestion with schema validation and normalisation
- `R/filter_initial.R` — date, dedup, text-length filters with full logging
- `scripts/01_initial_filter.R` — executable pipeline script

## Decisions Made

**Column mappings used (from whats-next.md schema table):**
| Canonical name | Source column | Notes |
|---|---|---|
| `id` | `parsedId` | Preferred over raw `id` |
| `text` | `body` | Both posts and comments |
| `title` | `title` | Posts only; NA for comments — not filled |
| `subreddit` | `parsedCommunityName` | Cleaner variant |
| `created_at` | `createdAt` | Posts only; NA for all comments |
| `type` | `dataType` | Exactly `"post"` or `"comment"` |
| `parent_id` | `parsedParentId` | Bare IDs — no prefix stripping |
| `post_id` | `parsedPostId` | Direct root post link |
| `score` | `coalesce(upVotes, commentUpVotes)` | Posts use upVotes, comments use commentUpVotes |
| `author` | `authorName` | |

**Date filter design:** `created_at` is NA for all comments so filter is post-first: identify `valid_post_ids` (posts >= 2020-01-01), then keep posts in that set and comments whose `post_id` is in that set.

**Content dedup:** MD5 hash of `tolower(trimws(text))` within subreddit — avoids false-positive dedup across subreddits for common short phrases.

## Issues Encountered
- None. Schema was fully known from `whats-next.md` — no flexible matching needed.

## Next Step
Code complete. Awaiting user to run `scripts/00_setup.R` then `scripts/01_initial_filter.R`.
Ready for 01-03-PLAN.md execution — `R/thread_reconstruct.R` is already written.
