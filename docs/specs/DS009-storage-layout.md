---
id: DS009
title: Storage Layout
status: accepted
owner: repository
summary: Shared model storage, per-backend directories, registry location, and volume mount contract.
---

# DS009 Storage Layout

## Introduction

All twelve agents share a single host-side storage root that is volume-mounted into every container. This specification defines the directory structure, the purpose of each subdirectory, and the invariants that prevent duplicate downloads and data corruption.

## Core Content

### Volume Mount

Every agent manifest declares the volume `.ploinky/data/local-llms` (host) mapped to `/data/local-llms` (container). Ploinky creates this directory under the workspace root on first agent start. Because the mount is shared across all agents in the workspace, any model downloaded by one agent is immediately available to another agent using the same backend.

### Directory Structure

```
.ploinky/data/local-llms/
  registry.json
  scripts/
    <profile-id>/
      start.sh
  ollama/
    models/
  llama-cpp/
    models/
  transformers/
    cache/
  vllm/
    cache/
  sglang/
    cache/
  lmstudio/
    models/
  agents/
    <agent-id>/
```

### Registry

`registry.json` is the workspace-level dynamic registry for operator-created model and profile entries. It is created by the dispatcher on first access with the structure `{ "models": {}, "profiles": {}, "version": 1 }`. All writes use atomic rename to prevent corruption.

### Generated Scripts

`scripts/<profile-id>/start.sh` files are created by the `generate_startup_script` MCP tool. Each script sets environment variables and delegates to `start-agent.sh`. Profile IDs are validated as slugs to prevent path traversal.

### Per-Backend Model Directories

Each backend has a dedicated directory for model storage:

- `ollama/models/` — Ollama's internal model cache, set via `OLLAMA_MODELS`.
- `llama-cpp/models/` — GGUF model files for llama.cpp. Operators must place files here manually.
- `transformers/cache/` — HuggingFace model cache shared between seq2seq and reranker backends, set via `TRANSFORMERS_CACHE` and `HF_HOME`.
- `vllm/cache/` — HuggingFace cache for vLLM, set via `HF_HOME` in the vLLM runner.
- `sglang/cache/` — HuggingFace cache for SGLang, set via `HF_HOME` in the SGLang runner.
- `lmstudio/models/` — LM Studio model storage.

The `transformers/cache/` directory is intentionally shared between the `transformers_seq2seq` and `reranker` backends because both use the HuggingFace `transformers` library and benefit from a unified cache to avoid duplicate downloads of shared tokenizer files.

### Per-Agent Scratch

`agents/<agent-id>/` is created by `start-agent.sh` for per-agent runtime data. Currently unused by the scripts but available for future per-agent state files.

### Sharing Semantics

The shared storage design means that if two agents use the same Ollama model (e.g., two agents both using `qwen3.5:4b`), the model is downloaded once and stored once. The `OLLAMA_MODELS` environment variable points all Ollama agents to the same directory.

This sharing is safe because Ollama, HuggingFace cache, and llama.cpp all use file-level locking or immutable-after-write semantics for their model files. Concurrent reads from multiple containers do not cause corruption.

### Disk Space Considerations

Model weights can be large: a 27B-parameter GGUF model may require 15-20 GB. The shared storage prevents this from being multiplied across agents. Operators should monitor `.ploinky/data/local-llms/` size, as it grows with each new model download and is not automatically pruned.

## Decisions & Questions

### Question #1: Should a model cleanup or pruning tool be added?

Options:
- Add a `cleanup_models` manager tool that lists unused models and optionally removes them.
- Leave disk management to the operator, since model usage patterns are deployment-specific.

### Question #2: Should per-backend directories be configurable independently?

Response: Currently all backend storage is under the single volume mount at `/data/local-llms/`. Per-backend mount points would add manifest complexity. Deferred unless operators need to place different backends on different filesystems.

## Conclusion

All agents share a single volume-mounted storage root under `.ploinky/data/local-llms/`. Model storage is organized by backend to prevent naming conflicts while enabling cross-agent sharing. The registry and generated scripts also live under this root for workspace-level persistence.
