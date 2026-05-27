---
id: DS007
title: Python Services
status: accepted
owner: repository
summary: Translation and reranker Flask services, model loading, health gating, and API contracts.
---

# DS007 Python Services

## Introduction

Two agents require Python-backed HTTP services instead of Ollama or llama.cpp: the translation agent (`language-translation`) and the relevance agent (`relevance`). These services bridge HuggingFace model libraries to a simple HTTP API that the MCP dispatcher can call via curl. This specification defines the service architecture, API contracts, and health semantics.

## Core Content

### Translation Service

`scripts/services/translation_service.py` is a Flask application that serves encoder-decoder seq2seq translation models. It is launched by the `transformers-seq2seq.sh` runner.

**Startup behavior**: The service loads the specified model at startup using `transformers.AutoTokenizer` and `transformers.AutoModelForSeq2SeqLM`, then constructs a `pipeline("translation")` instance. If model loading fails, the service prints an error and calls `sys.exit(1)`, which causes the runner (and consequently `start-agent.sh`) to detect the failure and abort. The service does not attempt to retry model loading.

**Health endpoint**: `GET /health` returns `200 {"status": "ok", "model": "<name>"}` when the model is loaded, and `503 {"status": "not_loaded", "model": "none"}` before loading completes. This gated health is critical because the readiness probe must not report success until the model is actually available for inference.

**Translation endpoint**: `POST /translate` accepts `{ "text": "...", "source_lang": "...", "target_lang": "..." }`. Both `text` and `target_lang` are required; `source_lang` is optional (some models auto-detect). The service sets `tokenizer.src_lang` when the tokenizer supports it (M2M100 uses this for language pair selection). Returns `{ "translation": "...", "model": "<name>" }` on success and `{ "error": "..." }` with status 500 on failure.

**Models endpoint**: `GET /models` returns the currently loaded model name and status. This is informational and not used by the healthcheck.

The default model is `facebook/m2m100_418M`, a 418M-parameter encoder-decoder model that supports 100 languages. The alternative `google/madlad400-3b-mt` is a 3B-parameter T5-based model with broader language coverage.

### Reranker Service

`scripts/services/reranker_service.py` is a Flask application that serves cross-encoder scoring models. It is launched by the `reranker.sh` runner.

**Startup behavior**: The service loads the model using `sentence_transformers.CrossEncoder` with `trust_remote_code=True`. The CrossEncoder class is specifically chosen over `AutoModelForSequenceClassification` because the Qwen3 Reranker model requires the cross-encoder interface for correct scoring. If model loading fails, the service exits nonzero.

**Health endpoint**: Same gated behavior as the translation service — 503 until loaded, 200 when ready.

**Rerank endpoint**: `POST /rerank` accepts `{ "query": "...", "passages": ["..."], "top_k": N, "instruction": "..." }`. The `query` and `passages` fields are required. When `instruction` is provided, the service prepends it to the query in the format `"Instruct: {instruction}\nQuery: {query}"`, which is the prompt format expected by instruction-aware rerankers like Qwen3-Reranker.

The service constructs query-passage pairs, calls `model.predict()` with `convert_to_numpy=True`, sorts results by score descending, truncates to `top_k` if specified, and truncates each passage to 200 characters in the response. Returns `{ "results": [...], "model": "<name>" }` where each result has `index`, `score`, and `passage`.

**Models endpoint**: Same as translation service.

The default model is `Qwen/Qwen3-Reranker-0.6B`, a 0.6B-parameter cross-encoder supporting 100+ languages and 32k token context.

### Shared Patterns

Both services follow the same architectural pattern: single-file Flask app, global model instance with lazy loading, gated health endpoint, startup preload with fail-fast exit, and a runner script that sets the HuggingFace cache environment before launching. Both use `app.run()` directly (development server) rather than gunicorn, since each service handles low concurrency within a single agent container.

## Decisions & Questions

### Question #1: Should the services use gunicorn in production?

Response: Gunicorn is installed in the Docker image but not currently used. For single-agent containers with low concurrency, Flask's development server is adequate. If multiple concurrent requests become a concern, the runner scripts should be updated to launch via `gunicorn --workers 1 --bind $HOST:$PORT`.

### Question #2: Should model switching be supported without agent restart?

Options:
- Add a `POST /load` endpoint that accepts a model name and hot-swaps the loaded model.
- Keep the current design where model switching requires an agent restart, which is simpler and avoids memory management complexity.

## Conclusion

The two Python services provide translation and reranking capabilities through Flask HTTP APIs with gated health endpoints and fail-fast startup. They bridge HuggingFace model libraries to the shell-based MCP dispatcher via curl.
