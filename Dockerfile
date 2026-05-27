FROM node:24-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl git ca-certificates procps jq \
    build-essential cmake \
    python3 python3-pip python3-venv \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/local-llms-venv
ENV PATH="/opt/local-llms-venv/bin:$PATH"
RUN pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cpu torch \
    && pip install --no-cache-dir \
    transformers sentencepiece protobuf \
    sentence-transformers \
    flask gunicorn

RUN curl -fsSL https://ollama.com/install.sh | sh

RUN git clone --depth 1 https://github.com/ggml-org/llama.cpp.git /tmp/llama.cpp \
    && cmake -S /tmp/llama.cpp -B /tmp/llama.cpp/build \
        -DCMAKE_BUILD_TYPE=Release \
        -DGGML_NATIVE=OFF \
        -DLLAMA_BUILD_TESTS=OFF \
        -DLLAMA_BUILD_EXAMPLES=OFF \
        -DLLAMA_BUILD_SERVER=ON \
    && cmake --build /tmp/llama.cpp/build --target llama-server -j"$(nproc)" \
    && cp /tmp/llama.cpp/build/bin/llama-server /usr/local/bin/llama-server \
    && rm -rf /tmp/llama.cpp

RUN mkdir -p \
    /data/local-llms/ollama/models \
    /data/local-llms/llama-cpp/models \
    /data/local-llms/transformers/cache \
    /data/local-llms/vllm/cache \
    /data/local-llms/sglang/cache \
    /data/local-llms/lmstudio/models

COPY scripts /opt/local-llms/scripts
COPY catalog /opt/local-llms/catalog
RUN chmod +x /opt/local-llms/scripts/*.sh /opt/local-llms/scripts/runners/*.sh

ENV TRANSFORMERS_CACHE=/data/local-llms/transformers/cache
ENV HF_HOME=/data/local-llms/transformers/cache
ENV OLLAMA_HOST=0.0.0.0:11434
ENV OLLAMA_MODELS=/data/local-llms/ollama/models
ENV LOCAL_LLMS_RUNTIME_DIR=/opt/local-llms
ENV LOCAL_LLMS_CATALOG_DIR=/opt/local-llms/catalog

WORKDIR /code

EXPOSE 7000 11434 8080 8090 8091
