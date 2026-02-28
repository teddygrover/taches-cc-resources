# config/config_template.R
# ---------------------------------------------------------------------------
# TEMPLATE — safe to commit.
# Copy this file to config/config.R, fill in your values, then source it.
# config/config.R is listed in .gitignore — NEVER commit it.
# ---------------------------------------------------------------------------

library(here)

CFG <- list(

  # ── API keys ──────────────────────────────────────────────────────────────
  # Recommended: set these in your ~/.Renviron file rather than hardcoding.
  anthropic_api_key = Sys.getenv("ANTHROPIC_API_KEY"),
  gptzero_api_key   = Sys.getenv("GPTZERO_API_KEY"),

  # ── LLM settings ─────────────────────────────────────────────────────────
  llm_model       = "claude-sonnet-4-5",
  llm_max_tokens  = 1024,
  llm_temperature = 0,       # Deterministic output for classification tasks

  # ── GPTZero settings ─────────────────────────────────────────────────────
  gptzero_monthly_word_limit = 300000,  # Hard cap — track usage carefully
  gptzero_batch_size         = 50,      # Records per API call
  gptzero_ai_threshold       = 0.75,    # P(AI-generated) >= this → filtered out

  # ── Filtering thresholds ─────────────────────────────────────────────────
  min_text_chars = 50,                  # Records below this char count are dropped
  start_date     = as.Date("2020-01-01"),

  # ── Paths ─────────────────────────────────────────────────────────────────
  path_raw         = here::here("data", "raw"),
  path_processed   = here::here("data", "processed"),
  path_checkpoints = here::here("data", "checkpoints"),

  # ── ABSA seed aspects ────────────────────────────────────────────────────
  # See .planning/BRIEF.md for full descriptions.
  seed_aspects = c(
    "Accuracy & Reliability",
    "Privacy & Data Security",
    "Ethics & Bias",
    "Regulation & Policy",
    "Job Impact & Workflow",
    "Patient Outcomes & Safety",
    "Trust & Adoption",
    "Cost & Accessibility"
  )
)
