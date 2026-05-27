#!/bin/sh
set -e

BACKEND_PORT="${LOCAL_LLMS_BACKEND_PORT:-8080}"
DATA_DIR="${LOCAL_LLMS_DATA_DIR:-/data/local-llms}"
MODEL_PATH="${LOCAL_LLMS_LLAMA_CPP_MODEL_PATH:-}"
CTX_SIZE="${LOCAL_LLMS_LLAMA_CPP_CTX_SIZE:-4096}"
N_GPU_LAYERS="${LOCAL_LLMS_LLAMA_CPP_GPU_LAYERS:-0}"

MODELS_DIR="${DATA_DIR}/llama-cpp/models"
mkdir -p "$MODELS_DIR"

if [ -z "$MODEL_PATH" ]; then
    MODEL_PATH=$(find "$MODELS_DIR" -name "*.gguf" -type f 2>/dev/null | head -1)
fi

if [ -z "$MODEL_PATH" ]; then
    echo "[llama-cpp] ERROR: No GGUF model found. Set LOCAL_LLMS_LLAMA_CPP_MODEL_PATH or place a .gguf file in $MODELS_DIR" >&2
    exit 1
fi

echo "[llama-cpp] Starting llama.cpp server with model: $MODEL_PATH"
exec llama-server \
    --model "$MODEL_PATH" \
    --port "$BACKEND_PORT" \
    --host 0.0.0.0 \
    --ctx-size "$CTX_SIZE" \
    --n-gpu-layers "$N_GPU_LAYERS"
