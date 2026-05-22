-- D1 schema for paymentform status-worker logs.
--
-- One row per shipped log record. `expires_at` is computed server-side at
-- insert from `ts + retention_days * 86400000`, then the 5-minute cron run
-- deletes any rows with `expires_at < now`.
--
-- Applied by `wrangler d1 execute --file schema.sql` during terraform apply.

CREATE TABLE IF NOT EXISTS logs (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  ts              INTEGER NOT NULL,                       -- unix milliseconds, when the record was emitted
  level           TEXT    NOT NULL,                       -- debug | info | notice | warning | error | critical | alert | emergency
  source          TEXT    NOT NULL,                       -- backend | renderer | queue | nginx | ...
  message         TEXT    NOT NULL,
  context_json    TEXT,                                   -- JSON: { request_id, user_uuid, file, line, exception, stack, ... }
  tenant_id       TEXT,                                   -- nullable
  trace_id        TEXT,                                   -- correlation id from request
  retention_days  INTEGER NOT NULL DEFAULT 7,
  expires_at      INTEGER NOT NULL                        -- unix milliseconds
);

CREATE INDEX IF NOT EXISTS idx_logs_expires    ON logs(expires_at);
CREATE INDEX IF NOT EXISTS idx_logs_ts         ON logs(ts);
CREATE INDEX IF NOT EXISTS idx_logs_level_ts   ON logs(level, ts);
CREATE INDEX IF NOT EXISTS idx_logs_tenant_ts  ON logs(tenant_id, ts);
CREATE INDEX IF NOT EXISTS idx_logs_source_ts  ON logs(source, ts);
