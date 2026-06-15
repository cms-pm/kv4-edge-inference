-- Per-run provenance (devil's-advocate findings #3 + #4).
--
-- fork_build_hash was conflated into `hardware` — a GPU does not determine the
-- llama.cpp build, so rebuilding the fork spawned a phantom hardware identity.
-- It belongs with the run's *software* provenance, alongside the driver / CUDA
-- / kernel versions, the eval-harness commit, and the served GGUF's SHA256 —
-- all of which experiment-design-rigor.md mandates be "bound to the run row,
-- not reconstructed by archaeology". This table is that home.
--
-- 1:1 with runs (run_id PK), so every column depends on the key directly (3NF;
-- per-run capture is intentional, so the environment is deliberately not
-- deduplicated). Idempotent (new table, no ALTER). v1/v2 seam: landed SCN runs
-- have no row here. `hardware.fork_build_hash` is now DEPRECATED — retained only
-- so existing v1 ingest/dedup keeps working; new runs record the build hash here.
CREATE TABLE IF NOT EXISTS run_provenance (
  run_id INTEGER PRIMARY KEY REFERENCES runs(id),
  fork_build_hash TEXT,        -- llama.cpp / turbo4 fork build (authoritative home)
  driver_version TEXT,         -- NVIDIA driver
  cuda_version TEXT,
  kernel_version TEXT,         -- uname -r
  eval_commit TEXT,            -- eval-grading harness commit hash
  gguf_sha256 TEXT             -- sha256 of the GGUF actually served
);
