# Realistic-RAG arm (register E1) — findings (2026-06-14)

Clean clock-locked run of `kv4-rag-real.yml` (PLAY RECAP ok=18 failed=0).
**Retrieval mirrors Shaik exactly**: corpus = Shaik (2025) LegacyRAG paper
(`shaik-corpus.txt`, 20.5 K chars), chunked 512-char/256-stride, embedded via
**Ollama nomic-embed-text** (768-d, L2-normalized), brute-force cosine top-8 per
question with near-duplicate suppression (Jaccard>0.6). 8 extractive-QA questions
whose answers are spread across the document. Generation: Qwen3-1.7B Q4_K_M,
`llama-server`, c4096, greedy (temp 0), n_predict 128, kv∈{f16,turbo4} ×
spec∈{off, ngram-cache}. **This de-confounds the pathological repeated-sentence
fixture (register V1) and the result inverts the prior headline.**

## Headline: kv4 has a real ACCURACY cost on diverse RAG
| config | accuracy (gold substring EM) | mean decode t/s | mean ngram accept |
|---|---|---|---|
| f16 spec-off    | **8/8** | 63.3 | — |
| f16 spec-ngram  | **8/8** | 47.0 | 0.136 |
| turbo4 spec-off    | **4/8** | 55.8 | — |
| turbo4 spec-ngram  | **3/8** | 38.6 | 0.058 |

turbo4 KV quant roughly **halves** extractive-QA accuracy (8/8 → 4/8). The
pathological fixture hid this entirely — there both KV types "answered" a single
repeated sentence. (q8 turbo4 is a near-miss: it answered "0" not "zero", so
substance is ~5/8; the loss is real regardless.)

## Failure mode = degeneration + hallucination (NOT clean copying)
turbo4 wrong answers on diverse context (vs f16 correct, coherent):
- **q3** WRONG: loops "The answer is: generation throughput" (should be 50×).
- **q4** WRONG: loops "The answer must be contained within 300 words." (ignores Q).
- **q7** WRONG: "765-dimensional vectors" (hallucinated; should be nomic-embed-text/768).
- **q1** OK-but-polluted: adds "memory capacity is 45.52 GB" (card is 4 GB).
- **q2/q5/q8** OK-but-degenerate: correct value then "The answer is X." loops; q2
  even drifts 99.86 → 99.66 (numeric corruption).

So turbo4's degeneracy is **real**, but on diverse input it manifests as
incoherent looping + hallucinated numbers that cost correctness — not the tidy
verbatim-copy of the pathological fixture. The §4.5 "verbatim repetition" framing
was a fixture artifact; the general failure mode is accuracy loss.

## ngram on realistic RAG: low acceptance, and it HURTS
- Acceptance collapses vs the pathological 0.88: f16 ≈0.14, **turbo4 ≈0.06**
  (turbo4 now LOWER than f16, the reverse of the artifact).
- ngram reduces decode for both (f16 63→47, turbo4 56→39) — acceptance is far too
  low to pay for draft/verify overhead. **The "ngram flips the verdict" claim
  from the pathological fixture is FALSE on real RAG.**
- The §4.1 decode penalty holds and is not rescued: turbo4-off 56 < f16-off 63;
  turbo4+ngram 39 ≪ f16-off 63.

## Spec-preservation control FAILED (important caveat)
Speculative decoding is supposed to be output-preserving (Leviathan 2023), but on
this fork it is **not**: spec-off vs spec-ngram were byte-identical in only 4/8
(f16) and 1/8 (turbo4) questions, and turbo4 accuracy changed 4→3 with ngram on.
Likely cause: variable speculative batch shapes change FP reduction order →
argmax flips on near-ties under greedy. **Consequence:** we cannot treat
ngram-accelerated output as identical to non-speculative output on this stack;
acceptance is a speed signal, not a free lunch, and must be reported with this
caveat. (It also means the degeneracy is attributable to KV quant *and* the spec
path is not neutral — report both.)

## Paper impact (supersedes pathological §4.5)
- New headline for §4.5: on realistic RAG, **kv4 costs accuracy (8/8→4/8)**;
  ngram acceptance is low (≤0.14) and ngram *hurts* decode; the pathological
  fixture's 0.88-accept "flip" was an artifact of a repeated-sentence prompt.
- Keep the pathological fixture only as a labelled worst-case illustration of how
  a bad RAG prompt can manufacture a misleading speedup.
- Add the accuracy axis to §4.4/§4.5 and the spec-non-preservation caveat.
