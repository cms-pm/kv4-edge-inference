# kv4 workload arm — findings (2026-06-14)

Clean clock-locked run of `kv4-workload.yml` on gpu-host (GTX 1650, sm_75,
build A `2cbfdc6`). Sole-tenant, clocks locked to TDP, Ollama stopped; clocks
reset + Ollama restarted in Phase Z. `PLAY RECAP: ok=30 failed=0`.

## Phase B — prefill scaling (llama-bench pp, 5 reps, t/s)
| prompt tok | f16 | turbo4 |
|---|---|---|
| 2048 | 258.5 ± 0.06 | 254.6 ± 0.04 |
| 8192 | 187.9 ± 0.02 | 185.1 ± 0.03 |
| 32768 | **OOM** (failed to create context) | 88.3 ± 0.004 |

Prefill is compute-bound, ~1.5% KV-dtype effect where both fit; f16 cannot
allocate the 32K KV in 4 GB → prefill-side capacity win for turbo4.

## Phase C — RAG/coordinator e2e (server, c8192, 3532-tok prompt, 64-tok decode)
| KV | prefill t/s | TTFT | decode t/s | peak VRAM |
|---|---|---|---|---|
| f16 | 230.1 | 15.35 s | 49.5 | 2438 MiB |
| turbo4 | 230.5 | 15.33 s | 39.5 | 1768 MiB |

Identical TTFT; decode −20% (turbo4) but only 64 tokens → invisible e2e. −27% VRAM.

## Phase D — ngram (llama-lookup, single stream)
- Open-ended (no reuse): f16 accept 7.3% (7/96), decode 48.3; turbo4 accept
  13.6% (9/66), decode 58.8 t/s. Lever near-useless without input reuse.
- **RAG cells FAILED**: `GGML_ASSERT(n_tokens_all <= cparams.n_batch)` — the
  3.5K prompt exceeds default n_batch 2048. **Harness fixed: `-b 4096`** (not
  re-run; the RAG×ngram acceptance story is covered by Phase F server ngram).

## Phase E — batch sweep (llama-batched-bench, c8192, npp256/ntg128, agg tg t/s)
| npl | f16 | turbo4 |
|---|---|---|
| 1 | 70.9 | 59.3 |
| 2 | 117.9 | 98.7 |
| 4 | 132.4 | 108.2 |
| 8 | 157.0 | 123.4 |

Both ~2.1–2.2× from npl 1→8; turbo4 stays 16–22% below f16 at every batch
(per-step overhead divides with useful work, doesn't cancel). No OOM at c8192/npl8.

## Phase F — spec × batch (server, kv × spec × np, 3 bursts median)
Per-request decode t/s (np1) and ngram acceptance:
| KV | spec off | + ngram | accept |
|---|---|---|---|
| f16 | 58.5 | 44.7 | 0.30 |
| turbo4 | 50.4 | 79.5 | 0.88 |

**ngram flips the verdict on RAG**: turbo4+ngram (79.5) > f16+ngram (44.7) >
f16-off (58.5)? — no: turbo4+ngram (79.5) > f16-off (58.5) > f16+ngram (44.7).
ngram hurts f16 (overhead > 0.30 benefit), helps turbo4 +58%.

np4 (mean per-request decode): f16-off 11.0, f16-ngram 10.5, turbo4-off 10.7,
turbo4-ngram 14.3. ngram VRAM-free (+~2 MiB); np doesn't change KV footprint
(f16 ~2438, turbo4 ~1768 across all cells).

### DEGENERACY CAVEAT (important)
The 0.88 vs 0.30 acceptance gap is partly a degeneracy artifact. Generated text:
- f16: correct answer, then novel meta-commentary ("The answer is correct…").
- turbo4: correct first sentence, then **verbatim repetition** of the context.

ngram drafts the repeated span perfectly → high acceptance = output
repetitiveness as much as speedup. Both got the correct first-sentence answer.
KV quant raises acceptance AND degeneracy. Report the speedup with the quality
flag, never alone.
