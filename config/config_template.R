# config/config_template.R — Copy to config/config.R and fill in your values
# config/config.R is in .gitignore — never commit it

CFG <- list(
  # API keys (loaded from .Renviron recommended)
  anthropic_api_key = Sys.getenv("ANTHROPIC_API_KEY"),
  gptzero_api_key   = Sys.getenv("GPTZERO_API_KEY"),

  # LLM settings
  llm_model         = "claude-sonnet-4-5",
  llm_max_tokens    = 1024,
  llm_temperature   = 0,       # Deterministic for classification tasks

  # GPTZero settings
  gptzero_monthly_word_limit = 300000,
  gptzero_batch_size         = 50,   # records per API call
  gptzero_ai_threshold       = 0.75, # Lower to 0.5 for mixed-AI; raise to 0.9 for strict

  # Filtering thresholds
  min_text_chars    = 50,      # Minimum characters for a record to be kept
  start_date        = as.Date("2020-01-01"),

  # Paths (use here::here() for portability)
  path_raw          = here::here("data", "raw"),
  path_processed    = here::here("data", "processed"),
  path_checkpoints  = here::here("data", "checkpoints"),

  # ABSA seed aspects (see BRIEF.md for descriptions)
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
