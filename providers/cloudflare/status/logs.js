/**
 * logs.js — D1 query helpers for the logs table.
 *
 * All callers should pass `env.LOGS_DB` (the D1 binding). Helpers compute
 * `expires_at` from `ts + retention_days * 86400000` so a malicious caller
 * cannot set a far-future expiry to keep records past purge.
 */

const MS_PER_DAY = 86_400_000;
const DEFAULT_RETENTION_DAYS = 7;
const MAX_RETENTION_DAYS = 365;
const VALID_LEVELS = new Set(['debug', 'info', 'notice', 'warning', 'error', 'critical', 'alert', 'emergency']);
const MAX_MESSAGE_BYTES = 16 * 1024;
const MAX_CONTEXT_BYTES = 32 * 1024;

/**
 * Coerce a single log record into the column tuple expected by the INSERT
 * statement. Throws on missing required fields. Truncates oversize text so a
 * runaway logger can't blow D1's row-size cap.
 */
function normaliseRecord(input) {
  if (!input || typeof input !== 'object') {
    throw new Error('record must be an object');
  }

  const level = String(input.level || '').toLowerCase();
  if (!VALID_LEVELS.has(level)) {
    throw new Error(`level must be one of: ${[...VALID_LEVELS].join(', ')}`);
  }

  const source = String(input.source || '').trim();
  if (!source) throw new Error('source is required');

  let message = String(input.message || '');
  if (!message) throw new Error('message is required');
  if (message.length > MAX_MESSAGE_BYTES) message = message.slice(0, MAX_MESSAGE_BYTES);

  let context = input.context;
  let context_json = null;
  if (context !== undefined && context !== null) {
    try {
      context_json = typeof context === 'string' ? context : JSON.stringify(context);
    } catch {
      context_json = null;
    }
    if (context_json && context_json.length > MAX_CONTEXT_BYTES) {
      context_json = context_json.slice(0, MAX_CONTEXT_BYTES);
    }
  }

  const tsRaw = Number(input.ts);
  const ts = Number.isFinite(tsRaw) && tsRaw > 0 ? Math.floor(tsRaw) : Date.now();

  const retentionRaw = Number(input.retention_days);
  let retention_days = Number.isFinite(retentionRaw) && retentionRaw > 0 ? Math.floor(retentionRaw) : DEFAULT_RETENTION_DAYS;
  if (retention_days > MAX_RETENTION_DAYS) retention_days = MAX_RETENTION_DAYS;

  const expires_at = ts + retention_days * MS_PER_DAY;

  const tenant_id = input.tenant_id ? String(input.tenant_id).slice(0, 128) : null;
  const trace_id = input.trace_id ? String(input.trace_id).slice(0, 128) : null;

  return { ts, level, source, message, context_json, tenant_id, trace_id, retention_days, expires_at };
}

export async function insertLog(db, input) {
  const r = normaliseRecord(input);
  const result = await db
    .prepare(
      `INSERT INTO logs (ts, level, source, message, context_json, tenant_id, trace_id, retention_days, expires_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .bind(r.ts, r.level, r.source, r.message, r.context_json, r.tenant_id, r.trace_id, r.retention_days, r.expires_at)
    .run();
  return { id: result.meta?.last_row_id ?? null, expires_at: r.expires_at };
}

export async function insertLogBatch(db, records) {
  if (!Array.isArray(records) || records.length === 0) {
    throw new Error('records must be a non-empty array');
  }
  if (records.length > 100) {
    throw new Error('batch size limited to 100 records');
  }

  const normalised = records.map(normaliseRecord);

  const stmt = db.prepare(
    `INSERT INTO logs (ts, level, source, message, context_json, tenant_id, trace_id, retention_days, expires_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  );

  const bound = normalised.map((r) =>
    stmt.bind(r.ts, r.level, r.source, r.message, r.context_json, r.tenant_id, r.trace_id, r.retention_days, r.expires_at),
  );

  const results = await db.batch(bound);
  const inserted = results.reduce((sum, x) => sum + (x.meta?.changes ?? 0), 0);
  return { inserted };
}

/**
 * Query logs with simple filters. Returns the most recent rows first.
 *
 * Filter values are validated; unknown filters are ignored so a caller
 * mistyping `?lvl=` cannot break the SQL.
 */
export async function queryLogs(db, filters = {}) {
  const where = [];
  const binds = [];

  if (filters.level) {
    const lv = String(filters.level).toLowerCase();
    if (VALID_LEVELS.has(lv)) {
      where.push('level = ?');
      binds.push(lv);
    }
  }

  if (filters.source) {
    where.push('source = ?');
    binds.push(String(filters.source).slice(0, 64));
  }

  if (filters.tenant_id) {
    where.push('tenant_id = ?');
    binds.push(String(filters.tenant_id).slice(0, 128));
  }

  if (filters.trace_id) {
    where.push('trace_id = ?');
    binds.push(String(filters.trace_id).slice(0, 128));
  }

  if (filters.since) {
    const since = Number(filters.since);
    if (Number.isFinite(since)) {
      where.push('ts >= ?');
      binds.push(Math.floor(since));
    }
  }

  if (filters.until) {
    const until = Number(filters.until);
    if (Number.isFinite(until)) {
      where.push('ts <= ?');
      binds.push(Math.floor(until));
    }
  }

  if (filters.q) {
    where.push('message LIKE ?');
    binds.push('%' + String(filters.q).slice(0, 200) + '%');
  }

  let limit = Number(filters.limit);
  if (!Number.isFinite(limit) || limit <= 0) limit = 100;
  if (limit > 500) limit = 500;

  const sql = `SELECT id, ts, level, source, message, context_json, tenant_id, trace_id, retention_days, expires_at
               FROM logs
               ${where.length ? 'WHERE ' + where.join(' AND ') : ''}
               ORDER BY ts DESC
               LIMIT ?`;
  binds.push(limit);

  const { results } = await db.prepare(sql).bind(...binds).all();

  return results.map((row) => ({
    ...row,
    context: row.context_json ? safeParse(row.context_json) : null,
  }));
}

/**
 * Delete rows whose expires_at has passed. Called from the cron handler.
 * Returns the number of rows removed (best-effort; D1 batch metadata).
 */
export async function purgeExpired(db, now = Date.now()) {
  const result = await db.prepare('DELETE FROM logs WHERE expires_at < ?').bind(now).run();
  return result.meta?.changes ?? 0;
}

/**
 * Fetch a single log row by id, including parsed context. Returns null when
 * the row doesn't exist.
 */
export async function getLogById(db, id) {
  const numericId = Number(id);
  if (!Number.isFinite(numericId) || numericId <= 0) {
    throw new Error('id must be a positive integer');
  }
  const row = await db.prepare(
    `SELECT id, ts, level, source, message, context_json, tenant_id, trace_id, retention_days, expires_at
     FROM logs WHERE id = ?`,
  ).bind(Math.floor(numericId)).first();

  if (!row) return null;
  return {
    ...row,
    context: row.context_json ? safeParse(row.context_json) : null,
  };
}

/**
 * Delete a single log row by id. Returns true when a row was removed.
 */
export async function deleteLogById(db, id) {
  const numericId = Number(id);
  if (!Number.isFinite(numericId) || numericId <= 0) {
    throw new Error('id must be a positive integer');
  }
  const result = await db.prepare('DELETE FROM logs WHERE id = ?').bind(Math.floor(numericId)).run();
  return (result.meta?.changes ?? 0) > 0;
}

/**
 * Delete rows older than the given timestamp. Used by the admin DELETE
 * endpoint for one-off cleanups.
 */
export async function purgeBefore(db, beforeTs) {
  const ts = Number(beforeTs);
  if (!Number.isFinite(ts) || ts <= 0) {
    throw new Error('before must be a positive unix millisecond timestamp');
  }
  const result = await db.prepare('DELETE FROM logs WHERE ts < ?').bind(Math.floor(ts)).run();
  return result.meta?.changes ?? 0;
}

function safeParse(value) {
  try {
    return JSON.parse(value);
  } catch {
    return value;
  }
}
