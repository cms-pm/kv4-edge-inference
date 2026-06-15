#!/usr/bin/env bash
# Shared preflight / telemetry / teardown for the kv4 portable runners.
# Sourced by scripts/run_*.sh. Reads config/local.env (else config/example.env).
set -uo pipefail

_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"        # scripts/
ROOT="$(cd "$_HERE/.." && pwd)"
CFG="${KV4_CONFIG:-$ROOT/config/local.env}"; [ -f "$CFG" ] || CFG="$ROOT/config/example.env"
# shellcheck disable=SC1090
source "$CFG"
export LD_LIBRARY_PATH="${CUDA_LIB}:${LD_LIBRARY_PATH:-}"

LB="$LLAMA_BIN_DIR/llama-bench"
LS="$LLAMA_BIN_DIR/llama-server"
SIDECAR_Q="timestamp,utilization.gpu,utilization.memory,memory.used,power.draw,temperature.gpu,clocks.current.sm,clocks.current.memory,pstate"
log(){ echo "[kv4] $*" >&2; }

preflight(){
  mkdir -p "$WORK_DIR"/{bench,gpu-telemetry,vram,ncu}
  command -v nvidia-smi >/dev/null || { log "nvidia-smi not found"; exit 1; }
  [ -x "$LB" ] || { log "llama-bench not at $LB (set LLAMA_BIN_DIR in config)"; exit 1; }
  sudo nvidia-smi -pm 1 >/dev/null 2>&1 || log "persistence mode skipped (no sudo?)"
  # reap our own leftover servers by SOCKET only — never pkill the binary path
  for p in 11435 11436 11437 "$PORT"; do fuser -k "${p}/tcp" 2>/dev/null || true; done
  sleep 2
  # sole-tenant assert: abort if any other process holds the GPU
  apps=$(nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader | tr -d '[:space:]')
  [ -z "$apps" ] || { log "ABORT: GPU not sole-tenant ($apps)"; exit 1; }
  [ -n "${VRAM_SERVICE:-}" ] && sudo systemctl stop "$VRAM_SERVICE" 2>/dev/null || true
  sudo nvidia-smi --lock-gpu-clocks="$CLOCK_LOCK" >/dev/null 2>&1 || log "clock lock skipped (no sudo?)"
  { echo "=== clocks (locked) ==="; nvidia-smi --query-gpu=clocks.current.sm,clocks.current.memory --format=csv,noheader
    echo "=== kernel ==="; uname -r
    echo "=== driver ==="; nvidia-smi --query-gpu=driver_version --format=csv,noheader
    echo "=== gpu ==="; nvidia-smi --query-gpu=name,memory.total,clocks.max.memory,clocks.max.sm --format=csv,noheader
  } > "$WORK_DIR/host-inventory.txt" 2>/dev/null
  "$LB" -m "$MODEL_DIR/$MODEL_QWEN3" -ngl 99 -fa 1 -p 256 -n 128 -r 1 >/dev/null 2>&1 || true  # warmup
  log "preflight done; evidence -> $WORK_DIR"
}

sidecar_start(){ nvidia-smi --query-gpu="$SIDECAR_Q" --format=csv,noheader,nounits -lms 1000 > "$1" 2>/dev/null & echo $!; }
sidecar_stop(){ kill "$1" 2>/dev/null || true; }

teardown(){
  sudo nvidia-smi --reset-gpu-clocks >/dev/null 2>&1 || true
  [ -n "${VRAM_SERVICE:-}" ] && sudo systemctl start "$VRAM_SERVICE" 2>/dev/null || true
  log "teardown: clocks reset"
}
trap teardown EXIT
