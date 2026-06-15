#!/usr/bin/env bash
# whichllm-style calibration: pp512/tg128, depth 0, f16 KV, REPS reps, 4 models.
# Produces the measured tok/s used to validate a bandwidth model. Ref: ansible/playbooks/calib.yml
set -uo pipefail
source "$(dirname "$0")/lib/common.sh"
preflight
mkdir -p "$WORK_DIR/calib/bench"
for m in "$MODEL_QWEN3" "$MODEL_LLAMA32" "$MODEL_SMOLLM2" "$MODEL_MINICPM"; do
  [ -f "$MODEL_DIR/$m" ] || { log "skip (missing): $m"; continue; }
  tag="${m%.gguf}"; log "calib $tag"
  "$LB" -m "$MODEL_DIR/$m" -ngl 99 -fa 1 -p 512 -n 128 -r "$REPS" -o jsonl \
    > "$WORK_DIR/calib/bench/$tag.jsonl" 2> "$WORK_DIR/calib/bench/$tag.err" || log "  ($tag err)"
done
log "calib done -> $WORK_DIR/calib/bench"
