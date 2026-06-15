# analysis

- `analyze.py` — standalone (stdlib) reproduction of the paper's decode/prefill
  tok/s and VRAM-peak numbers from `../data/`. No GPU or extra deps.
- `schema/*.sql` — the DuckDB data model the project used to ingest evidence
  (gpu_telemetry, matrix dimensions, run provenance, bench_results). Reference
  only; `analyze.py` reads the raw JSONL/CSV directly so you don't need a DB.
