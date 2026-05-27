---
id: DS000
title: Vision
status: accepted
owner: repository
summary: High-level vision and scope for the local-llms Ploinky repository.
---

# DS000 Vision

## Introduction

This document establishes the purpose, scope, and guiding principles for the `local-llms` repository. The repository provides a Ploinky-managed collection of agents that run local large language models as MCP servers inside a shared Docker image.

## Core Content

### Purpose

The local-llms repository exists to give a Ploinky workspace self-hosted inference capacity across several model roles without depending on external API providers. Each role is represented by a dedicated Ploinky agent that starts, manages, and exposes a single backend model server through MCP tools.

### Scope

The repository contains twelve agents: one management agent (`local-llms-manager`) and eleven model-serving agents covering translation, relevance scoring, function selection and invocation, general chat at multiple parameter scales, planning with and without validation, adaptive replanning, and agentic coding. All agents share a single Docker image (`assistos/local-llms`) and a common set of runtime scripts, catalog definitions, and an MCP dispatcher.

The repository does not own or modify Ploinky core, AgentServer, or the model weights themselves. It consumes the Ploinky manifest contract and the AgentServer MCP hosting surface as external dependencies.

### Guiding Principles

The design favors explicit configuration over implicit behavior. Model downloads are never silent — default-enabled agents pull their model at first start with visible logging, and additional models require an explicit MCP tool call. Backend selection is catalog-driven rather than heuristic-based, so that non-Ollama models (seq2seq translation, cross-encoder rerankers) are routed to the correct Python service rather than forced through a chat-completions interface.

Resource awareness is a first-class concern. Every agent catalog entry declares a RAM band and a `cpuSafe` flag. The startup script checks available memory and warns when GPU-dependent agents start without visible NVIDIA hardware, since Ploinky manifests do not yet model GPU passthrough.

Experimental backends (vLLM, SGLang, LM Studio llmster) are cataloged with `experimental: true` and are not default dependencies. They exist as extension points for operators who need GPU-accelerated inference or alternative serving stacks.

### Non-Goals

The repository does not aim to become a general-purpose model serving platform. It targets Ploinky workspace use cases where agents need local inference as a tool rather than as a standalone service. It does not manage multi-node inference, model training, fine-tuning, or quantization workflows.

## Decisions & Questions

### Question #1: Should vLLM and SGLang graduate from experimental status?

Options:
- Keep them experimental until a GPU-tagged Docker image variant is published and tested.
- Graduate them once Ploinky manifests support GPU resource declarations.
- Remove them entirely and treat GPU inference as an external service.

### Question #2: Should a dedicated `pull_model` or `download_model` MCP tool be added?

Options:
- Add it as a manager-only tool that explicitly downloads weights without starting the backend.
- Keep the current design where `start_model` handles downloads implicitly for Ollama and Python services load at startup.

## Conclusion

The local-llms repository provides Ploinky workspaces with self-contained local inference across a range of model roles. Its design centers on explicit model management, catalog-driven backend routing, shared storage, and resource-aware startup.
