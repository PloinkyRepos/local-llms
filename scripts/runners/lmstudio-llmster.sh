#!/bin/sh
set -e

BACKEND_PORT="${LOCAL_LLMS_BACKEND_PORT:-1234}"
DATA_DIR="${LOCAL_LLMS_DATA_DIR:-/data/local-llms}"

echo "[lmstudio-llmster] EXPERIMENTAL: LM Studio llmster headless daemon"
echo "[lmstudio-llmster] This runner requires the llmster binary or Docker image."
echo "[lmstudio-llmster] LM Studio llmster is NOT a default v1 dependency."

MODELS_DIR="${DATA_DIR}/lmstudio/models"
mkdir -p "$MODELS_DIR"

if ! command -v llmster >/dev/null 2>&1; then
    echo "[lmstudio-llmster] ERROR: llmster binary not found. Install LM Studio headless daemon first." >&2
    echo "[lmstudio-llmster] See https://lmstudio.ai/docs/developer/core/headless" >&2
    exit 1
fi

echo "[lmstudio-llmster] Starting llmster on port $BACKEND_PORT"
exec llmster start --port "$BACKEND_PORT"
