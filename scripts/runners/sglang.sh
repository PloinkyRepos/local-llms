#!/bin/sh
set -e

BACKEND_PORT="${LOCAL_LLMS_BACKEND_PORT:-8001}"
DATA_DIR="${LOCAL_LLMS_DATA_DIR:-/data/local-llms}"
MODEL_NAME="${LOCAL_LLMS_DEFAULT_MODEL:-}"

if [ -z "$MODEL_NAME" ]; then
    echo "[sglang] ERROR: LOCAL_LLMS_DEFAULT_MODEL must be set for SGLang backend" >&2
    exit 1
fi

export HF_HOME="${DATA_DIR}/sglang/cache"
mkdir -p "$HF_HOME"

echo "[sglang] Starting SGLang OpenAI-compatible server for model: $MODEL_NAME on port $BACKEND_PORT"
echo "[sglang] NOTE: SGLang is experimental and requires GPU + CUDA. Ensure sglang is installed."
exec python3 -m sglang.launch_server \
    --model-path "$MODEL_NAME" \
    --port "$BACKEND_PORT" \
    --host 0.0.0.0
