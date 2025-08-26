# syntax=docker/dockerfile:1

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install base dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.12 python3.12-venv python3-pip \
    curl git ca-certificates build-essential pkg-config libssl-dev \
    nodejs npm \
    cargo \
    netcat \
    docker.io docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# Ensure python3 points to 3.12
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1

# Install Rust via rustup
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Install SUI client + explorer
RUN cargo install --locked --git https://github.com/MystenLabs/sui.git sui \
    && cargo install --locked --git https://github.com/MystenLabs/sui.git sui-explorer-local

# Setup workdir
WORKDIR /app

# Copy repo into container
COPY . .

# Setup Python venv and dependencies
RUN python3 -m venv venv \
    && ./venv/bin/pip install --upgrade pip \
    && ./venv/bin/pip install -r zkscript_package/requirements.txt \
    && ./venv/bin/pip install -r cli/requirements.txt

# Build zk_engine
RUN cd zk_engine && cargo build --release

# Install pinned ETH dev dependencies globally
RUN npm install -g \
    hardhat@2.26.3 \
    typescript@5.3.0 \
    ts-node@10.9.1 \
    @nomicfoundation/hardhat-ethers@3.0.8 \
    ethers@6.9.0 \
    @nomicfoundation/hardhat-toolbox-viem@4.1.0

# Default entrypoint: run Make targets
ENTRYPOINT ["make"]

# Default command if nothing is passed: show help
CMD ["help"]
