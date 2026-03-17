# Stage 1: CUDA build environment
FROM nvidia/cuda:13.0.0-devel-ubuntu24.04 AS cuda-builder

WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Copy and build CUDA kernels
COPY cuda/ ./cuda/
RUN cd cuda && \
    nvcc -arch=sm_86 -O3 -Xcompiler -fPIC -shared -o libbsv_cuda.so \
         ecdsa_verify.cu sha256_merkle.cu script_validate.cu

# Stage 2: Node.js build environment
FROM nvidia/cuda:13.0.0-devel-ubuntu24.04 AS node-builder

# Install Node.js 22 (LTS as of 2026)
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && NODE_MAJOR=22 \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y nodejs \
    && apt-get install -y python3 make g++ \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy package and install deps (NO native build)
COPY package*.json ./
RUN npm install

# Copy config files, source, and CUDA library
COPY binding.gyp tsconfig.json ./
COPY src/ ./src/
COPY --from=cuda-builder /build/cuda/libbsv_cuda.so ./cuda/

# Build native addon and TypeScript
RUN npm run build:native && npx tsc

# Stage 3: Production runtime
FROM nvidia/cuda:13.0.0-runtime-ubuntu24.04

# Install Node.js 22 (same method)
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && NODE_MAJOR=22 \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
    && apt-get update \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy built artifacts
COPY --from=node-builder /app/dist ./dist
COPY --from=node-builder /app/node_modules ./node_modules
COPY --from=node-builder /app/cuda ./cuda
COPY --from=node-builder /app/build ./build

# Set library path
ENV LD_LIBRARY_PATH=/app/cuda:$LD_LIBRARY_PATH
ENV NODE_ENV=production

# Create log directory
RUN mkdir -p /app/logs

COPY start.sh ./
RUN chmod +x start.sh

CMD ["./start.sh"]

EXPOSE 8080

CMD ["node", "dist/validator.js"]