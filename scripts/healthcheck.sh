#!/bin/sh
BACKEND_PORT="${LOCAL_LLMS_BACKEND_PORT:-11434}"
BACKEND="${LOCAL_LLMS_BACKEND:-ollama}"
AGENT_ID="${LOCAL_LLMS_AGENT_ID:-}"

if [ "$AGENT_ID" = "local-llms-manager" ]; then
    curl -sf http://127.0.0.1:7000/health >/dev/null 2>&1
    exit $?
fi

case "$BACKEND" in
    ollama)
        OLLAMA_HOST="127.0.0.1:${BACKEND_PORT}" ollama list >/dev/null 2>&1
        ;;
    llama_cpp|llama-cpp)
        curl -sf "http://127.0.0.1:${BACKEND_PORT}/health" >/dev/null 2>&1
        ;;
    transformers_seq2seq|transformers-seq2seq|reranker)
        curl -sf "http://127.0.0.1:${BACKEND_PORT}/health" >/dev/null 2>&1
        ;;
    vllm|sglang)
        curl -sf "http://127.0.0.1:${BACKEND_PORT}/health" >/dev/null 2>&1
        ;;
    *)
        curl -sf "http://127.0.0.1:${BACKEND_PORT}/health" >/dev/null 2>&1
        ;;
esac
