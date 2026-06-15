#!/usr/bin/env bash
# Workload arms: prefill scaling, batch/continuous-batching, ngram speculative.
# (RAG end-to-end with a quality probe is scripts/run_rag.sh.)
# Exact-as-run reference (incl. precise flags for your build): ansible/playbooks/workload.yml
set -uo pipefail
source "$(dirname "$0")/lib/common.sh"
preflight
W="$WORK_DIR/workload"; mkdir -p "$W"/{bench,batch,lookup}
M="$MODEL_DIR/$MODEL_QWEN3"

# prefill scaling (pp at increasing prompt length), f16 vs turbo4
for kv in f16 turbo4; do
  log "prefill $kv"
  "$LB" -m "$M" -ngl 99 -fa 1 -ctk "$kv" -ctv "$kv" -p 2048,8192,32768 -n 0 -r "$REPS" -o jsonl \
    > "$W/bench/prefill__$kv.jsonl" 2> "$W/bench/prefill__$kv.err" || log "  (prefill $kv OOM/err)"
done

# batch / continuous batching (aggregate generation t/s vs concurrency)
BB="$LLAMA_BIN_DIR/llama-batched-bench"
[ -x "$BB" ] && for kv in f16 turbo4; do
  log "batch $kv"
  "$BB" -m "$M" -ngl 99 -fa 1 -ctk "$kv" -ctv "$kv" -c 8192 -npp 256 -ntg 128 -npl 1,2,4,8 \
    > "$W/batch/batch__$kv.txt" 2>&1 || log "  (batch $kv err)"
done || log "llama-batched-bench not found; skipping batch arm"

# ngram (prompt-lookup) speculative decoding
LK="$LLAMA_BIN_DIR/llama-lookup"
[ -x "$LK" ] && for kv in f16 turbo4; do
  log "lookup(ngram) $kv"
  "$LK" -m "$M" -ngl 99 -fa 1 -ctk "$kv" -ctv "$kv" -c 4096 -n 256 \
    > "$W/lookup/lookup__$kv.txt" 2>&1 || log "  (lookup $kv err)"
done || log "llama-lookup not found; skipping ngram arm"

log "workload done -> $W"
