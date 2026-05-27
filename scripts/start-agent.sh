#!/bin/sh
set -e

AGENT_ID="${LOCAL_LLMS_AGENT_ID:-}"
BACKEND="${LOCAL_LLMS_BACKEND:-ollama}"
BACKEND_PORT="${LOCAL_LLMS_BACKEND_PORT:-11434}"
DEFAULT_MODEL="${LOCAL_LLMS_DEFAULT_MODEL:-}"
DATA_DIR="${LOCAL_LLMS_DATA_DIR:-/data/local-llms}"
RUNTIME_DIR="${LOCAL_LLMS_RUNTIME_DIR:-/opt/local-llms}"
CATALOG_DIR="${LOCAL_LLMS_CATALOG_DIR:-${RUNTIME_DIR}/catalog}"
SCRIPTS_DIR="${RUNTIME_DIR}/scripts"

if [ -z "$AGENT_ID" ]; then
    echo "[start-agent] ERROR: LOCAL_LLMS_AGENT_ID is not set" >&2
    exit 1
fi

echo "[start-agent] Starting agent: $AGENT_ID (backend=$BACKEND, model=$DEFAULT_MODEL)"

mkdir -p "$DATA_DIR/agents/$AGENT_ID"
mkdir -p "$DATA_DIR/ollama/models"
mkdir -p "$DATA_DIR/llama-cpp/models"
mkdir -p "$DATA_DIR/transformers/cache"
mkdir -p "$DATA_DIR/scripts"

fail() {
    echo "[start-agent] ERROR: $*" >&2
    exit 1
}

cleanup_backend() {
    if [ -n "${BACKEND_PID:-}" ] && kill -0 "$BACKEND_PID" >/dev/null 2>&1; then
        kill "$BACKEND_PID" >/dev/null 2>&1 || true
    fi
}

parse_min_ram_gb() {
    ram_band="$(jq -r --arg agent "$AGENT_ID" '.ramBand // empty' "$CATALOG_DIR/agents/$AGENT_ID.json" 2>/dev/null || true)"
    echo "$ram_band" | sed -n 's/^[^0-9]*\([0-9][0-9]*\).*$/\1/p'
}

check_resources() {
    [ -f "$CATALOG_DIR/agents/$AGENT_ID.json" ] || return 0
    min_ram_gb="$(parse_min_ram_gb)"
    [ -n "$min_ram_gb" ] || return 0
    mem_kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    [ "$mem_kb" -gt 0 ] || return 0
    available_gb=$((mem_kb / 1024 / 1024))
    if [ "$available_gb" -lt "$min_ram_gb" ]; then
        fail "agent '$AGENT_ID' requires approximately ${min_ram_gb}GB RAM (${available_gb}GB detected). Choose a lighter profile/model or increase container memory."
    fi
    cpu_safe="$(jq -r '.cpuSafe // true' "$CATALOG_DIR/agents/$AGENT_ID.json" 2>/dev/null || echo true)"
    if [ "$cpu_safe" != "true" ] && ! command -v nvidia-smi >/dev/null 2>&1 && [ ! -e /dev/nvidia0 ]; then
        echo "[start-agent] WARNING: agent '$AGENT_ID' is marked cpuSafe=false and no NVIDIA GPU signal was detected. Startup will continue only because Ploinky v1 does not model GPU passthrough." >&2
    fi
}

if [ "$AGENT_ID" = "local-llms-manager" ]; then
    echo "[start-agent] Manager mode — skipping backend startup"
    exec /Agent/server/AgentServer.sh
fi

check_resources

RUNNER_SCRIPT="$SCRIPTS_DIR/runners/${BACKEND}.sh"
if [ ! -f "$RUNNER_SCRIPT" ]; then
    RUNNER_SCRIPT="$SCRIPTS_DIR/runners/$(echo "$BACKEND" | tr '_' '-').sh"
fi

if [ ! -f "$RUNNER_SCRIPT" ]; then
    fail "No runner script found for backend '$BACKEND'"
fi

echo "[start-agent] Launching backend with $RUNNER_SCRIPT"
sh "$RUNNER_SCRIPT" &
BACKEND_PID=$!
trap cleanup_backend EXIT INT TERM

echo "[start-agent] Waiting for backend readiness on port $BACKEND_PORT..."
PROBE_PATH="$(jq -r --arg backend "$BACKEND" '.backends[$backend].readinessProbe.path // empty' "$CATALOG_DIR/backends.json" 2>/dev/null || true)"
[ -n "$PROBE_PATH" ] || PROBE_PATH="/health"
TRIES=0
MAX_TRIES=60
while [ $TRIES -lt $MAX_TRIES ]; do
    if ! kill -0 "$BACKEND_PID" >/dev/null 2>&1; then
        fail "backend process for '$BACKEND' exited before becoming ready"
    fi
    if curl -sf "http://127.0.0.1:${BACKEND_PORT}${PROBE_PATH}" >/dev/null 2>&1; then
        echo "[start-agent] Backend ready on port $BACKEND_PORT"
        break
    fi
    TRIES=$((TRIES + 1))
    sleep 2
done

if [ $TRIES -ge $MAX_TRIES ]; then
    fail "backend did not become ready within $((MAX_TRIES * 2))s"
fi

if [ -n "$DEFAULT_MODEL" ] && [ "$BACKEND" = "ollama" ]; then
    echo "[start-agent] Pulling default model: $DEFAULT_MODEL"
    OLLAMA_HOST="127.0.0.1:${BACKEND_PORT}" ollama pull "$DEFAULT_MODEL" >/dev/null || \
        fail "model pull failed for '$DEFAULT_MODEL'"
    OLLAMA_HOST="127.0.0.1:${BACKEND_PORT}" ollama show "$DEFAULT_MODEL" >/dev/null || \
        fail "default model '$DEFAULT_MODEL' is not available after pull"
fi

echo "[start-agent] Starting AgentServer"
trap - EXIT INT TERM
exec /Agent/server/AgentServer.sh
