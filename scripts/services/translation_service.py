import argparse
import sys
import os

from flask import Flask, request, jsonify

app = Flask(__name__)
model_instance = None
model_name_loaded = None

def load_model(model_name):
    global model_instance, model_name_loaded
    if model_name_loaded == model_name and model_instance is not None:
        return model_instance

    from transformers import AutoTokenizer, AutoModelForSeq2SeqLM, pipeline

    tokenizer = AutoTokenizer.from_pretrained(model_name)
    model = AutoModelForSeq2SeqLM.from_pretrained(model_name)
    model_instance = pipeline("translation", model=model, tokenizer=tokenizer)
    model_name_loaded = model_name
    return model_instance

@app.route("/health", methods=["GET"])
def health():
    if model_instance is None:
        return jsonify({"status": "not_loaded", "model": model_name_loaded or "none"}), 503
    return jsonify({"status": "ok", "model": model_name_loaded})

@app.route("/translate", methods=["POST"])
def translate():
    body = request.get_json(force=True, silent=True) or {}
    text = body.get("text", "")
    source_lang = body.get("source_lang", body.get("sourceLang"))
    target_lang = body.get("target_lang", body.get("targetLang"))

    if not text:
        return jsonify({"error": "text is required"}), 400
    if not target_lang:
        return jsonify({"error": "target_lang is required"}), 400

    try:
        name = model_name_loaded or os.environ.get("LOCAL_LLMS_DEFAULT_MODEL", "facebook/m2m100_418M")
        pipe = load_model(name)

        kwargs = {}
        if source_lang:
            kwargs["src_lang"] = source_lang
        if target_lang:
            kwargs["tgt_lang"] = target_lang

        if hasattr(pipe.tokenizer, "src_lang"):
            if source_lang:
                pipe.tokenizer.src_lang = source_lang
        result = pipe(text, **kwargs)
        translated = result[0]["translation_text"] if result else ""
        return jsonify({"translation": translated, "model": name})
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
    parser.add_argument("--model", default="facebook/m2m100_418M")
    parser.add_argument("--port", type=int, default=8090)
    parser.add_argument("--host", default="0.0.0.0")
    args = parser.parse_args()

    print(f"[translation_service] Loading model: {args.model}")
    try:
        load_model(args.model)
        print(f"[translation_service] Model loaded successfully")
    except Exception as e:
        print(f"[translation_service] ERROR: Model load failed: {e}", file=sys.stderr)
        sys.exit(1)

    app.run(host=args.host, port=args.port)
