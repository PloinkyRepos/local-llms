---
id: DS010
title: GPU and Resource Policy
status: accepted
owner: repository
summary: RAM band enforcement, CPU safety checks, GPU passthrough limitations, and operator requirements.
---

# DS010 GPU and Resource Policy

## Introduction

Local LLM inference is resource-intensive. This specification defines how the repository handles RAM requirements, GPU availability, and the gap between what the catalog declares and what Ploinky manifests can enforce.

## Core Content

### RAM Band Enforcement

Every agent catalog entry declares a `ramBand` field as a human-readable range (e.g., `"2-8 GB"`, `"30-48 GB"`). The `start-agent.sh` script parses the lower bound from this string using a sed pattern that extracts the first integer.

At startup, the script reads total memory from `/proc/meminfo`, converts to gigabytes, and compares against the parsed minimum. If the container has less memory than the lower band, the script fails with an error message naming the agent, the required amount, and the detected amount. This prevents obviously undersized containers from starting backend processes that would be killed by the OOM killer.

The check is a floor, not a guarantee: the upper end of the RAM band is advisory, and the check does not account for memory consumed by other processes in the container.

### CPU Safety

Each catalog entry includes `cpuSafe: true` or `cpuSafe: false`. Agents marked `cpuSafe: false` (currently `adaptive-local` and `coding-local`, which default to 27B+ parameter models) are expected to be extremely slow on CPU-only hardware.

The startup script checks for NVIDIA GPU signals: the `nvidia-smi` binary and the `/dev/nvidia0` device. If a non-CPU-safe agent starts without either signal, the script emits a warning to stderr but does not fail. The warning explicitly notes that Ploinky v1 does not model GPU passthrough, so the startup is allowed to proceed despite the likely performance impact.

The check is best-effort: it detects NVIDIA GPUs but not AMD ROCm or Intel XPU accelerators. It also cannot verify that the GPU has been passed through to the container, only that GPU-related files exist.

### GPU Passthrough Limitations

Ploinky's current `containerSecurity` manifest field supports only `privileged: true`. There is no manifest-level field for GPU resource requests, device passthrough, or CUDA version requirements. GPU access must be configured at the operator level through Docker or Podman runtime flags:

- Docker: `--gpus all` or `--gpus '"device=0"'`
- Podman with NVIDIA CDI: `--device nvidia.com/gpu=all` with NVIDIA Container Toolkit CDI setup

The repository documents these requirements in `README.md` and in catalog `notes` fields for GPU-heavy agents. The startup script's GPU check is a courtesy warning, not an enforcement mechanism.

### Resource Metadata

The catalog provides additional resource metadata per agent:

- `gpuRequired: boolean` — whether the agent's default model requires a GPU to run at all (currently `false` for all agents, since even large models can run on CPU, just slowly).
- `recommendedVram: string | null` — the recommended GPU VRAM for the agent's default model.
- `readinessTimeout: integer` — seconds to wait for the backend to become ready. Heavy agents use longer timeouts (up to 600 seconds for `coding-local`).
- `startupPreset: string` — a label (`light`, `manager`, `translation`, `reranker`, `heavy`) that groups agents by resource profile.

These fields are informational metadata consumed by the test suite and by operators making deployment decisions. They are not enforced at runtime beyond the RAM band check.

### Shared Resource Contention

Because all agents share the same volume mount and potentially the same GPU, running multiple model-serving agents simultaneously can cause resource contention. Ollama mitigates this with `OLLAMA_MAX_LOADED_MODELS=1` and `OLLAMA_KEEP_ALIVE=5m` defaults, which unload idle models. There is no cross-agent resource coordinator; operators must manage agent concurrency based on available hardware.

## Decisions & Questions

### Question #1: Should Ploinky manifests gain a GPU resource declaration?

Options:
- Propose a `resources.gpu` field to Ploinky core that agents can use to request GPU passthrough.
- Keep GPU management as an operator concern and document the required runtime flags.
- Support both: use the manifest field when available, fall back to operator flags when not.

### Question #2: Should the RAM check be configurable or disableable?

Options:
- Add a `LOCAL_LLMS_SKIP_RAM_CHECK=true` environment variable for operators who know their container has more memory than `/proc/meminfo` reports (e.g., cgroups limits).
- Keep the check mandatory since it prevents the most common deployment failure.

## Conclusion

The repository enforces RAM floor checks at startup and warns about missing GPU signals for CPU-unsafe agents. GPU passthrough is an operator-level concern due to Ploinky manifest limitations. Catalog metadata provides resource guidance for deployment decisions but is not fully enforced at runtime.
