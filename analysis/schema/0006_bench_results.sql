-- llama-bench results fact table for the kv4 throughput matrix.
-- Each row is one llama-bench test line (one pp or tg measurement for a given
-- config), parsed from the per-cell JSONL the matrix runner emits. This is a
-- measurement/fact table (like scores_cache is a derived cache): the bench
-- config columns are denormalized onto each row by design, since llama-bench
-- reports its own model/config metadata inline and these results do not map to
-- the runs.yaml/serving_params path (that path serves the server-load + per-
-- prompt eval cells).
CREATE TABLE IF NOT EXISTS bench_results (
  id INTEGER PRIMARY KEY,
  chunk_id INTEGER REFERENCES chunks(id),
  condition TEXT NOT NULL,        -- cell name (JSONL filename stem)
  test TEXT NOT NULL,             -- 'pp' (prefill) | 'tg' (decode), derived
  build_commit TEXT,
  model_filename TEXT,
  model_type TEXT,
  model_size INTEGER,
  model_n_params INTEGER,
  type_k TEXT,                    -- KV-cache K quant (f16 | turbo2/3/4 | ...)
  type_v TEXT,                    -- KV-cache V quant
  n_gpu_layers INTEGER,
  flash_attn INTEGER,
  n_batch INTEGER,
  n_ubatch INTEGER,
  n_prompt INTEGER,
  n_gen INTEGER,
  n_depth INTEGER,                -- KV depth before measurement (context axis)
  avg_ts REAL,                    -- tokens/s mean
  stddev_ts REAL,                 -- tokens/s stddev (from llama-bench reps)
  avg_ns REAL,
  test_time TEXT,
  UNIQUE(chunk_id, condition, test, n_prompt, n_gen, n_depth, type_k, type_v)
);

CREATE INDEX IF NOT EXISTS idx_bench_results_condition ON bench_results(chunk_id, condition);
