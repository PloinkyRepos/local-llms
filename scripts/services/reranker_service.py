import argparse
import sys
import os
from numbers import Number

from flask import Flask, request, jsonify

app = Flask(__name__)
model_instance = None
model_name_loaded = None

def load_model(model_name):
    global model_instance, model_name_loaded
    if model_name_loaded == model_name and model_instance is not None:
        return model_instance

    from sentence_transformers import CrossEncoder

    model_instance = CrossEncoder(model_name, trust_remote_code=True)
    model_name_loaded = model_name
    return model_instance

@app.route("/health", methods=["GET"])
def health():
    if model_instance is None:
        return jsonify({"status": "not_loaded", "model": model_name_loaded or "none"}), 503
    return jsonify({"status": "ok", "model": model_name_loaded})

@app.route("/rerank", methods=["POST"])
def rerank():
    body = request.get_json(force=True, silent=True) or {}
    query = body.get("query", "")
    passages = body.get("passages", [])
    top_k = body.get("top_k", body.get("topK"))
    instruction = body.get("instruction")

    if not query:
        return jsonify({"error": "query is required"}), 400
    if not passages:
        return jsonify({"error": "passages is required"}), 400

    try:
        name = model_name_loaded or os.environ.get("LOCAL_LLMS_DEFAULT_MODEL", "Qwen/Qwen3-Reranker-0.6B")
        model = load_model(name)

        pairs = []
        for passage in passages:
            if instruction:
                pairs.append([f"Instruct: {instruction}\nQuery: {query}", passage])
            else:
                pairs.append([query, passage])

        scores = model.predict(
            pairs,
            convert_to_numpy=True,
            show_progress_bar=False,
        )
        if hasattr(scores, "tolist"):
            scores = scores.tolist()
        if isinstance(scores, Number):
            scores = [scores]

        results = []
        for i, (passage, score) in enumerate(zip(passages, scores)):
            if isinstance(score, list):
                score = score[0] if score else 0
            results.append({
                "index": i,
                "score": float(score),
                "passage": passage[:200]
            })

        results.sort(key=lambda x: x["score"], reverse=True)

        if isinstance(top_k, Number) and top_k > 0:
            results = results[:int(top_k)]

        return jsonify({"results": results, "model": name})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/models", methods=["GET"])
def models():
    return jsonify({
        "loaded": model_name_loaded,
        "status": "ready" if model_instance else "not_loaded"
    })

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="Qwen/Qwen3-Reranker-0.6B")
    parser.add_argument("--port", type=int, default=8091)
    parser.add_argument("--host", default="0.0.0.0")
    args = parser.parse_args()

    print(f"[reranker_service] Loading model: {args.model}")
    try:
        load_model(args.model)
        print(f"[reranker_service] Model loaded successfully")
    except Exception as e:
        print(f"[reranker_service] ERROR: Model load failed: {e}", file=sys.stderr)
        sys.exit(1)

    app.run(host=args.host, port=args.port)
