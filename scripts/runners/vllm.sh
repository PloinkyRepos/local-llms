#!/bin/sh
set -e

BACKEND_PORT="${LOCAL_LLMS_BACKEND_PORT:-8000}"
DATA_DIR="${LOCAL_LLMS_DATA_DIR:-/data/local-llms}"
MODEL_NAME="${LOCAL_LLMS_DEFAULT_MODEL:-}"

if [ -z "$MODEL_NAME" ]; then
    echo "[vllm] ERROR: LOCAL_LLMS_DEFAULT_MODEL must be set for vLLM backend" >&2
    exit 1
fi

export HF_HOME="${DATA_DIR}/vllm/cache"
mkdir -p "$HF_HOME"

echo "[vllm] Starting vLLM OpenAI-compatible server for model: $MODEL_NAME on port $BACKEND_PORT"
echo "[vllm] NOTE: vLLM is experimental and requires GPU + CUDA. Ensure vllm is installed."
exec python3 -m vllm.entrypoints.openai.api_server \
    --model "$MODEL_NAME" \
    --port "$BACKEND_PORT" \
    --host 0.0.0.0
