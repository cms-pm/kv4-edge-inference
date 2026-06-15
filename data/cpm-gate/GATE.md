# MiniCPM5-1B kv4 pre-screen gate — VERDICT: PASS (2026-06-14)

SCN-3.1 flagged A5 (MiniCPM5-1B) as "per-arch kv4 (turbo4) on the sm_75 fork
**unverified** → pre-screen gate" because MiniCPM is non-strictly-vanilla
(`scale_emb` / `scale_depth`). Empirical-admission pre-screen
(`kv4-cpm-gate.yml`, clock-locked, sole-tenant). Both checks pass:

| check | f16 | turbo4 | verdict |
|---|---|---|---|
| **Functional** (llama-bench load+run, pp64/tg64) | tg 134.7 t/s | tg 118.3 t/s (−12 %) | turbo4 loads + runs on the arch; no crash |
| **Coherence** (greedy, "capital of France?") | "Paris. … London. … Washington D[C]" | "Paris … London … New Delhi" | turbo4 output coherent, not garbage/looping |

**Verdict: PASS** — turbo4 KV quantization is functional and coherent on
MiniCPM5-1B's non-vanilla architecture on the sm_75 TurboQuant fork (build
`2cbfdc6`). The SCN-3.1 A5 "turbo4 unverified" caveat is resolved; MiniCPM5-1B is
eligible for the full depth/VRAM/realistic-RAG (E1/V3) treatment.

**Caveats.**
- This gate confirms *eligibility* (loads, runs, coherent on a trivial prompt),
  not that MiniCPM avoids the §4.5 accuracy cost — the coherence prompt is a
  trivial capital-cities QA, not the harder retrieval-QA degeneration probe. A
  full E1 run would be needed to place MiniCPM in the §4.5 cross-family table.
- −12 % turbo4 decode penalty here is on a short pp64/tg64 bench at shallow depth
  (1B model, fastest of the pool at 134 t/s f16); the depth-resolved penalty
  (§4.1) is not measured by this gate.
