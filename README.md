# kv4-edge-inference

[![Paper: SSRN 6941538](https://img.shields.io/badge/paper-SSRN%206941538-blue)](https://ssrn.com/abstract=6941538)
[![License: MIT](https://img.shields.io/github/license/cms-pm/kv4-edge-inference)](LICENSE)
[![Data: CC-BY-4.0](https://img.shields.io/badge/data-CC--BY--4.0-lightgrey)](data/LICENSE)

Reproduction package for **"The kv4 Trade-off Is Workload-Dependent: A Depth- and
Workload-Resolved Study of 4-bit KV-Cache Quantization on a 4 GB Turing GPU."**
Read the paper on SSRN: <https://ssrn.com/abstract=6941538>.

It contains everything needed to reproduce the study's measurements, analysis,
and figures: the experiment runners (portable bash **and** Ansible), the measured
evidence (so you can regenerate every number/figure **without a GPU**), the
analysis code, and the figure scripts. All host/path/model specifics are
configuration — adapt them to your own environment.

## What's measured

4-bit KV-cache quantization ("turbo4"/kv4) vs FP16 KV on a small GPU, resolved by
**decode depth**, **context length**, and **workload shape** (sustained decode vs
RAG/coordinator), plus speculative-decoding and batching arms. The reference rig
is an NVIDIA GTX 1650 (TU117, sm_75, 4 GB, GDDR6/192 GB/s); nothing is specific to
it beyond the documented config values.

## Layout

```
config/example.env        # copy to config/local.env; edit paths/models/clocks
scripts/                  # portable bash runners (run locally on the GPU host)
  lib/common.sh           #   preflight (clock-lock, sole-tenant, sidecar) + teardown
  run_matrix.sh           #   decode-vs-depth + VRAM-vs-context   (Fig. 1)
  run_workload.sh         #   prefill, batch/continuous-batching, ngram speculative
  run_rag.sh              #   realistic RAG + extractive-QA accuracy (Fig. 2)
  run_calib.sh            #   pp512/tg128 calibration (4 models)
  run_cpm_gate.sh         #   turbo4 pre-screen gate for a new model
ansible/                  # same experiments as Ansible playbooks (genericized)
  playbooks/*.yml         #   matrix / workload / rag-real / cpm-gate / calib
  inventory.example.ini   #   point [gpu] at your host
  group_vars/all.example.yml
analysis/
  analyze.py              # reproduce headline numbers from data/ (stdlib, no GPU)
  schema/*.sql            # reference data model for the evidence (DuckDB)
data/                     # MEASURED EVIDENCE from the paper's runs (2 MB)
figures/make_figures.py   # regenerate the paper's figures (matplotlib)
rag/                      # retrieval (nomic-embed-text) + example question set
```

## Quickstart A — reproduce the paper from shipped data (no GPU)

```bash
python3 analysis/analyze.py          # prints decode/prefill tok/s + VRAM peaks from data/
pip install matplotlib               # for the figures
python3 figures/make_figures.py      # writes fig_*.pdf from the measured numbers
```

## Quickstart B — re-run the experiments (needs the GPU + build)

**Prerequisites:** NVIDIA driver + CUDA; the **`llama-cpp-turboquant` fork**
(TheTom) built for your arch (the paper used commit `2cbfdc6`,
`-DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=<your_sm>`), exposing `turbo2/3/4` KV;
your GGUF models (Q4_K_M) in `MODEL_DIR`. For the RAG arm: Ollama with
`nomic-embed-text`.

```bash
cp config/example.env config/local.env   # then edit paths/models/clocks
bash scripts/run_matrix.sh                # decode + VRAM
bash scripts/run_calib.sh                 # calibration
bash scripts/run_workload.sh              # prefill / batch / ngram
bash scripts/run_rag.sh                   # realistic RAG (see corpus note below)
# results land in $WORK_DIR; then: python3 analysis/analyze.py $WORK_DIR
```

Ansible path (same experiments, remote host):

```bash
cp ansible/inventory.example.ini ansible/inventory.ini       # point [gpu] at your host
cp ansible/group_vars/all.example.yml ansible/group_vars/all.yml
ansible-playbook -i ansible/inventory.ini ansible/playbooks/matrix.yml -e matrix_profile=full
```

The bash runners capture the core methodology (clock-lock, sole-tenant assert,
1 Hz nvidia-smi sidecar, per-cell JSONL); the **Ansible playbooks are the
exact-as-run reference** (incl. the precise flags and the L4 `ncu` profile).

## RAG corpus note

The paper's RAG corpus is a third-party paper we cannot redistribute. `run_rag.sh`
expects **your own** `RAG_CORPUS` (a `.txt`) and a question set
(`rag/questions.json`; see `rag/questions.example.json` — each gold answer must
appear verbatim in your corpus). Retrieval mirrors Shaik (2025): nomic-embed-text,
512-char/256-stride chunks, cosine top-k, near-duplicate suppression.

## Honest hardware caveats (from the study)

- `power.draw` reads `[N/A]` on the GTX 1650 → no energy/Wh metric.
- Nsight Compute (`ncu`) gives the L4 per-kernel profile; set `NCU_BIN`. Without
  it, the bandwidth roofline is derivable post-hoc (tok/s × bytes/token vs peak BW).
- `turbo2/3/4` require the llama-cpp-turboquant fork; stock llama.cpp won't have them.

## Citation

See `CITATION.cff`. Code & data: https://github.com/cms-pm/kv4-edge-inference. Paper: SSRN 6941538 (https://ssrn.com/abstract=6941538).

## License

MIT (see `LICENSE`). The measured data under `data/` is released under
CC-BY-4.0 (see `data/LICENSE`) — attribute the paper.
