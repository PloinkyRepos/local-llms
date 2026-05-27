#!/bin/sh
set -e

TOOL_NAME="${TOOL_NAME:-}"
AGENT_ID="${LOCAL_LLMS_AGENT_ID:-}"
BACKEND="${LOCAL_LLMS_BACKEND:-ollama}"
BACKEND_PORT="${LOCAL_LLMS_BACKEND_PORT:-11434}"
DATA_DIR="${LOCAL_LLMS_DATA_DIR:-/data/local-llms}"
CATALOG_DIR="${LOCAL_LLMS_CATALOG_DIR:-/opt/local-llms/catalog}"
DEFAULT_MODEL="${LOCAL_LLMS_DEFAULT_MODEL:-}"

REGISTRY_FILE="${DATA_DIR}/registry.json"
SCRIPTS_OUTPUT_DIR="${DATA_DIR}/scripts"

if [ -z "$TOOL_NAME" ]; then
    echo '{"error":"TOOL_NAME not set"}' >&2
    exit 1
fi

ensure_registry() {
    if [ ! -f "$REGISTRY_FILE" ]; then
        mkdir -p "$(dirname "$REGISTRY_FILE")"
        echo '{"models":{},"profiles":{},"version":1}' > "$REGISTRY_FILE"
    fi
}

read_input() {
    if [ -t 0 ]; then
        echo '{}'
    else
        cat
    fi
}

json_error() {
    jq -n --arg error "$1" '{error: $error}'
}

is_slug() {
    case "$1" in
        ""|*[!A-Za-z0-9._-]*) return 1 ;;
        *) return 0 ;;
    esac
}

is_model_name() {
    case "$1" in
        ""|*[!A-Za-z0-9._:/+-]*) return 1 ;;
        *) return 0 ;;
    esac
}

resolve_model_backend() {
    requested_model="$1"
    for f in "$CATALOG_DIR"/agents/*.json; do
        [ -f "$f" ] || continue
        resolved="$(jq -r --arg name "$requested_model" '.models[]? | select(.name == $name) | .backend' "$f" 2>/dev/null | head -1)"
        if [ -n "$resolved" ]; then
            echo "$resolved"
            return 0
        fi
    done
    echo ""
}

resolve_backend_model() {
    requested_model="$1"
    requested_backend="$2"
    for f in "$CATALOG_DIR"/agents/*.json; do
        [ -f "$f" ] || continue
        resolved="$(jq -r --arg name "$requested_model" --arg backend "$requested_backend" \
            '.models[]? | select(.name == $name and .backend == $backend) | (.backendModel // .name)' \
            "$f" 2>/dev/null | head -1)"
        if [ -n "$resolved" ]; then
            echo "$resolved"
            return 0
        fi
    done
    echo "$requested_model"
}

normalize_input() {
    jq -c '
        if type != "object" then {}
        elif (.input | type) == "object" then .input
        elif (.arguments | type) == "object" then .arguments
        elif (((.params // {}) | .arguments) | type) == "object" then .params.arguments
        elif (((.params // {}) | .input) | type) == "object" then .params.input
        else .
        end
    ' 2>/dev/null || echo '{}'
}

RAW_INPUT=$(read_input)
INPUT=$(printf '%s' "$RAW_INPUT" | normalize_input)

case "$TOOL_NAME" in
    list_available_models)
        ensure_registry
        AGENT_FILTER=$(echo "$INPUT" | jq -r '.agentFilter // empty' 2>/dev/null || true)
        BACKEND_FILTER=$(echo "$INPUT" | jq -r '.backendFilter // empty' 2>/dev/null || true)

        CATALOG_MODELS=$(for f in "$CATALOG_DIR"/agents/*.json; do
            [ -f "$f" ] || continue
            ENTRY_AGENT=$(jq -r '.agentId' "$f" 2>/dev/null)
            if [ -n "$AGENT_FILTER" ] && [ "$ENTRY_AGENT" != "$AGENT_FILTER" ]; then
                continue
            fi
            MODELS=$(jq -c '.models[]' "$f" 2>/dev/null || true)
            echo "$MODELS" | while IFS= read -r model; do
                [ -z "$model" ] && continue
                MODEL_BACKEND=$(echo "$model" | jq -r '.backend' 2>/dev/null)
                if [ -n "$BACKEND_FILTER" ] && [ "$MODEL_BACKEND" != "$BACKEND_FILTER" ]; then
                    continue
                fi
                echo "$model" | jq -c ". + {\"agentId\": \"$ENTRY_AGENT\"}"
            done
        done | jq -s '.')

        REGISTRY_MODELS=$(jq -c '.models // {} | to_entries[] | {name: .key, source: "registry"} + .value' "$REGISTRY_FILE" 2>/dev/null | jq -s '.')
        jq -n --argjson catalog "$CATALOG_MODELS" --argjson registry "$REGISTRY_MODELS" \
            '{catalog: $catalog, registry: $registry}'
        ;;

    register_model)
        ensure_registry
        MODEL_NAME=$(echo "$INPUT" | jq -r '.modelName // empty')
        REG_BACKEND=$(echo "$INPUT" | jq -r '.backend // empty')
        REG_AGENT=$(echo "$INPUT" | jq -r '.agentId // empty')
        REG_TASK_API=$(echo "$INPUT" | jq -r '.taskApi // "chat"')
        REG_PARAMS=$(echo "$INPUT" | jq -c '.parameters // {}')
        [ -z "$REG_BACKEND" ] && REG_BACKEND="$BACKEND"
        [ -z "$REG_AGENT" ] && REG_AGENT="$AGENT_ID"

        if [ -z "$MODEL_NAME" ] || [ -z "$REG_BACKEND" ] || [ -z "$REG_AGENT" ]; then
            json_error "modelName, backend, and agentId are required"
            exit 1
        fi
        is_model_name "$MODEL_NAME" || { json_error "modelName contains unsupported characters"; exit 1; }
        is_slug "$REG_BACKEND" || { json_error "backend must be a slug"; exit 1; }
        is_slug "$REG_AGENT" || { json_error "agentId must be a slug"; exit 1; }

        jq --arg name "$MODEL_NAME" \
           --arg backend "$REG_BACKEND" \
           --arg agent "$REG_AGENT" \
           --arg taskApi "$REG_TASK_API" \
           --argjson params "$REG_PARAMS" \
           '.models[$name] = {"backend": $backend, "agentId": $agent, "taskApi": $taskApi, "parameters": $params}' \
           "$REGISTRY_FILE" > "${REGISTRY_FILE}.tmp" && mv "${REGISTRY_FILE}.tmp" "$REGISTRY_FILE"

        jq -n --arg registered "$MODEL_NAME" --arg backend "$REG_BACKEND" --arg agentId "$REG_AGENT" \
            '{registered: $registered, backend: $backend, agentId: $agentId}'
        ;;

    generate_startup_script)
        ensure_registry
        PROFILE_ID=$(echo "$INPUT" | jq -r '.profileId // empty')
        GEN_AGENT=$(echo "$INPUT" | jq -r '.agentId // empty')
        GEN_MODEL=$(echo "$INPUT" | jq -r '.modelName // empty')
        GEN_BACKEND=$(echo "$INPUT" | jq -r '.backend // empty')

        if [ -z "$PROFILE_ID" ] || [ -z "$GEN_AGENT" ] || [ -z "$GEN_MODEL" ]; then
            json_error "profileId, agentId, and modelName are required"
            exit 1
        fi

        if [ -z "$GEN_BACKEND" ]; then
            GEN_BACKEND="$(resolve_model_backend "$GEN_MODEL")"
        fi
        [ -z "$GEN_BACKEND" ] && GEN_BACKEND="ollama"
        is_slug "$PROFILE_ID" || { json_error "profileId must be a slug"; exit 1; }
        is_slug "$GEN_AGENT" || { json_error "agentId must be a slug"; exit 1; }
        is_slug "$GEN_BACKEND" || { json_error "backend must be a slug"; exit 1; }
        is_model_name "$GEN_MODEL" || { json_error "modelName contains unsupported characters"; exit 1; }
        GEN_RUNTIME_MODEL="$(resolve_backend_model "$GEN_MODEL" "$GEN_BACKEND")"
        is_model_name "$GEN_RUNTIME_MODEL" || { json_error "backendModel contains unsupported characters"; exit 1; }

        mkdir -p "$SCRIPTS_OUTPUT_DIR"
        BASE_SCRIPT_DIR=$(cd "$SCRIPTS_OUTPUT_DIR" && pwd -P)
        SCRIPT_DIR="${BASE_SCRIPT_DIR}/${PROFILE_ID}"
        mkdir -p "$SCRIPT_DIR"
        SCRIPT_REAL_DIR=$(cd "$SCRIPT_DIR" && pwd -P)
        case "$SCRIPT_REAL_DIR" in
            "$BASE_SCRIPT_DIR"/*) ;;
            *) json_error "generated script path escaped scripts directory"; exit 1 ;;
        esac

        cat > "${SCRIPT_DIR}/start.sh" << SCRIPT_EOF
#!/bin/sh
export LOCAL_LLMS_AGENT_ID="$GEN_AGENT"
export LOCAL_LLMS_DEFAULT_MODEL="$GEN_RUNTIME_MODEL"
export LOCAL_LLMS_BACKEND="$GEN_BACKEND"
exec /opt/local-llms/scripts/start-agent.sh
SCRIPT_EOF
        chmod +x "${SCRIPT_DIR}/start.sh"
        jq -n --arg generated "${SCRIPT_DIR}/start.sh" \
            --arg profileId "$PROFILE_ID" \
            --arg requestedModel "$GEN_MODEL" \
            --arg runtimeModel "$GEN_RUNTIME_MODEL" \
            --arg backend "$GEN_BACKEND" \
            '{generated: $generated, profileId: $profileId, requestedModel: $requestedModel, runtimeModel: $runtimeModel, backend: $backend}'
        ;;

    register_agent_profile)
        ensure_registry
        PROFILE_ID=$(echo "$INPUT" | jq -r '.profileId // empty')
        PROF_AGENT=$(echo "$INPUT" | jq -r '.agentId // empty')
        PROF_MODELS=$(echo "$INPUT" | jq -c '.models // []')
        PROF_DEFAULT=$(echo "$INPUT" | jq -r '.defaultModel // empty')
        PROF_BACKEND=$(echo "$INPUT" | jq -r '.backend // "ollama"')

        if [ -z "$PROFILE_ID" ] || [ -z "$PROF_AGENT" ] || [ -z "$PROF_DEFAULT" ]; then
            json_error "profileId, agentId, and defaultModel are required"
            exit 1
        fi
        is_slug "$PROFILE_ID" || { json_error "profileId must be a slug"; exit 1; }
        is_slug "$PROF_AGENT" || { json_error "agentId must be a slug"; exit 1; }
        is_slug "$PROF_BACKEND" || { json_error "backend must be a slug"; exit 1; }
        is_model_name "$PROF_DEFAULT" || { json_error "defaultModel contains unsupported characters"; exit 1; }

        jq --arg id "$PROFILE_ID" \
           --arg agent "$PROF_AGENT" \
           --argjson models "$PROF_MODELS" \
           --arg dflt "$PROF_DEFAULT" \
           --arg backend "$PROF_BACKEND" \
           '.profiles[$id] = {"agentId": $agent, "models": $models, "defaultModel": $dflt, "backend": $backend, "promoted": false}' \
           "$REGISTRY_FILE" > "${REGISTRY_FILE}.tmp" && mv "${REGISTRY_FILE}.tmp" "$REGISTRY_FILE"

        jq -n --arg registered "$PROFILE_ID" --arg agentId "$PROF_AGENT" \
            '{registered: $registered, agentId: $agentId}'
        ;;

    promote_agent_profile)
        ensure_registry
        PROFILE_ID=$(echo "$INPUT" | jq -r '.profileId // empty')

        if [ -z "$PROFILE_ID" ]; then
            json_error "profileId is required"
            exit 1
        fi
        is_slug "$PROFILE_ID" || { json_error "profileId must be a slug"; exit 1; }

        PROFILE_DATA=$(jq -c --arg id "$PROFILE_ID" '.profiles[$id] // null' "$REGISTRY_FILE")
        if [ "$PROFILE_DATA" = "null" ]; then
            json_error "profile '$PROFILE_ID' not found"
            exit 1
        fi

        jq -n --arg profileId "$PROFILE_ID" \
            '{status: "promotion_prepared", profileId: $profileId, note: "Promoted profiles require Ploinky restart. Generate agent directory manually or via manager tooling."}'
        ;;

    status_model)
        MODEL_QUERY=$(echo "$INPUT" | jq -r '.modelName // empty')
        AGENT_QUERY=$(echo "$INPUT" | jq -r '.agentId // empty')

        STATUS_BACKEND="unknown"
        STATUS_MODEL="none"

        case "$BACKEND" in
            ollama)
                if OLLAMA_HOST="127.0.0.1:${BACKEND_PORT}" ollama list >/dev/null 2>&1; then
                    STATUS_BACKEND="running"
                    LOADED=$(OLLAMA_HOST="127.0.0.1:${BACKEND_PORT}" ollama ps 2>/dev/null | tail -n +2 | awk '{print $1}' | head -1)
                    STATUS_MODEL="${LOADED:-none}"
                else
                    STATUS_BACKEND="stopped"
                fi
                ;;
            *)
                if curl -sf "http://127.0.0.1:${BACKEND_PORT}/health" >/dev/null 2>&1; then
                    STATUS_BACKEND="running"
                    HEALTH_RESP=$(curl -sf "http://127.0.0.1:${BACKEND_PORT}/health" 2>/dev/null || echo '{}')
                    STATUS_MODEL=$(echo "$HEALTH_RESP" | jq -r '.model // "unknown"' 2>/dev/null || echo "unknown")
                else
                    STATUS_BACKEND="stopped"
                fi
                ;;
        esac

        jq -n --arg backend "$STATUS_BACKEND" \
              --arg model "$STATUS_MODEL" \
              --arg agentId "${AGENT_QUERY:-$AGENT_ID}" \
              --arg backendType "$BACKEND" \
              '{"backend_status": $backend, "loaded_model": $model, "agent_id": $agentId, "backend_type": $backendType}'
        ;;

    start_model)
        MODEL_NAME=$(echo "$INPUT" | jq -r '.modelName // empty')
        [ -z "$MODEL_NAME" ] && MODEL_NAME="$DEFAULT_MODEL"

        if [ -z "$MODEL_NAME" ]; then
            json_error "modelName is required (or set LOCAL_LLMS_DEFAULT_MODEL)"
            exit 1
        fi
        is_model_name "$MODEL_NAME" || { json_error "modelName contains unsupported characters"; exit 1; }
        RUNTIME_MODEL="$(resolve_backend_model "$MODEL_NAME" "$BACKEND")"
        is_model_name "$RUNTIME_MODEL" || { json_error "backendModel contains unsupported characters"; exit 1; }

        case "$BACKEND" in
            ollama)
                OLLAMA_HOST="127.0.0.1:${BACKEND_PORT}" ollama pull "$RUNTIME_MODEL" >/dev/null
                jq -n --arg started "$MODEL_NAME" --arg runtimeModel "$RUNTIME_MODEL" \
                    '{started: $started, runtimeModel: $runtimeModel, backend: "ollama"}'
                ;;
            transformers_seq2seq|transformers-seq2seq)
                jq -n --arg model "$MODEL_NAME" --arg runtimeModel "$RUNTIME_MODEL" \
                    '{note: "Seq2seq models are loaded at service startup. Restart the agent to switch models.", model: $model, runtimeModel: $runtimeModel}'
                ;;
            reranker)
                jq -n --arg model "$MODEL_NAME" --arg runtimeModel "$RUNTIME_MODEL" \
                    '{note: "Reranker models are loaded at service startup. Restart the agent to switch models.", model: $model, runtimeModel: $runtimeModel}'
                ;;
            *)
                jq -n --arg backend "$BACKEND" --arg model "$MODEL_NAME" --arg runtimeModel "$RUNTIME_MODEL" \
                    '{note: ("Start model for backend " + $backend + " by restarting the agent with LOCAL_LLMS_DEFAULT_MODEL set."), model: $model, runtimeModel: $runtimeModel}'
                ;;
        esac
        ;;

    stop_model)
        MODEL_NAME=$(echo "$INPUT" | jq -r '.modelName // empty')

        case "$BACKEND" in
            ollama)
                if [ -n "$MODEL_NAME" ]; then
                    is_model_name "$MODEL_NAME" || { json_error "modelName contains unsupported characters"; exit 1; }
                    RUNTIME_MODEL="$(resolve_backend_model "$MODEL_NAME" "$BACKEND")"
                    is_model_name "$RUNTIME_MODEL" || { json_error "backendModel contains unsupported characters"; exit 1; }
                    OLLAMA_HOST="127.0.0.1:${BACKEND_PORT}" ollama stop "$RUNTIME_MODEL" >/dev/null 2>&1 || true
                    jq -n --arg stopped "$MODEL_NAME" --arg runtimeModel "$RUNTIME_MODEL" \
                        '{stopped: $stopped, runtimeModel: $runtimeModel}'
                else
                    jq -n '{note: "Specify modelName to stop a specific Ollama model, or stop the agent to stop all models."}'
                fi
                ;;
            *)
                jq -n '{note: "Stop the agent to stop the model backend."}'
                ;;
        esac
        ;;

    translate)
        TEXT=$(echo "$INPUT" | jq -r '.text // empty')
        SOURCE_LANG=$(echo "$INPUT" | jq -r '.sourceLang // empty')
        TARGET_LANG=$(echo "$INPUT" | jq -r '.targetLang // empty')

        if [ -z "$TEXT" ] || [ -z "$TARGET_LANG" ]; then
            json_error "text and targetLang are required"
            exit 1
        fi

        PAYLOAD=$(jq -n --arg text "$TEXT" --arg src "$SOURCE_LANG" --arg tgt "$TARGET_LANG" \
            '{text: $text, source_lang: $src, target_lang: $tgt}')

        curl -sf -X POST "http://127.0.0.1:${BACKEND_PORT}/translate" \
            -H "Content-Type: application/json" \
            -d "$PAYLOAD"
        ;;

    rerank)
        QUERY=$(echo "$INPUT" | jq -r '.query // empty')
        PASSAGES=$(echo "$INPUT" | jq -c '.passages // []')
        TOP_K=$(echo "$INPUT" | jq -r '.topK // empty')
        INSTRUCTION=$(echo "$INPUT" | jq -r '.instruction // empty')

        if [ -z "$QUERY" ]; then
            json_error "query is required"
            exit 1
        fi

        PAYLOAD=$(jq -n --arg q "$QUERY" --argjson p "$PASSAGES" --arg k "$TOP_K" --arg inst "$INSTRUCTION" \
            '{query: $q, passages: $p} | if ($k | length) > 0 then . + {top_k: ($k | tonumber)} else . end | if ($inst | length) > 0 then . + {instruction: $inst} else . end')

        curl -sf -X POST "http://127.0.0.1:${BACKEND_PORT}/rerank" \
            -H "Content-Type: application/json" \
            -d "$PAYLOAD"
        ;;

    *)
        json_error "Unknown tool: $TOOL_NAME"
        exit 1
        ;;
esac
