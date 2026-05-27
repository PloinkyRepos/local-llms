# Local LLM Ploinky Agents

## Summary

Bootstrap `local-llms` as a Ploinky repo with one shared `assistos/local-llms` Docker image, repo-tracked first-class agents from the table, and runtime-extensible model/script config under `.ploinky/data/local-llms`.

Use a hybrid config model:

- Git-tracked catalog defines stable Ploinky agents, model candidates, RAM bands, backend defaults, and startup presets.
- Workspace state stores dynamic registered models, generated startup scripts, and operator overrides.
- Default startup enables only the manager plus light agents: `function-selection` and `function-invocation`.

## Key Changes

### Shared Base Image

- Add a `Dockerfile` based on Node 24 + Debian slim, with Python, curl/git/build tools, Ollama, llama.cpp server, and LM Studio headless/`lms` support.
- Pin image/runtimes via build args and publish as `assistos/local-llms:<tag>`.
- Avoid nested Docker/privileged mode.

### Shared Runtime Scripts

- `start-agent.sh` reads `LOCAL_LLMS_AGENT_ID`, resolves config from repo catalog plus `.ploinky/data/local-llms`, starts the selected backend, waits for readiness, then starts Ploinky `AgentServer`.
- Shared MCP dispatcher implements `list_available_models`, `register_model`, `generate_startup_script`, `start_model`, `stop_model`, `status_model`.
- Runtime-generated scripts live under `.ploinky/data/local-llms/scripts/<profile-id>/`.

### Repo Catalog

- `catalog/backends.json` for `ollama`, `llama_cpp`, `lmstudio`.
- `catalog/agents/<agent>.json` for every table agent, including model candidates, default backend, RAM band, purpose, startup preset, and default-enabled flag.
- Treat supplied model names as desired candidates; tools validate availability with the selected backend instead of assuming every ID exists.

### Ploinky Agents

- Add top-level folders for all listed agents, each with `manifest.json` and `mcp-config.json`.
- All manifests use `container: "assistos/local-llms:${LOCAL_LLMS_IMAGE_TAG}"`, default env, `.ploinky/data/local-llms` volume, and shared start script.
- Add `local-llms-manager` static/meta agent with `enable[]` entries for the light defaults only.

### Dynamic Additions

- `register_model` adds models/presets to workspace state.
- `register_agent_profile` creates a logical runtime profile inside the manager.
- `promote_agent_profile` generates a real repo agent folder from the template when a dynamic profile should become a first-class Ploinky agent.

## Test Plan

- Validate JSON catalogs and generated manifests.
- Unit-test config merge precedence: repo defaults, profile defaults, workspace registry, explicit tool args.
- Unit-test MCP tool contracts and failure payloads.
- Smoke-test `ploinky start local-llms-manager <port>` starts manager plus light defaults.
- Smoke-test Ollama and llama.cpp model list/start/status/stop flows with tiny test models or mocked backend commands.
- Verify no secrets/tokens/model prompts are logged by default.

## Assumptions

- Config decision: hybrid model.
- Runtime decision: one shared image, no nested Docker.
- Default startup: manager, `function-selection`, `function-invocation`.
- Soul Gateway integration remains optional: local agents expose OpenAI-compatible endpoints that can later be registered with embedded Soul Gateway.
- External runtime references checked during planning: Ollama OpenAI compatibility, Ollama pull API, llama.cpp server/Docker docs, and LM Studio headless docs.
