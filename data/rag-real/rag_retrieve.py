#!/usr/bin/env python3
"""Mirror Shaik (2025) LegacyRAG retrieval: chunk a document into 512-char
overlapping windows, embed each via Ollama nomic-embed-text into normalized
768-d vectors, and for each question retrieve top-k chunks by cosine similarity
(brute-force over a flat in-memory store, as Shaik's NumPy store does).

Deviation from Shaik, documented: we suppress near-duplicate retrieved chunks
(char-trigram Jaccard > 0.6) so the heavy window overlap does not hand back a
repetitive context — the whole point of this fixture is a DIVERSE context that
de-confounds the pathological repeated-sentence prompt (register V1).

Stdlib only (urllib/json/math) so it runs on the bare gpu-host python3.
Usage: rag_retrieve.py <corpus.txt> <questions.json> <outdir> [ollama_url] [top_k]
"""
import sys, json, math, urllib.request, os

CORPUS, QFILE, OUTDIR = sys.argv[1], sys.argv[2], sys.argv[3]
OLLAMA = sys.argv[4] if len(sys.argv) > 4 else "http://127.0.0.1:11434"
TOP_K = int(sys.argv[5]) if len(sys.argv) > 5 else 8
WIN, STRIDE = 512, 256          # 512-char windows, 50% overlap (Shaik: overlapping windows)
EMBED_MODEL = "nomic-embed-text"

def embed(text):
    body = json.dumps({"model": EMBED_MODEL, "prompt": text}).encode()
    req = urllib.request.Request(OLLAMA + "/api/embeddings", data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        v = json.load(r)["embedding"]
    n = math.sqrt(sum(x * x for x in v)) or 1.0
    return [x / n for x in v]

def cos(a, b):                    # both already L2-normalized
    return sum(x * y for x, y in zip(a, b))

def trigrams(s):
    s = " ".join(s.lower().split())
    return {s[i:i+3] for i in range(max(0, len(s) - 2))}

def jaccard(a, b):
    if not a or not b: return 0.0
    return len(a & b) / len(a | b)

text = open(CORPUS).read()
chunks = [text[i:i+WIN] for i in range(0, max(1, len(text) - WIN + 1), STRIDE)]
chunks = [c.strip() for c in chunks if c.strip()]
print(f"chunks: {len(chunks)} (win={WIN} stride={STRIDE})", flush=True)
cvecs = [embed(c) for c in chunks]
ctri = [trigrams(c) for c in chunks]
print("embedded all chunks", flush=True)

os.makedirs(os.path.join(OUTDIR, "prompts"), exist_ok=True)
qs = json.load(open(QFILE))["questions"]
manifest = []
for q in qs:
    qv = embed(q["q"])
    ranked = sorted(range(len(chunks)), key=lambda i: cos(qv, cvecs[i]), reverse=True)
    picked = []
    for i in ranked:
        if any(jaccard(ctri[i], ctri[j]) > 0.6 for j in picked):
            continue           # near-duplicate of an already-picked chunk
        picked.append(i)
        if len(picked) >= TOP_K:
            break
    ctx = "\n\n".join(f"[{n+1}] {chunks[i]}" for n, i in enumerate(picked))
    prompt = ("You are a helpful assistant. Use only the provided context to "
              "answer the question concisely.\n\nContext:\n" + ctx +
              f"\n\nQuestion: {q['q']}\nAnswer:")
    open(os.path.join(OUTDIR, "prompts", q["id"] + ".txt"), "w").write(prompt)
    manifest.append({"id": q["id"], "q": q["q"], "gold": q["gold"],
                     "chunk_ids": picked,
                     "scores": [round(cos(qv, cvecs[i]), 4) for i in picked],
                     "prompt_chars": len(prompt)})
    print(f"  {q['id']}: top-{len(picked)} chunks, {len(prompt)} chars", flush=True)

json.dump({"win": WIN, "stride": STRIDE, "top_k": TOP_K, "embed_model": EMBED_MODEL,
           "n_chunks": len(chunks), "questions": manifest},
          open(os.path.join(OUTDIR, "retrieval_manifest.json"), "w"), indent=2)
print("wrote retrieval_manifest.json", flush=True)
