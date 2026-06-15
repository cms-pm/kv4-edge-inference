#!/usr/bin/env bash
# Decode-throughput matrix (tg vs depth x KV quant) + VRAM-vs-context curve.
# Reproduces the paper's Fig. 1 data. Exact-as-run reference: ansible/playbooks/matrix.yml
set -uo pipefail
source "$(dirname "$0")/lib/common.sh"
preflight

# --- decode throughput: llama-bench, 1 Hz sidecar per cell (cond kv depth) ---
for c in \
  "qwen3-1.7b__kvf16__ngl99__d0 f16 0" \
  "qwen3-1.7b__kvturbo4__ngl99__d0 turbo4 0" \
  "qwen3-1.7b__kvf16__ngl99__d8192 f16 8192" \
  "qwen3-1.7b__kvturbo4__ngl99__d8192 turbo4 8192" \
  "qwen3-1.7b__kvf16__ngl99__d32768 f16 32768" \
  "qwen3-1.7b__kvturbo4__ngl99__d32768 turbo4 32768" \
  "qwen3-1.7b__kvturbo3__ngl99__d32768 turbo3 32768" \
  "qwen3-1.7b__kvturbo2__ngl99__d32768 turbo2 32768" ; do
  read -r cond kv depth <<<"$c"
  log "bench $cond"
  sp=$(sidecar_start "$WORK_DIR/gpu-telemetry/$cond.csv"); sleep 1
  da=(); [ "$depth" -gt 0 ] && da=(-d "$depth")
  "$LB" -m "$MODEL_DIR/$MODEL_QWEN3" -ngl 99 -fa 1 -ctk "$kv" -ctv "$kv" \
        -p 512 -n 128 "${da[@]}" -r "$REPS" -o jsonl \
        > "$WORK_DIR/bench/$cond.jsonl" 2> "$WORK_DIR/bench/$cond.err" \
        || log "  ($cond OOM/err — recorded as a data point)"
  sidecar_stop "$sp"; sleep 1
done

# --- VRAM-vs-context: server load, peak memory.used (cond kv ctx) ---
for c in \
  "vram__qwen3-1.7b__kvf16__c8192 f16 8192" \
  "vram__qwen3-1.7b__kvturbo4__c8192 turbo4 8192" \
  "vram__qwen3-1.7b__kvf16__c32768 f16 32768" \
  "vram__qwen3-1.7b__kvturbo4__c32768 turbo4 32768" \
  "vram__qwen3-1.7b__kvturbo4__c65536 turbo4 65536" ; do
  read -r cond kv ctx <<<"$c"
  log "vram $cond"
  fuser -k "$PORT/tcp" 2>/dev/null || true; sleep 2
  nvidia-smi --query-gpu=timestamp,memory.used --format=csv,noheader,nounits -lms 1000 \
    > "$WORK_DIR/vram/$cond.csv" 2>/dev/null & sp=$!
  nohup "$LS" -m "$MODEL_DIR/$MODEL_QWEN3" -ngl 99 -fa 1 \
    --cache-type-k "$kv" --cache-type-v "$kv" -c "$ctx" --host 127.0.0.1 --port "$PORT" \
    > "$WORK_DIR/vram/$cond.server.log" 2>&1 & srv=$!
  for _ in $(seq 1 90); do          # health-wait with dead-server sentinel
    kill -0 $srv 2>/dev/null || { echo "server exited (OOM/crash)" >>"$WORK_DIR/vram/$cond.server.log"; break; }
    [ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/health" 2>/dev/null)" = 200 ] && break
    sleep 2
  done
  sleep 2
  echo "$cond peak_line=$(sort -t, -k2 -n "$WORK_DIR/vram/$cond.csv" | tail -1)" >> "$WORK_DIR/vram/peaks.txt"
  kill -9 $srv 2>/dev/null || true; kill $sp 2>/dev/null || true
  fuser -k "$PORT/tcp" 2>/dev/null || true; sleep 2
done

# --- optional L4 ncu per-kernel profile (set NCU_BIN in config) ---
if [ -n "${NCU_BIN:-}" ]; then
  for kv in f16 turbo4; do
    log "ncu $kv"
    sudo "$NCU_BIN" --metrics dram__bytes_read.sum,dram__throughput.avg.pct_of_peak_sustained_elapsed,sm__throughput.avg.pct_of_peak_sustained_elapsed \
      --launch-count 30 --target-processes all --csv \
      "$LB" -m "$MODEL_DIR/$MODEL_QWEN3" -ngl 99 -fa 1 -ctk "$kv" -ctv "$kv" -p 0 -n 8 -d 2048 -r 1 \
      > "$WORK_DIR/ncu/ncu__kv$kv__d2048.csv" 2> "$WORK_DIR/ncu/ncu__kv$kv__d2048.log" || true
  done
fi
log "matrix done: bench=$WORK_DIR/bench  vram=$WORK_DIR/vram/peaks.txt"
