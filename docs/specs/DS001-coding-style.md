---
id: DS001
title: Coding Style
status: accepted
owner: repository
summary: Coding conventions, source layout, language rules, and test organization for the local-llms repository.
---

# DS001 Coding Style

## Introduction

This specification defines the coding style, file organization, and test conventions that apply across the local-llms repository. It is the canonical authority for these decisions; `AGENTS.md` points here.

## Core Content

### Languages and Runtimes

The repository uses three languages:

Shell scripts (POSIX `sh`) are the primary implementation language for runtime logic. Every script must start with `#!/bin/sh` and `set -e`. Shell is used for `start-agent.sh`, `dispatcher.sh`, `healthcheck.sh`, and all backend runner scripts under `scripts/runners/`. Shell was chosen because the scripts run inside a minimal Docker image where a Node.js or Python process for orchestration would add startup latency and memory overhead.

Python 3 is used for the two specialized backend services (`translation_service.py` and `reranker_service.py`) that require HuggingFace `transformers` and `sentence-transformers`. Python services use Flask for HTTP and are launched by their corresponding runner scripts. No Python packaging infrastructure (setup.py, pyproject.toml) is used; the scripts are standalone files executed directly.

Node.js (ESM) is used exclusively for the validation test suite (`tests/validate.mjs`). The test file uses `node:test` and `node:assert/strict` with no external test framework.

### Source Layout

```
local-llms/
  Dockerfile
  CLAUDE.md / AGENTS.md / README.md
  catalog/
    backends.json
    agents/<agent-id>.json
    schemas/agent.schema.json, backends.schema.json
  scripts/
    start-agent.sh
    dispatcher.sh
    healthcheck.sh
    runners/<backend>.sh
    services/<service>.py
  tests/
    validate.mjs
  <agent-id>/
    manifest.json
    mcp-config.json
    package.json
    healthcheck.sh (model agents only)
  docs/
    specs/
```

Each of the twelve agent directories contains exactly three files (manifest, mcp-config, package.json) plus an optional `healthcheck.sh` wrapper for model-serving agents. No agent directory contains application source code — all runtime logic lives in `scripts/` and is copied into the Docker image at `/opt/local-llms/scripts`.

### Shell Conventions

All shell scripts must be POSIX-compatible (`sh`, not `bash`). Scripts must use `set -e` for fail-fast behavior. Variable references must be quoted to prevent word splitting. Error messages must be written to stderr with a `[component]` prefix (e.g., `[start-agent] ERROR: ...`). JSON output must be produced through `jq`, never through string concatenation or `echo`.

Input validation in `dispatcher.sh` uses the `is_slug` and `is_model_name` functions. Slugs permit `[A-Za-z0-9._-]`. Model names additionally permit `:/+`. These character sets are intentionally restrictive to prevent path traversal and injection in generated scripts and registry entries.

### Python Conventions

Python services are single-file Flask applications. They load their model at startup and exit nonzero if preload fails, which causes the runner script to exit and `start-agent.sh` to detect the failure. The `/health` endpoint returns 503 until the model is loaded and 200 afterward. No Python linter or formatter is configured; the standard is to keep the files minimal and readable.

### JSON Configuration

Manifest files, MCP config files, and catalog entries use JSON (not YAML). All JSON files must be formatted with 2-space indentation. Catalog entries must conform to the JSON Schema files under `catalog/schemas/`.

### Test Organization

The single test file `tests/validate.mjs` contains all validation tests. Tests are organized into `describe` blocks covering catalog validation, manifest validation, MCP config validation, tool surface checks, backend selection rules, default startup behavior, port ordering, dispatcher runtime behavior, runner script existence, startup and health script properties, translation and relevance agent specifics, shared image properties, and env defaults.

Tests run with `node --test tests/validate.mjs`. The suite validates structural contracts (file existence, JSON schema conformance, port ordering, env defaults) and behavioral contracts (dispatcher envelope unwrapping, path traversal rejection, backendModel alias resolution). Tests do not require Docker, model downloads, or network access.

### File Size Policy

Shell scripts should remain under 500 lines. The dispatcher is the largest script at approximately 385 lines; if new tools push it significantly beyond this, consider splitting tool handlers into separate files sourced by the dispatcher. Python services should remain under 150 lines each.

### Git Policy

Branches must not use the `codex/` prefix. Commits must not include AI assistant co-author trailers or tool attribution. Commit metadata must appear human-authored.

## Decisions & Questions

### Question #1: Should a shell linter (shellcheck) be added to CI?

Response: Recommended but not yet configured. All scripts are written to be shellcheck-clean in intent. A future CI pipeline should run `shellcheck scripts/*.sh scripts/runners/*.sh`.

### Question #2: Should Python services migrate from Flask to a lighter framework?

Response: Flask is adequate for the current two services. If additional Python services are added, evaluate whether a shared ASGI framework (e.g., uvicorn + Starlette) would reduce per-service overhead.

## Conclusion

The repository uses POSIX shell for runtime orchestration, Python for specialized ML services, and Node.js for testing. All configuration is JSON. The coding style favors minimal, explicit, fail-fast scripts with strict input validation.
