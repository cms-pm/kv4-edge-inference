-- L2 GPU sidecar telemetry: nvidia-smi polled at ~1 Hz during an eval run,
-- joined post-hoc to the run by (run_id, ts). One row per sidecar sample.
-- See docs/planning/experiment-design-rigor.md § "Telemetry layers" (L2).
CREATE TABLE IF NOT EXISTS gpu_telemetry (
  run_id INTEGER NOT NULL REFERENCES runs(id),
  ts TEXT NOT NULL,            -- nvidia-smi timestamp (ISO-ish), sidecar clock
  gpu_util_pct REAL,           -- utilization.gpu (coarse: % time >=1 kernel active)
  mem_util_pct REAL,           -- utilization.memory
  mem_mib INTEGER,             -- memory.used
  power_w REAL,                -- power.draw
  temp_c REAL,                 -- temperature.gpu
  sm_mhz INTEGER,              -- clocks.current.sm
  mem_mhz INTEGER,             -- clocks.current.memory
  pstate TEXT,                 -- performance state (P0..P12)
  PRIMARY KEY(run_id, ts)
);

CREATE INDEX IF NOT EXISTS idx_gpu_telemetry_run_id ON gpu_telemetry(run_id);
