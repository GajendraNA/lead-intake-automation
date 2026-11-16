CREATE TABLE IF NOT EXISTS leads (
  id           BIGSERIAL PRIMARY KEY,
  email        TEXT NOT NULL UNIQUE,
  name         TEXT,
  company      TEXT,
  message      TEXT,
  source       TEXT,
  industry     TEXT,
  company_size TEXT,
  enriched     BOOLEAN DEFAULT false,
  fit_score    INT,
  urgency      TEXT,
  budget_text  TEXT,
  summary      TEXT,
  tier         TEXT,
  created_at   TIMESTAMPTZ DEFAULT now(),
  updated_at   TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS error_log (
  id            BIGSERIAL PRIMARY KEY,
  workflow_name TEXT,
  failing_node  TEXT,
  message       TEXT,
  execution_url TEXT,
  created_at    TIMESTAMPTZ DEFAULT now()
);
