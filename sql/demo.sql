-- Rate-limit bookkeeping for the public demo webhook (workflows/WF4-demo-lead.json).
-- Stores only a one-way hash of the visitor's IP and a timestamp. No lead data is saved.
CREATE TABLE IF NOT EXISTS demo_runs (
  id         BIGSERIAL PRIMARY KEY,
  ip_hash    TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS demo_runs_created_at_idx ON demo_runs (created_at);
