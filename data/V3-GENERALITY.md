# V3 generality — kv4 across three model families (2026-06-14)

Register item V3 (single-model gap). Re-ran the realistic-RAG arm
(`kv4-rag-real.yml`, identical retrieved prompts) on two more families, both
plain *instruct* (non-tool) variants, full-GPU no-offload, clock-locked:
Llama-3.2-3B-Instruct and SmolLM2-1.7B-Instruct (SCN-3.1 candidates A3, A4).
Evidence: `evidence/rag-real{,-llama32-3b,-smollm2-1.7b}/`.

## Cross-model summary (realistic RAG, spec-off, 8 extractive-QA Qs)
| model | family | params | f16 acc | turbo4 acc | f16 decode t/s | turbo4 decode t/s | turbo4 penalty | turbo4 repetition (rep4 vs f16) |
|---|---|---|---|---|---|---|---|---|
| Qwen3-1.7B   | Qwen3   | 1.7B | 8/8 | **4/8** | 63.3 | 55.8 | −12 % | ~0.62 vs 0.62 (both loop; noisy) |
| Llama-3.2-3B | Llama-3 | 3B   | 8/8 | **7/8** | 48.5 | 38.5 | −21 % | 0.004 vs 0.012 (stays coherent) |
| SmolLM2-1.7B | SmolLM2 | 1.7B | 8/8 | **7/8** | 80.1 | 40.2 | **−50 %** | 0.320 vs 0.105 (clearly degenerates) |
| MiniCPM5-1B  | MiniCPM | 1B   | 6/8 | **6/8** | 122.8 | 92.4 | −25 % | 0.331 vs 0.204 (degenerates, no net acc loss) |

MiniCPM5-1B (gate: [[../cpm-gate/GATE.md]]) is the 1B capability-ceiling reference.
Its f16 baseline is already the lowest (6/8) and turbo4 does **not** lower it
further (6/8) — so the kv4 accuracy cost is **not universal**: it is 0 here, −1 on
Llama/SmolLM2, −4 on Qwen3. turbo4 still makes MiniCPM more repetitive (rep4
0.204→0.331) without costing net correctness.

## What generalizes (direction) vs what doesn't (magnitude)
1. **Decode penalty — universal, magnitude model-specific.** turbo4 is slower
   than f16 on all three (−12 %, −21 %, −50 %). The relative hit is *largest*
   where f16 decode is *fastest* (SmolLM2 80→40), consistent with §4.3: turbo4's
   cost is a fixed per-step kernel-overhead cascade, so it dominates more when the
   f16 attention it replaces is cheap. Mechanism replicates across families.
2. **Accuracy cost — real but NOT universal.** turbo4 ≤ f16 on all four, but the
   loss ranges 0 to −4/8: Qwen3 −4, Llama −1, SmolLM2 −1, **MiniCPM 0** (the 4th
   family falsifies "every family"). Not predicted by size (the 1B MiniCPM loses
   nothing; the 1.7B Qwen3 loses most). Headline must read "kv4 costs accuracy on
   most families (3 of 4), severely on Qwen3-1.7B, not at all on MiniCPM5-1B" —
   never "kv4 halves accuracy."
3. **Degeneracy under turbo4 — model-specific.** SmolLM2 clearly degenerates
   (rep4 0.105→0.320, distinct-2 0.86→0.64); Qwen3 loops (both KV types high, the
   metric is noisy); Llama-3.2-3B stays coherent (rep ~0, its single miss is a
   plain error, not a loop). KV quant *can* trigger repetition degeneration, but
   whether it does is model-dependent.
4. **ngram — universally weak on real RAG.** Acceptance ≤0.14 for all three;
   ngram *slows* decode in every case (no input-copying to exploit).
5. **ngram not output-preserving — universal.** spec-off vs spec-ngram differ on
   every model (f16 identical 4/8 Qwen3, 8/8 Llama, 5/8 SmolLM2; turbo4 1–4/8).
   The fork's `ngram-cache` changes greedy output (FP/argmax-tie); confirmed
   across families, so it is a fork property, not a per-model fluke.

## Paper impact
- §4.5: soften "halves accuracy (8/8→4/8)" to the cross-family statement (cost on
  all three, Qwen3 worst). Add the 3-family table; report the decode-penalty range
  (−12 % to −50 %) and tie the magnitude to §4.3 (fixed overhead vs f16 speed).
- §7: V3 (single-model) is now substantially addressed (three families, two sizes);
  remaining generality gaps are weight-quant (all Q4_K_M) and >4 GB models.
