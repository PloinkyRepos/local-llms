#!/bin/sh
set -e

BACKEND_PORT="${LOCAL_LLMS_BACKEND_PORT:-8090}"
DATA_DIR="${LOCAL_LLMS_DATA_DIR:-/data/local-llms}"
MODEL_NAME="${LOCAL_LLMS_DEFAULT_MODEL:-facebook/m2m100_418M}"

export TRANSFORMERS_CACHE="${DATA_DIR}/transformers/cache"
export HF_HOME="${DATA_DIR}/transformers/cache"

mkdir -p "$TRANSFORMERS_CACHE"

RUNTIME_DIR="${LOCAL_LLMS_RUNTIME_DIR:-/opt/local-llms}"

echo "[transformers-seq2seq] Starting translation service for model: $MODEL_NAME on port $BACKEND_PORT"
exec python3 "${RUNTIME_DIR}/scripts/services/translation_service.py" \
    --model "$MODEL_NAME" \
    --port "$BACKEND_PORT" \
    --host 0.0.0.0
