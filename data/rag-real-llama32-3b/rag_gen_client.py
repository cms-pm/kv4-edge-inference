#!/usr/bin/env python3
"""Fire every retrieved RAG question at a running llama-server /completion and
record the generation + timings + ngram acceptance for one (KV, spec) config.
Greedy (temperature 0), cache_prompt off so each prefill/TTFT is fresh.
Stdlib only. Usage: rag_gen_client.py <server_url> <prompts_dir> <manifest.json> <out.json> [n_predict]
"""
import sys, json, time, urllib.request, os

URL, PDIR, MAN, OUT = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
NPRED = int(sys.argv[5]) if len(sys.argv) > 5 else 128
qs = json.load(open(MAN))["questions"]
rows = []
for q in qs:
    prompt = open(os.path.join(PDIR, q["id"] + ".txt")).read()
    body = json.dumps({"prompt": prompt, "n_predict": NPRED, "temperature": 0,
                       "cache_prompt": False}).encode()
    req = urllib.request.Request(URL, data=body, headers={"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=300) as r:
        j = json.load(r)
    wall = time.time() - t0
    tm = j.get("timings", {})
    dn, da = tm.get("draft_n"), tm.get("draft_n_accepted")
    rows.append({
        "id": q["id"], "gold": q["gold"], "content": j.get("content", ""),
        "wall_s": round(wall, 3),
        "prefill_t_s": tm.get("prompt_per_second"), "prompt_n": tm.get("prompt_n"),
        "decode_t_s": tm.get("predicted_per_second"), "predicted_n": tm.get("predicted_n"),
        "draft_n": dn, "draft_n_accepted": da,
        "accept_rate": (da / dn if dn else None),
    })
    print(f"  {q['id']}: decode {tm.get('predicted_per_second',0):.1f} t/s "
          f"accept={rows[-1]['accept_rate']}", flush=True)
json.dump(rows, open(OUT, "w"), indent=2)
