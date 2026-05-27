# Claude Review Findings

## Verdict

Proceed with changes.

The overall Ploinky shape is compatible: one repo, per-agent manifest directories, shared image, manager with `enable[]`, and AgentServer plus `mcp-config.json` dispatching.

The implementation plan needs revision before coding because the first version under-specified backend coverage, GPU/runtime requirements, model download behavior, readiness, ports, model storage, and per-agent MCP surface boundaries.

## Blocking Findings

- Some listed models are not Ollama/llama.cpp/LM Studio chat models. Translation models and rerankers need a Python `transformers`/reranker backend or equivalent.
- LM Studio headless-in-Docker is unverified and should not be a v1 backend.
- GPU passthrough is not represented in the Ploinky manifest contract, but the larger agents are impractical without GPU support.
- Model download timing is not specified.
- Backend ports, readiness checks, and OpenAI-compatible endpoint exposure are not specified.
- RAM bands are advisory unless the start script checks host resources or Ploinky gains container memory controls.

## Required Plan Changes

- Add a Python backend family for `transformers` translation/reranking models.
- Treat LM Studio as future/experimental until container-headless support is verified.
- Add explicit GPU/runtime strategy and a v1 CPU-safe fallback.
- Define model pull/download lifecycle and readiness timeout behavior.
- Split manager MCP tools from model-agent MCP tools.
- Define shared model storage under `.ploinky/data/local-llms`.
- Use `no-wait` for default model-agent dependencies launched by the manager.
- Add default profiles, manifest `about`, ports, readiness, and endpoint decisions.
