#!/bin/sh
set -e

BACKEND_PORT="${LOCAL_LLMS_BACKEND_PORT:-11434}"
DATA_DIR="${LOCAL_LLMS_DATA_DIR:-/data/local-llms}"

export OLLAMA_HOST="${OLLAMA_HOST:-0.0.0.0:${BACKEND_PORT}}"
export OLLAMA_MODELS="${OLLAMA_MODELS:-${DATA_DIR}/ollama/models}"
export OLLAMA_NUM_PARALLEL="${OLLAMA_NUM_PARALLEL:-1}"
export OLLAMA_MAX_LOADED_MODELS="${OLLAMA_MAX_LOADED_MODELS:-1}"
export OLLAMA_KEEP_ALIVE="${OLLAMA_KEEP_ALIVE:-5m}"

mkdir -p "$OLLAMA_MODELS"

echo "[ollama] Starting Ollama server on $OLLAMA_HOST"
exec ollama serve
