#!/usr/bin/env bash
# Realistic RAG arm with a quality probe (paper Fig. 2 / Sec 4.5).
# Mirrors Shaik (2025) retrieval (nomic-embed-text, 512/256 chunks, cosine top-k)
# then scores extractive-QA accuracy (gold-substring EM) under {f16,turbo4} x {off,ngram}.
#
# YOU SUPPLY the corpus + questions (we cannot redistribute the paper's corpus):
#   RAG_CORPUS=/path/corpus.txt   (in config)   and   rag/questions.json
#   (format: rag/questions.example.json — {"questions":[{"id","q","gold"},...]})
# Needs Ollama running with the embedding model:  ollama pull "$EMBED_MODEL"
# Ref: ansible/playbooks/rag-real.yml
set -uo pipefail
source "$(dirname "$0")/lib/common.sh"
QF="${1:-$ROOT/rag/questions.json}"
[ -n "${RAG_CORPUS:-}" ] && [ -f "$RAG_CORPUS" ] || { log "set RAG_CORPUS to your corpus .txt"; exit 1; }
[ -f "$QF" ] || { log "questions file not found: $QF (see rag/questions.example.json)"; exit 1; }
preflight
R="$WORK_DIR/rag-real"; mkdir -p "$R"/{prompts,results}
M="$MODEL_DIR/$MODEL_QWEN3"

log "retrieval (nomic-embed-text via Ollama)…"
python3 "$ROOT/rag/retrieve.py" "$RAG_CORPUS" "$QF" "$R/prompts" || { log "retrieval failed (is Ollama up?)"; exit 1; }
MAN="$R/prompts/manifest.json"

grade(){ python3 - "$1" "$2" <<'PY'
import json,sys; gen=open(sys.argv[1]).read().lower(); gold=sys.argv[2].lower()
print("HIT" if gold in gen else "MISS")
PY
}

for kv in f16 turbo4; do
  for spec in off ngram; do
    cfg="${kv}_spec${spec}"; log "RAG $cfg"
    fuser -k "$PORT/tcp" 2>/dev/null || true; sleep 2
    sa=(); [ "$spec" = ngram ] && sa=(--draft-max 16 --draft-min 1)   # prompt-lookup ngram
    nohup "$LS" -m "$M" -ngl 99 -fa 1 --cache-type-k "$kv" --cache-type-v "$kv" \
      -c 4096 "${sa[@]}" --host 127.0.0.1 --port "$PORT" > "$R/results/$cfg.server.log" 2>&1 & srv=$!
    for _ in $(seq 1 90); do kill -0 $srv 2>/dev/null || break
      [ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/health" 2>/dev/null)" = 200 ] && break; sleep 2; done
    hits=0; n=0
    while read -r qid; do
      n=$((n+1))
      prompt=$(python3 -c "import json,sys;m=json.load(open('$MAN'));print(next(x['prompt'] for x in m['questions'] if x['id']==sys.argv[1]))" "$qid")
      gold=$(python3 -c "import json,sys;m=json.load(open('$MAN'));print(next(x['gold'] for x in m['questions'] if x['id']==sys.argv[1]))" "$qid")
      curl -s "http://127.0.0.1:$PORT/completion" \
        -d "$(python3 -c "import json,sys;print(json.dumps({'prompt':sys.argv[1],'n_predict':128,'temperature':0}))" "$prompt")" \
        > "$R/results/${cfg}__${qid}.json" 2>/dev/null || true
      gen=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('content',''))" "$R/results/${cfg}__${qid}.json")
      echo "$gen" > "$R/results/${cfg}__${qid}.txt"
      [ "$(grade "$R/results/${cfg}__${qid}.txt" "$gold")" = HIT ] && hits=$((hits+1))
    done < <(python3 -c "import json;[print(q['id']) for q in json.load(open('$MAN'))['questions']]")
    echo "$cfg accuracy=$hits/$n" | tee -a "$R/results/SUMMARY.txt"
    kill -9 $srv 2>/dev/null || true; fuser -k "$PORT/tcp" 2>/dev/null || true; sleep 2
  done
done
log "RAG done -> $R/results/SUMMARY.txt"
