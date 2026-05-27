---
id: DS008
title: Model Lifecycle
status: accepted
owner: repository
summary: Model discovery, registration, download, start, stop, and backendModel alias resolution.
---

# DS008 Model Lifecycle

## Introduction

Models in the local-llms system move through a lifecycle that spans discovery, registration, download, startup, and shutdown. This specification defines the lifecycle stages, the tools that drive transitions, and the relationship between catalog entries, registry entries, and runtime state.

## Core Content

### Discovery

Model discovery happens through the `list_available_models` MCP tool. This tool merges two sources: the static catalog (JSON files under `catalog/agents/`) and the dynamic registry (`registry.json` under the data directory). Catalog models are read-only and versioned with the repository. Registry models are operator-created and persist across agent restarts through the shared volume.

The tool supports `agentFilter` and `backendFilter` parameters for scoping results. When called from a model agent, the agent's own `LOCAL_LLMS_AGENT_ID` is available for implicit filtering.

### Registration

The `register_model` tool writes a model entry to the registry. Registration records metadata only — it does not download weights or start a backend. The entry includes the model name, backend, agent assignment, task API type, and optional parameters. If `backend` and `agentId` are not provided, the dispatcher defaults them from the current agent's environment.

Registration is idempotent: re-registering the same model name overwrites the previous entry. The registry write is atomic (write to `.tmp`, then `mv`).

### BackendModel Resolution

When a user-facing model name differs from the backend-specific identifier, the catalog provides a `backendModel` field. The dispatcher's `resolve_backend_model` function searches all agent catalog files for a model entry matching the requested name and backend, then returns the `backendModel` value (or the original name if no alias exists).

For example, `google/translategemma-4b-it` resolves to `translategemma:4b` for the Ollama backend. This resolution happens in `start_model` and `generate_startup_script`, ensuring that the correct backend identifier reaches Ollama or other servers.

### Download

Model weight download is never implicit for the user but is built into the startup flow:

- **Ollama models**: Downloaded by `ollama pull` during either `start-agent.sh` (for the default model at first start) or the `start_model` MCP tool (for on-demand model additions). Ollama manages its own model cache under `/data/local-llms/ollama/models`.
- **HuggingFace models** (seq2seq, rerankers): Downloaded by the HuggingFace `transformers` or `sentence-transformers` library at service startup. The cache directory is set via `TRANSFORMERS_CACHE` and `HF_HOME` environment variables pointing to `/data/local-llms/transformers/cache`.
- **llama.cpp models**: Must be pre-placed in `/data/local-llms/llama-cpp/models/` as `.gguf` files. There is no automatic download mechanism; the runner fails with an error if no model file is found.

All model storage paths are under `/data/local-llms/`, which is volume-mounted from the host. This prevents model re-downloads across container restarts.

### Start

The `start_model` tool has backend-specific behavior:

- **Ollama**: Runs `ollama pull` for the resolved runtime model, then returns success. Ollama's lazy loading means the model becomes available for inference after the pull completes.
- **Seq2seq and reranker**: Returns a note indicating that the model is loaded at service startup and requires an agent restart to switch models. These Python services load their model once at startup and do not support hot-swapping.
- **Other backends**: Returns a note to restart the agent with `LOCAL_LLMS_DEFAULT_MODEL` set to the desired model.

### Stop

The `stop_model` tool is meaningful primarily for Ollama, where it runs `ollama stop` to unload a specific model from memory. For other backends, stopping requires stopping the entire agent.

### Status

The `status_model` tool probes the backend to determine whether it is running and which model is loaded. For Ollama, it uses `ollama list` and `ollama ps`. For other backends, it probes the `/health` endpoint and reads the model name from the response.

### Profile Lifecycle

The manager additionally supports `register_agent_profile` and `promote_agent_profile`. A profile groups an agent identity, a set of models, a default model, and a backend into a named configuration. Registered profiles are stored in `registry.json` with `promoted: false`. Promotion marks the profile as ready for first-class agent directory creation, which is a manual operator step requiring a Ploinky restart.

The `generate_startup_script` tool creates a `start.sh` for a profile under `$DATA_DIR/scripts/<profileId>/`. This script sets the required environment variables and delegates to `start-agent.sh`, allowing operators to test profiles without creating a full agent directory.

## Decisions & Questions

### Question #1: Should a `pull_model` tool be added for explicit weight download?

Response: The current design combines download with `start_model` for Ollama and with service startup for Python backends. A separate `pull_model` tool would let operators pre-download weights without starting inference. This is useful for air-gapped or scheduled-download scenarios. Deferred until operator feedback indicates demand.

### Question #2: Should profiles support a dry-run mode?

Options:
- Add a `--dry-run` or `dryRun: true` parameter to `generate_startup_script` that validates the configuration without writing files.
- Keep the current behavior where generated scripts are always written but can be inspected before use.

## Conclusion

The model lifecycle spans discovery (catalog + registry), registration (metadata-only), download (Ollama pull or HuggingFace cache), start (backend-specific), stop (Ollama unload or agent restart), and status probing. BackendModel alias resolution bridges user-facing identifiers to backend-specific names throughout the lifecycle.
