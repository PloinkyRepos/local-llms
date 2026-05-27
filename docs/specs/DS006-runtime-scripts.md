---
id: DS006
title: Runtime Scripts
status: accepted
owner: repository
summary: Startup orchestration, backend runners, and healthcheck scripts.
---

# DS006 Runtime Scripts

## Introduction

The runtime scripts under `scripts/` handle agent startup orchestration, backend process management, and health probing. They are copied into the Docker image at `/opt/local-llms/scripts` and executed at container start time. This specification defines the behavior and contracts of each script category.

## Core Content

### start-agent.sh

This is the entry point for every agent container, set as the manifest `start` command. Its execution flow is:

1. Read environment variables: `LOCAL_LLMS_AGENT_ID`, `LOCAL_LLMS_BACKEND`, `LOCAL_LLMS_BACKEND_PORT`, `LOCAL_LLMS_DEFAULT_MODEL`, `LOCAL_LLMS_DATA_DIR`, `LOCAL_LLMS_RUNTIME_DIR`, `LOCAL_LLMS_CATALOG_DIR`.
2. Fail immediately if `LOCAL_LLMS_AGENT_ID` is not set.
3. Create per-agent data directories under `$DATA_DIR/agents/$AGENT_ID`.
4. If the agent is `local-llms-manager`, skip all backend startup and exec directly to AgentServer (`/Agent/server/AgentServer.sh`).
5. Run resource checks: parse the RAM band from the catalog, compare the lower bound against `/proc/meminfo`, and fail if insufficient. Check `cpuSafe` and warn (but do not fail) if a non-CPU-safe agent starts without visible NVIDIA GPU hardware.
6. Resolve the runner script path from `$SCRIPTS_DIR/runners/${BACKEND}.sh`, falling back to a hyphenated variant (`tr '_' '-'`).
7. Launch the runner in the background and trap its PID for cleanup.
8. Poll the backend readiness endpoint (from `backends.json`) every 2 seconds for up to 60 attempts (120 seconds). Fail if the backend process exits or readiness times out.
9. For Ollama backends with `LOCAL_LLMS_DEFAULT_MODEL` set, run `ollama pull` followed by `ollama show` to verify the model is available.
10. Exec to AgentServer, replacing the startup process.

The script must fail hard on backend readiness failure or model pull failure. It must never start AgentServer if the backend is not ready, because MCP tool calls would fail silently against an unresponsive backend.

### Backend Runners

Each runner script lives under `scripts/runners/` and is responsible for starting a single backend process. Runners are named after their backend with underscores converted to hyphens (e.g., `transformers-seq2seq.sh` for the `transformers_seq2seq` backend).

**ollama.sh**: Sets Ollama-specific environment variables (`OLLAMA_HOST`, `OLLAMA_MODELS`, `OLLAMA_NUM_PARALLEL`, `OLLAMA_MAX_LOADED_MODELS`, `OLLAMA_KEEP_ALIVE`) from defaults or environment overrides, then execs `ollama serve`.

**llama-cpp.sh**: Reads `LOCAL_LLMS_LLAMA_CPP_MODEL_PATH` or finds the first `.gguf` file in the models directory. Fails if no model is found. Starts `llama-server` with configurable context size and GPU layer count.

**transformers-seq2seq.sh**: Sets HuggingFace cache environment, then execs the Python translation service with the model name and port.

**reranker.sh**: Sets HuggingFace cache environment, then execs the Python reranker service with the model name and port.

**vllm.sh** and **sglang.sh**: Require `LOCAL_LLMS_DEFAULT_MODEL` to be set. Start the respective Python server with the model and port. Both print experimental notices.

**lmstudio-llmster.sh**: Checks for the `llmster` binary and exits with guidance if missing. This is the most defensive runner because LM Studio llmster is not bundled in the base image.

All runners must use `exec` to replace the shell process with the backend process. This ensures that `start-agent.sh` can track the backend PID correctly and that signals propagate to the actual backend process.

### healthcheck.sh

The shared healthcheck script is used by all agent-local `healthcheck.sh` wrappers (which contain a single `exec /opt/local-llms/scripts/healthcheck.sh` line). Its behavior depends on the agent:

- For `local-llms-manager`: probes `http://127.0.0.1:7000/health` (AgentServer).
- For Ollama backends: runs `ollama list` against the backend port.
- For all other backends: probes `http://127.0.0.1:${BACKEND_PORT}/health`.

The script exits 0 on success and nonzero on failure, which Ploinky interprets for readiness state.

## Decisions & Questions

### Question #1: Should the readiness polling timeout be configurable per agent?

Response: Currently hardcoded at 60 attempts x 2 seconds = 120 seconds in `start-agent.sh`. The catalog has `readinessTimeout` per agent, but the startup script does not read it. A future improvement would derive `MAX_TRIES` from the catalog value.

### Question #2: Should runners support graceful shutdown hooks?

Options:
- Add a SIGTERM handler to each runner that cleanly stops the backend before the container terminates.
- Rely on Docker/Podman's default SIGTERM-then-SIGKILL behavior, which is sufficient for the current backends.

## Conclusion

The runtime scripts implement a sequential startup pipeline: resource check, backend launch, readiness polling, optional model pull, then AgentServer handoff. Backend runners are thin wrappers that configure environment and exec the backend process. The healthcheck script routes probes to the correct endpoint based on the agent identity.
