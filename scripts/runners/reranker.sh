#!/bin/sh
set -e

BACKEND_PORT="${LOCAL_LLMS_BACKEND_PORT:-8091}"
DATA_DIR="${LOCAL_LLMS_DATA_DIR:-/data/local-llms}"
MODEL_NAME="${LOCAL_LLMS_DEFAULT_MODEL:-Qwen/Qwen3-Reranker-0.6B}"

export TRANSFORMERS_CACHE="${DATA_DIR}/transformers/cache"
export HF_HOME="${DATA_DIR}/transformers/cache"

mkdir -p "$TRANSFORMERS_CACHE"

RUNTIME_DIR="${LOCAL_LLMS_RUNTIME_DIR:-/opt/local-llms}"

echo "[reranker] Starting reranker service for model: $MODEL_NAME on port $BACKEND_PORT"
exec python3 "${RUNTIME_DIR}/scripts/services/reranker_service.py" \
    --model "$MODEL_NAME" \
    --port "$BACKEND_PORT" \
    --host 0.0.0.0
