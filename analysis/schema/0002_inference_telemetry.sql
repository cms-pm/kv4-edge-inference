CREATE TABLE IF NOT EXISTS inference_telemetry (
  transcript_id INTEGER PRIMARY KEY REFERENCES transcripts(id),
  prefill_ms REAL,
  prefill_tokens INTEGER,
  decode_ms REAL,
  decode_tokens INTEGER,
  load_ms REAL,
  source TEXT
);
