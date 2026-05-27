---
id: DS005
title: MCP Dispatcher
status: accepted
owner: repository
summary: The shell-based MCP tool dispatcher, envelope unwrapping, tool routing, input validation, and registry management.
---

# DS005 MCP Dispatcher

## Introduction

The dispatcher (`scripts/dispatcher.sh`) is the single entry point for all MCP tool calls across every agent. Each agent's `mcp-config.json` routes tool invocations to this script with a `TOOL_NAME` environment variable that selects the handler. This specification defines the dispatcher's contract surface.

## Core Content

### Invocation

Every MCP tool declaration in every `mcp-config.json` must set `command` to `/opt/local-llms/scripts/dispatcher.sh` (the image-internal path). The tool name is passed via the `TOOL_NAME` environment variable, not as a command-line argument. The dispatcher reads its input from stdin as a JSON object.

### Envelope Unwrapping

AgentServer wraps MCP tool arguments in various envelope formats depending on the protocol path. The dispatcher's `normalize_input` function handles four envelope shapes:

1. `{ "input": { ... } }` — unwraps `.input`.
2. `{ "arguments": { ... } }` — unwraps `.arguments`.
3. `{ "params": { "arguments": { ... } } }` — unwraps `.params.arguments`.
4. `{ "params": { "input": { ... } } }` — unwraps `.params.input`.

If none of these patterns match, the raw object is used as-is. This normalization is critical because MCP tool calls may arrive through different AgentServer protocol versions, and the dispatcher must handle all of them.

### Output Contract

Every dispatcher response must be a single JSON object written to stdout. Error responses must use the form `{"error": "message"}`. The dispatcher must never produce non-JSON output on stdout. Diagnostic messages must go to stderr with a prefix identifying the component.

### Input Validation

The dispatcher validates all user-supplied identifiers:

- **Slugs** (`is_slug`): must match `[A-Za-z0-9._-]+`. Used for `profileId`, `backend`, and `agentId`. Rejects empty strings and characters outside the allowed set.
- **Model names** (`is_model_name`): must match `[A-Za-z0-9._:/+-]+`. The additional `:/` characters accommodate HuggingFace-style `org/model` identifiers and Ollama `model:tag` identifiers.

The `generate_startup_script` tool performs path traversal prevention by resolving the output directory to an absolute path and checking that the result is under the scripts output directory. Profile IDs like `../../escape` are rejected by the slug validator before reaching the filesystem.

### Manager Tools

The manager agent exposes six tools:

- `list_available_models` — merges catalog entries and registry entries, with optional `agentFilter` and `backendFilter` parameters. Returns `{ catalog: [...], registry: [...] }`.
- `register_model` — writes a model entry to `registry.json`. Defaults `backend` and `agentId` from the agent's environment if not provided. Does not download weights.
- `generate_startup_script` — creates a `start.sh` script under `$DATA_DIR/scripts/<profileId>/` that sets environment variables and delegates to `start-agent.sh`. Resolves `backendModel` aliases from the catalog.
- `register_agent_profile` — writes a profile entry to `registry.json` with models, default model, backend, and `promoted: false`.
- `promote_agent_profile` — marks a profile as promotion-ready. The actual agent directory creation requires a Ploinky restart and is an operator-level operation.
- `status_model` — probes the backend service to report running/stopped status and the currently loaded model.

### Model Agent Tools

Model-serving agents expose five tools:

- `list_available_models` — same as manager but scoped to the agent's own context.
- `start_model` — for Ollama, runs `ollama pull` to download and load the model. For seq2seq and reranker backends, returns a note that the model is loaded at service startup and requires an agent restart to switch. Resolves `backendModel` aliases.
- `stop_model` — for Ollama, runs `ollama stop` on the specified model. For other backends, returns a note to stop the agent.
- `status_model` — same as manager.
- `register_model` — same as manager but defaults `agentId` to the current agent.

### Specialized Tools

The `language-translation` agent additionally exposes `translate`, which sends a POST request to the translation service at `http://127.0.0.1:${BACKEND_PORT}/translate` with `text`, `source_lang`, and `target_lang` fields.

The `relevance` agent additionally exposes `rerank`, which sends a POST request to the reranker service at `http://127.0.0.1:${BACKEND_PORT}/rerank` with `query`, `passages`, optional `top_k`, and optional `instruction` fields.

### Registry

The dispatcher maintains a workspace-level registry at `$DATA_DIR/registry.json`. The registry is created on first access with the structure `{ "models": {}, "profiles": {}, "version": 1 }`. All registry writes use atomic rename (`mv` of a `.tmp` file) to prevent corruption from concurrent tool calls.

## Decisions & Questions

### Question #1: Should the dispatcher be split into per-tool scripts?

Response: The current single-file dispatcher is approximately 385 lines and manageable. If additional tools are added (e.g., `pull_model`, `list_backends`, `agent_info`), consider splitting into a dispatcher that sources per-tool handler files. For now, the single file is preferred for simplicity and to avoid sourcing overhead in shell.

### Question #2: Should the registry support versioned migrations?

Options:
- Add a migration step that checks `registry.version` and transforms the structure if needed.
- Keep version 1 as the only format and require manual migration if the schema changes.

## Conclusion

The dispatcher is a POSIX shell script that handles MCP tool routing, AgentServer envelope unwrapping, input validation, backend-model alias resolution, and registry management. It produces JSON-only output and validates all user-supplied identifiers to prevent injection and traversal.
