CREATE TABLE IF NOT EXISTS chunks (
  id INTEGER PRIMARY KEY,
  name TEXT UNIQUE NOT NULL,
  started_at TEXT,
  notes TEXT
);

CREATE TABLE IF NOT EXISTS hardware (
  id INTEGER PRIMARY KEY,
  gpu_model TEXT,
  vram_mib INTEGER,
  host TEXT,
  fork_build_hash TEXT,
  notes TEXT,
  UNIQUE(gpu_model, host, fork_build_hash)
);

CREATE TABLE IF NOT EXISTS models (
  id INTEGER PRIMARY KEY,
  model_id TEXT NOT NULL,
  quant TEXT,
  flavour TEXT,
  gguf_basename TEXT,
  notes TEXT,
  UNIQUE(model_id, quant, flavour)
);

CREATE TABLE IF NOT EXISTS sampling_params (
  id INTEGER PRIMARY KEY,
  temperature REAL,
  top_p REAL,
  n_samples INTEGER,
  base_seed INTEGER,
  method TEXT,
  UNIQUE(temperature, top_p, n_samples, base_seed, method)
);

CREATE TABLE IF NOT EXISTS rubrics (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  version TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  axes_json TEXT NOT NULL,
  pass_threshold INTEGER,
  source_path TEXT,
  UNIQUE(name, version)
);

CREATE TABLE IF NOT EXISTS prompts (
  id INTEGER PRIMARY KEY,
  chunk_id INTEGER NOT NULL REFERENCES chunks(id),
  prompt_id TEXT NOT NULL,
  layer TEXT,
  sub_skill TEXT,
  scenario TEXT,
  difficulty TEXT,
  schema_name TEXT,
  grading_kind TEXT,
  rubric_id INTEGER REFERENCES rubrics(id),
  task_text TEXT,
  expected_json TEXT,
  UNIQUE(chunk_id, prompt_id)
);

CREATE TABLE IF NOT EXISTS runs (
  id INTEGER PRIMARY KEY,
  chunk_id INTEGER NOT NULL REFERENCES chunks(id),
  condition TEXT NOT NULL,
  model_id INTEGER NOT NULL REFERENCES models(id),
  sampling_params_id INTEGER NOT NULL REFERENCES sampling_params(id),
  hardware_id INTEGER NOT NULL REFERENCES hardware(id),
  started_at TEXT,
  ended_at TEXT,
  UNIQUE(chunk_id, condition, hardware_id)
);

CREATE TABLE IF NOT EXISTS transcripts (
  id INTEGER PRIMARY KEY,
  run_id INTEGER NOT NULL REFERENCES runs(id),
  prompt_id INTEGER NOT NULL REFERENCES prompts(id),
  captured_at TEXT,
  source_path TEXT,
  wall_ms_total REAL,
  status_ok INTEGER,
  aggregated_winner_json TEXT,
  raw_extracted_json TEXT,
  UNIQUE(run_id, prompt_id)
);

CREATE TABLE IF NOT EXISTS samples (
  id INTEGER PRIMARY KEY,
  transcript_id INTEGER NOT NULL REFERENCES transcripts(id),
  sample_index INTEGER NOT NULL,
  wall_ms REAL,
  status INTEGER,
  raw_text TEXT,
  extracted_json TEXT,
  UNIQUE(transcript_id, sample_index)
);

CREATE TABLE IF NOT EXISTS graders (
  id INTEGER PRIMARY KEY,
  kind TEXT NOT NULL,
  identity TEXT NOT NULL,
  model_version TEXT,
  notes TEXT,
  UNIQUE(kind, identity, model_version)
);

CREATE TABLE IF NOT EXISTS grades (
  id INTEGER PRIMARY KEY,
  transcript_id INTEGER NOT NULL REFERENCES transcripts(id),
  axis_name TEXT NOT NULL,
  score INTEGER NOT NULL,
  comment TEXT,
  grader_id INTEGER NOT NULL REFERENCES graders(id),
  graded_at TEXT NOT NULL,
  UNIQUE(transcript_id, axis_name, grader_id)
);

CREATE TABLE IF NOT EXISTS scores_cache (
  run_id INTEGER,
  prompt_id INTEGER,
  parse_ok INTEGER,
  schema_ok INTEGER,
  intent_ok INTEGER,
  rubric_total INTEGER,
  rubric_pass INTEGER,
  wall_p50_ms REAL,
  computed_at TEXT,
  PRIMARY KEY(run_id, prompt_id)
);

CREATE INDEX IF NOT EXISTS idx_runs_condition ON runs(condition);
CREATE INDEX IF NOT EXISTS idx_prompts_chunk_id_difficulty ON prompts(chunk_id, difficulty);
CREATE INDEX IF NOT EXISTS idx_grades_transcript_id ON grades(transcript_id);
CREATE INDEX IF NOT EXISTS idx_grades_grader_id ON grades(grader_id);
CREATE INDEX IF NOT EXISTS idx_transcripts_run_id ON transcripts(run_id);
CREATE INDEX IF NOT EXISTS idx_samples_transcript_id ON samples(transcript_id);
