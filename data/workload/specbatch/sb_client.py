# Fire NPL concurrent identical /completion requests for REPS bursts;
# report aggregate decode tok/s (sum predicted tokens / burst wall),
# mean per-request decode tok/s, and ngram acceptance if reported.
import sys, json, time, urllib.request, concurrent.futures, statistics
url, promptfile = sys.argv[1], sys.argv[2]
npl, npred = int(sys.argv[3]), int(sys.argv[4])
outp = sys.argv[5]
reps = int(sys.argv[6]) if len(sys.argv) > 6 else 3
prompt = open(promptfile).read()
payload = {"prompt": prompt, "n_predict": npred, "temperature": 0, "cache_prompt": False}
def fire(_i):
    data = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        j = json.load(r)
    tm = j.get("timings", {})
    return {k: tm.get(k) for k in ("prompt_n", "prompt_ms", "prompt_per_second",
            "predicted_n", "predicted_ms", "predicted_per_second",
            "draft_n", "draft_n_accepted")}
bursts = []
for _ in range(reps):
    t0 = time.time()
    with concurrent.futures.ThreadPoolExecutor(max_workers=npl) as ex:
        res = list(ex.map(fire, range(npl)))
    wall = time.time() - t0
    agg = sum((r["predicted_n"] or 0) for r in res)
    dn = sum((r["draft_n"] or 0) for r in res)
    da = sum((r["draft_n_accepted"] or 0) for r in res)
    bursts.append({"wall_s": wall, "agg_predicted": agg,
                   "agg_decode_tok_s": (agg / wall if wall > 0 else 0),
                   "mean_req_decode_tok_s": statistics.mean((r["predicted_per_second"] or 0) for r in res),
                   "draft_n": dn, "draft_n_accepted": da,
                   "accept_rate": (da / dn if dn else None), "res": res})
aggs = [b["agg_decode_tok_s"] for b in bursts]
out = {"npl": npl, "reps": reps, "median_agg_decode_tok_s": statistics.median(aggs),
       "agg_decode_tok_s_runs": aggs,
       "median_mean_req_decode_tok_s": statistics.median(b["mean_req_decode_tok_s"] for b in bursts),
       "accept_rate_runs": [b["accept_rate"] for b in bursts], "bursts": bursts}
json.dump(out, open(outp, "w"), indent=2)
print(json.dumps({k: out[k] for k in ("npl", "median_agg_decode_tok_s",
      "median_mean_req_decode_tok_s", "accept_rate_runs")}))
