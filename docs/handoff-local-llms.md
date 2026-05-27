# local-llms Handoff

This document is the compact project handoff for a new Claude Code session. It replaces the earlier planning, review, and prompt documents that were used during implementation.

## Repository Policy

Read `CLAUDE.md` first. `AGENTS.md` only points to it.

Important Git policy:
- Do not create branches with a `codex/` prefix.
- Do not add Codex, Claude, or other AI assistant co-author trailers to commits.
- Keep commit metadata human-authored unless the user explicitly asks for different attribution.

## Original Request

Build `local-llms` as a Ploinky repository containing multiple Ploinky agents. Each agent should be an MCP server for a local-LLM role from the requested table:

- `language-translation`
- `relevance`
- `function-selection`
- `function-invocation`
- `tool-composition-local`
- `base-local`
- `local`
- `planning-local`
- `validated-planning-local`
- `adaptive-local`
- `coding-local`

The repo should also include `local-llms-manager` as the orchestration/management agent. All agents use the same base Docker image, `assistos/local-llms`, and expose MCP tools for model discovery, model registration, startup script generation, start/stop/status, translation, and reranking where applicable.

## Review Findings That Shaped The Implementation

The implementation plan was revised after review. The key valid findings were:

- Not all requested models are runnable through Ollama, llama.cpp, or LM Studio. Translation seq2seq models and rerankers need Python-backed services.
- LM Studio headless support should not be a default v1 dependency. It is represented as experimental through `lmstudio_llmster`.
- GPU passthrough is not modeled in the current Ploinky manifest contract. Larger agents need operator-level runtime flags outside the manifest.
- Model download behavior must be explicit because cold pulls are slow and large.
- Ploinky readiness and port declarations need to account for both AgentServer and the backend service.
- RAM bands need at least startup-time checks because Ploinky manifests do not enforce container memory limits.
- Each agent needs its own `mcp-config.json`; tools can call shared scripts but the config files must be per-agent.
- Health scripts must be local script names from the agent directory, while shared implementation lives in the image.
- Agents using `manifest.start` still need a `package.json` marker so Ploinky prepares AgentServer dependencies.

## Architecture

### Shared Docker Image

`Dockerfile` builds one image for every agent:

- Base: `node:24-slim`
- Installs `curl`, `git`, `jq`, `procps`, Python 3, build tools, and CMake.
- Creates `/opt/local-llms-venv`.
- Installs CPU PyTorch from the PyTorch CPU index, then installs normal Python packages from PyPI:
  - `transformers`
  - `sentencepiece`
  - `protobuf`
  - `sentence-transformers`
  - `flask`
  - `gunicorn`
- Installs Ollama.
- Builds and installs `llama-server` from `ggml-org/llama.cpp`.
- Copies shared scripts to `/opt/local-llms/scripts`.
- Copies the catalog to `/opt/local-llms/catalog`.
- Uses `/data/local-llms/...` as the shared model/runtime root.

Important path decision: Ploinky mounts each agent directory at `/code`, so shared scripts and catalog cannot live under `/code`. They live under `/opt/local-llms` inside the image.

### Agent Directories

There are 12 agent directories:

- `local-llms-manager`
- `language-translation`
- `relevance`
- `function-selection`
- `function-invocation`
- `tool-composition-local`
- `base-local`
- `local`
- `planning-local`
- `validated-planning-local`
- `adaptive-local`
- `coding-local`

Every agent directory has:

- `manifest.json`
- `mcp-config.json`
- `package.json`

Every backend-serving model agent also has:

- `healthcheck.sh`

The `package.json` files are dependency markers. They are intentionally minimal; their purpose is to make Ploinky prepare the AgentServer dependency cache even though the manifest uses `start`.

### Manifests

All manifests use:

- `container`: `assistos/local-llms:latest`
- `start`: `/opt/local-llms/scripts/start-agent.sh`
- default profile env:
  - `LOCAL_LLMS_AGENT_ID`
  - `LOCAL_LLMS_BACKEND`
  - `LOCAL_LLMS_BACKEND_PORT`
  - `LOCAL_LLMS_DEFAULT_MODEL`
  - `LOCAL_LLMS_DATA_DIR=/data/local-llms`
  - `LOCAL_LLMS_CATALOG_DIR=/opt/local-llms/catalog`
- volume:
  - `.ploinky/data/local-llms` -> `/data/local-llms`

Model-serving agents declare two ports in order:

- AgentServer internal `7000`
- Backend service port, such as `11434`, `8090`, or `8091`

Readiness scripts are declared as `healthcheck.sh`, not an absolute path, because Ploinky validates readiness script names. Each agent-local wrapper delegates to `/opt/local-llms/scripts/healthcheck.sh`.

### Default Startup

`local-llms-manager` is the management agent. Its manifest enables:

- `function-selection` with `no-wait`
- `function-invocation` with `no-wait`

This keeps the manager responsive while model backends load or pull in the background.

### Catalog

The catalog is under `catalog/`:

- `catalog/backends.json`
- `catalog/agents/*.json`
- `catalog/schemas/backends.schema.json`
- `catalog/schemas/agent.schema.json`

Backends:

- `ollama`
- `llama_cpp`
- `transformers_seq2seq`
- `reranker`
- `vllm` experimental
- `sglang` experimental
- `lmstudio_llmster` experimental

Model routing decisions:

- `facebook/m2m100_418M` -> `transformers_seq2seq`
- `google/madlad400-3b-mt` -> `transformers_seq2seq`
- `Qwen/Qwen3-Reranker-0.6B` -> `reranker`
- `utter-project/EuroLLM-1.7B-Instruct` -> `vllm`
- `google/translategemma-4b-it` keeps the requested model ID but maps to `backendModel: translategemma:4b` for Ollama.
- Chat/function/coding model candidates are cataloged primarily as Ollama model IDs, matching the requested table.

`backendModel` exists so a user-facing model ID can differ from the backend-specific runnable ID.

### Runtime Scripts

Shared scripts live under `scripts/` and are copied into the image.

Core scripts:

- `scripts/start-agent.sh`
- `scripts/dispatcher.sh`
- `scripts/healthcheck.sh`

Runner scripts:

- `scripts/runners/ollama.sh`
- `scripts/runners/llama-cpp.sh`
- `scripts/runners/transformers-seq2seq.sh`
- `scripts/runners/reranker.sh`
- `scripts/runners/vllm.sh`
- `scripts/runners/sglang.sh`
- `scripts/runners/lmstudio-llmster.sh`

Python services:

- `scripts/services/translation_service.py`
- `scripts/services/reranker_service.py`

### Startup Behavior

`start-agent.sh`:

- Reads agent/backend/model env.
- Skips backend startup for `local-llms-manager`.
- Checks the catalog RAM band against `/proc/meminfo`.
- Warns when `cpuSafe=false` and no NVIDIA GPU signal is visible.
- Starts the selected backend runner from `/opt/local-llms/scripts/runners`.
- Waits for backend readiness using the catalog readiness path.
- Fails hard if the backend exits or readiness times out.
- Pulls and validates the default Ollama model when `LOCAL_LLMS_DEFAULT_MODEL` is set for `ollama`.
- Starts `/Agent/server/AgentServer.sh` only after backend readiness succeeds.

### MCP Dispatcher

`dispatcher.sh` is called by every `mcp-config.json`.

Important behavior:

- Unwraps AgentServer envelopes:
  - `.input`
  - `.arguments`
  - `.params.arguments`
  - `.params.input`
- Produces JSON-only responses.
- Defaults model-agent `register_model` calls to the current `LOCAL_LLMS_AGENT_ID` and `LOCAL_LLMS_BACKEND`.
- Validates slugs and model IDs.
- Prevents generated startup script path traversal.
- Resolves catalog `backendModel` aliases.
- Writes dynamic registry state under `/data/local-llms/registry.json`.
- Writes generated startup scripts under `/data/local-llms/scripts/<profile-id>/start.sh`.

Manager tools:

- `list_available_models`
- `register_model`
- `generate_startup_script`
- `register_agent_profile`
- `promote_agent_profile`
- `status_model`

Model-agent tools:

- `list_available_models`
- `start_model`
- `stop_model`
- `status_model`
- `register_model`

Specialized tools:

- `language-translation`: `translate`
- `relevance`: `rerank`

### Python Services

`translation_service.py`:

- Uses `transformers` seq2seq pipeline.
- Loads the model at startup.
- `/health` returns `503` until the model is loaded.
- Startup exits nonzero if preload fails.

`reranker_service.py`:

- Uses `sentence_transformers.CrossEncoder`, not `AutoModelForSequenceClassification`.
- Loads `Qwen/Qwen3-Reranker-0.6B` by default.
- `/health` returns `503` until the model is loaded.
- Startup exits nonzero if preload fails.

## Storage Layout

All agents share `.ploinky/data/local-llms`:

```text
.ploinky/data/local-llms/
├── registry.json
├── scripts/<profile-id>/start.sh
├── ollama/models/
├── llama-cpp/models/
├── transformers/cache/
├── vllm/cache/
├── sglang/cache/
├── lmstudio/models/
└── agents/<agent-id>/
```

Sharing model storage prevents duplicate downloads for repeated model IDs across agents.

## Model Download Strategy

- Model weights are not baked into the Docker image.
- Default-enabled Ollama agents pull their default model at first start.
- Additional Ollama model downloads happen through `start_model`.
- `register_model` only records metadata in the registry; it does not download weights.
- Seq2seq and reranker models are loaded by their Python services at service startup through Hugging Face cache paths.

## GPU And Resource Policy

Current Ploinky manifests do not model GPU passthrough. This remains an operator/runtime concern.

Expected operator flags:

- Docker: `--gpus all`
- Podman/NVIDIA CDI: `--device nvidia.com/gpu=all`

The repo documents this and marks heavy agents with catalog metadata. `start-agent.sh` checks memory and warns when a non-CPU-safe agent starts without visible NVIDIA GPU signals.

## Tests And Validation

Primary test:

```sh
node --test tests/validate.mjs
```

Current result after the last change:

- 123 tests passing

Additional checks used:

```sh
sh -n scripts/dispatcher.sh scripts/start-agent.sh scripts/healthcheck.sh scripts/runners/*.sh
python3 -m py_compile scripts/services/*.py
git diff --check
```

Docker build was not run in the original implementation environment because Docker CLI was unavailable there. A future session should build and smoke-test the image before publishing.

## Current Git State At Handoff

The default branch `main` contains:

- `9bc1c3c` - local LLM Ploinky implementation
- `2115805` - repository instruction files

The temporary implementation branch was deleted locally and remotely. Work should continue directly from `main` or a newly named branch that follows `CLAUDE.md`.

## Remaining Work

Before publishing `assistos/local-llms:latest`:

- Build the Docker image.
- Run at least one Ploinky startup smoke test for:
  - `local-llms-manager`
  - `function-invocation`
  - `language-translation`
  - `relevance`
- Confirm current model IDs against the target backend at publish time.
- Decide whether vLLM/SGLang should stay experimental scripts or move to a separate GPU image tag.
- Decide whether Ploinky core should gain a GPU/container resource manifest extension.
- Consider adding a `pull_model`/`download_model` MCP tool if operators want explicit downloads separate from `start_model`.

## Key Files To Read Next

- `CLAUDE.md`
- `README.md`
- `Dockerfile`
- `catalog/backends.json`
- `catalog/agents/language-translation.json`
- `catalog/agents/relevance.json`
- `scripts/start-agent.sh`
- `scripts/dispatcher.sh`
- `scripts/services/translation_service.py`
- `scripts/services/reranker_service.py`
- `tests/validate.mjs`
