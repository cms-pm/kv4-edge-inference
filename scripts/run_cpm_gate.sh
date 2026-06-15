#!/usr/bin/env bash
# turbo4 pre-screen GATE for a candidate model: does it load + decode coherently
# under 4-bit KV? Usage: run_cpm_gate.sh [model.gguf]  (default: $MODEL_MINICPM)
# Ref: ansible/playbooks/cpm-gate.yml
set -uo pipefail
source "$(dirname "$0")/lib/common.sh"
preflight
G="$WORK_DIR/cpm-gate"; mkdir -p "$G"/{bench,coh}
M="$MODEL_DIR/${1:-$MODEL_MINICPM}"
[ -f "$M" ] || { log "model not found: $M"; exit 1; }

# functional: does turbo4 even bench? (a turbo4 load failure = gate FAIL)
for kv in f16 turbo4; do
  log "gate bench $kv"
  "$LB" -m "$M" -ngl 99 -fa 1 -ctk "$kv" -ctv "$kv" -p 512 -n 128 -r "$REPS" -o jsonl \
    > "$G/bench/cpm_$kv.jsonl" 2> "$G/bench/cpm_$kv.err" || log "  (turbo4 may be unsupported -> gate FAIL)"
done

# coherence: a short greedy generation under each KV type
for kv in f16 turbo4; do
  log "gate coherence $kv"
  fuser -k "$PORT/tcp" 2>/dev/null || true; sleep 2
  nohup "$LS" -m "$M" -ngl 99 -fa 1 --cache-type-k "$kv" --cache-type-v "$kv" \
    -c 4096 --host 127.0.0.1 --port "$PORT" > "$G/coh/cpm_$kv.server.log" 2>&1 & srv=$!
  for _ in $(seq 1 60); do
    kill -0 $srv 2>/dev/null || break
    [ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/health" 2>/dev/null)" = 200 ] && break
    sleep 2
  done
  curl -s "http://127.0.0.1:$PORT/completion" \
    -d '{"prompt":"What is the capital of France?","n_predict":32,"temperature":0}' \
    > "$G/coh/cpm_$kv.gen.json" 2>/dev/null || true
  kill -9 $srv 2>/dev/null || true; fuser -k "$PORT/tcp" 2>/dev/null || true; sleep 2
done
log "gate done -> $G (inspect coh/*.gen.json: turbo4 must stay coherent to pass)"
