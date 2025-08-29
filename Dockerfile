# syntax=docker/dockerfile:1

# --- Base stage ---
FROM ubuntu:24.04 AS base

ENV DEBIAN_FRONTEND=noninteractive

# System deps (INTENTIONALLY no nodejs/npm here)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3.12-venv \
    curl git ca-certificates build-essential pkg-config libssl-dev \
    cargo \
    netcat-openbsd \
    file procps \
    && rm -rf /var/lib/apt/lists/*

# Rust via rustup
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# --- Stage 2: grab sui binary from Mysten ---
FROM mysten/sui-tools:devnet AS sui-tools

# --- Final stage ---
FROM base

# Bring in sui
COPY --from=sui-tools /usr/local/bin/sui /usr/local/bin/sui

# Workdir + repo
WORKDIR /app
COPY . .

# Python venv + deps
RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --upgrade pip \
    && /opt/venv/bin/pip install -r zkscript_package/requirements.txt \
    && /opt/venv/bin/pip install -r cli/requirements.txt

# Make venv, cargo and /usr/local/bin first on PATH
ENV PATH="/opt/venv/bin:/usr/local/bin:/root/.cargo/bin:${PATH}"

# Build zk_engine (runtime setup/keys happen later via Makefile)
RUN cargo build --release --manifest-path zk_engine/Cargo.toml

# ---------- Install Node.js 22 from official tarball (arch-aware) ----------
ARG NODE_VERSION=22.10.0
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      amd64) node_arch="x64" ;; \
      arm64) node_arch="arm64" ;; \
      ppc64el) node_arch="ppc64le" ;; \
      s390x) node_arch="s390x" ;; \
      *) echo "Unsupported architecture: $arch"; exit 1 ;; \
    esac; \
    curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.xz" \
      | tar -xJ -C /usr/local --strip-components=1; \
    ln -sf /usr/local/bin/node /usr/bin/node; \
    ln -sf /usr/local/bin/npm  /usr/bin/npm; \
    ln -sf /usr/local/bin/npx  /usr/bin/npx; \
    node -v; npm -v

# ETH dev deps exactly like Makefile (ensure package.json exists)
RUN cd evm \
    && npm init -y \
    && npm install --save-dev \
       hardhat@2.26.3 \
       typescript \
       ts-node \
       @nomicfoundation/hardhat-ethers@3.0.8 \
       ethers \
       @nomicfoundation/hardhat-toolbox-viem@4.1.0

# Default entry: run Make targets
ENTRYPOINT ["make"]
CMD ["help"]
