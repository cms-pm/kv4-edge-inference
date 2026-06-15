-- Matrix-dimension normalization for the kv4 measurement volley.
-- Devil's-advocate remediation (2026-06-14): the kv4 study varies KV-cache
-- quant, context length, offload, batch, and speculative decoding. Previously
-- those facts had no home and would be encoded into the free-text
-- runs.condition (a 1NF-spirit violation) or conflated into models.flavour
-- (KV-quant is a serving param, not a weights property). This migration gives
-- them first-class, queryable homes.
--
-- v1/v2 seam: runs.serving_params_id is nullable. Landed SCN-1.x/3.x runs
-- keep NULL; the kv4 volley onward populates it. No back-fill of published
-- evidence. Provenance columns (driver/CUDA/kernel/commit/GGUF-SHA) and
-- gpu_telemetry.gpu_uuid are intentionally deferred (single-GPU host).

-- Reference table for per-GPU-model spec. gpu_model is the key, so
-- vram/bandwidth/etc. depend on the key directly (removes the
-- gpu_model -> vram_mib transitive dependency that lived in `hardware`).
-- Joined to hardware.gpu_model in analytics; this is the normalized home for
-- the GTX 1650 GDDR6 / 192 GB/s finding.
CREATE TABLE IF NOT EXISTS gpu_models (
  gpu_model TEXT PRIMARY KEY,
  vram_mib INTEGER,
  memory_bandwidth_gbps REAL,
  memory_type TEXT,            -- e.g. 'GDDR5', 'GDDR6'
  compute_capability TEXT,     -- e.g. '7.5'
  notes TEXT
);

-- Serving configuration dimension, mirroring the sampling_params pattern:
-- deduplicated by its natural-key tuple, referenced by runs.
CREATE TABLE IF NOT EXISTS serving_params (
  id INTEGER PRIMARY KEY,
  kv_cache_quant TEXT,         -- 'fp16' | 'q8_0' | 'turbo4' (kv4)
  context_length INTEGER,      -- n_ctx
  n_gpu_layers INTEGER,        -- -ngl (offload; the single-GPU analog of tensor split)
  batch_size INTEGER,          -- -np / continuous-batching width
  speculative TEXT,            -- 'off' | 'ngram' | draft-model id
  UNIQUE(kv_cache_quant, context_length, n_gpu_layers, batch_size, speculative)
);

-- 1:1 optional link from a run to its serving config. A link table (rather
-- than ALTER TABLE runs ADD COLUMN) keeps this migration idempotent: db.migrate
-- re-runs every script, and SQLite has no ADD COLUMN IF NOT EXISTS. The v1/v2
-- seam is the absence of a row: landed SCN runs have none; kv4 runs add one.
CREATE TABLE IF NOT EXISTS run_serving (
  run_id INTEGER PRIMARY KEY REFERENCES runs(id),
  serving_params_id INTEGER NOT NULL REFERENCES serving_params(id)
);
