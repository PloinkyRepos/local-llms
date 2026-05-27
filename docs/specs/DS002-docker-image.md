---
id: DS002
title: Shared Docker Image
status: accepted
owner: repository
summary: Architecture and build contract for the shared assistos/local-llms Docker image.
---

# DS002 Shared Docker Image

## Introduction

All twelve agents in the repository run inside a single Docker image, `assistos/local-llms:latest`. This specification defines the image contents, build-time decisions, and the contract between the image and the Ploinky agent directories.

## Core Content

### Base Image

The image is built from `node:24-slim`. This base provides Node.js for AgentServer and a Debian-slim userland for system packages. The image installs `curl`, `git`, `ca-certificates`, `procps`, `jq`, `build-essential`, `cmake`, `python3`, `python3-pip`, and `python3-venv`.

### Python Virtual Environment

A Python virtual environment is created at `/opt/local-llms-venv` and activated via `PATH` for all subsequent layers. PyTorch is installed from the CPU-only wheel index (`https://download.pytorch.org/whl/cpu`) in a separate `pip install` invocation to prevent the CPU index from being applied to other packages. The remaining Python packages (`transformers`, `sentencepiece`, `protobuf`, `sentence-transformers`, `flask`, `gunicorn`) are installed from the default PyPI index in a second `pip install` invocation.

This two-step installation is load-bearing: combining them into a single `pip install` with `--index-url` would apply the PyTorch CPU index to all packages, potentially pulling incompatible or missing wheels for `transformers` and `sentence-transformers`.

### Backend Binaries

Ollama is installed via its official install script (`https://ollama.com/install.sh`). The `llama-server` binary is built from source by cloning `ggml-org/llama.cpp` at `--depth 1`, building with CMake in Release mode with `DGGML_NATIVE=OFF` (for portability) and `DLLAMA_BUILD_SERVER=ON`, and copying the resulting binary to `/usr/local/bin/llama-server`. The llama.cpp source tree is removed after the build.

vLLM, SGLang, and LM Studio llmster are not installed in the base image. Their runner scripts check for the required binaries at startup and exit with guidance if they are missing. This keeps the base image size manageable while leaving experimental backends available for custom image variants.

### Runtime Layout Inside the Image

The image copies `scripts/` to `/opt/local-llms/scripts` and `catalog/` to `/opt/local-llms/catalog`, then sets execute permissions on all `.sh` files. The environment variables `LOCAL_LLMS_RUNTIME_DIR=/opt/local-llms` and `LOCAL_LLMS_CATALOG_DIR=/opt/local-llms/catalog` are set at build time.

Ploinky mounts each agent directory at `/code` inside the container. Shared scripts and catalog must not live under `/code` because they would be overwritten by the agent mount. The `/opt/local-llms` path is the image-internal runtime root that is independent of the Ploinky agent mount.

### Data Directories

The image creates empty directories under `/data/local-llms/` for each backend's model storage: `ollama/models`, `llama-cpp/models`, `transformers/cache`, `vllm/cache`, `sglang/cache`, `lmstudio/models`. These directories are populated at runtime through the Ploinky volume mount.

### Exposed Ports

The Dockerfile exposes ports 7000 (AgentServer), 11434 (Ollama), 8080 (llama.cpp), 8090 (transformers seq2seq), and 8091 (reranker). These are documentation hints; actual port mapping is controlled by each agent's manifest profile.

### Model Weights

Model weights are never baked into the Docker image. They are downloaded at runtime by either Ollama (`ollama pull`), the Python service startup (HuggingFace cache), or future explicit download tools. This keeps the image size under control and allows model selection to vary per agent and per deployment.

## Decisions & Questions

### Question #1: Should a separate GPU image tag be published?

Options:
- Publish `assistos/local-llms:gpu` with CUDA runtime, vLLM, and SGLang pre-installed.
- Keep a single image and require operators to extend it for GPU workloads.
- Use multi-stage builds with a shared base and GPU/CPU variants.

### Question #2: Should the image pin specific Ollama and llama.cpp versions?

Response: Currently both are installed from latest (Ollama install script, llama.cpp HEAD). For reproducible builds, the Dockerfile should pin Ollama to a release version and llama.cpp to a tagged commit. This is deferred until the first production image publish.

## Conclusion

The shared Docker image provides a single build artifact for all twelve agents, containing Ollama, llama-server, a Python virtual environment with transformers and sentence-transformers, and the repository's runtime scripts and catalog. Model weights are external to the image.
