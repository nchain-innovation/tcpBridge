FROM ubuntu:22.04

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install base dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.12 python3.12-venv python3-pip \
    curl git ca-certificates build-essential pkg-config libssl-dev \
    nodejs npm \
    cargo \
    netcat \
    && rm -rf /var/lib/apt/lists/*

# Ensure python3 points to 3.12
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1

# Install Rust and Cargo (latest stable via rustup, overrides apt cargo if needed)
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Install SUI client + explorer
RUN cargo install --locked --git https://github.com/MystenLabs/sui.git sui \
    && cargo install --locked --git https://github.com/MystenLabs/sui.git sui-explorer-local

# Setup workdir
WORKDIR /app

# Copy repo into container
COPY . .

# Setup Python virtual environment + deps
RUN python3 -m venv venv \
    && ./venv/bin/pip install --upgrade pip \
    && ./venv/bin/pip install -r zkscript_package/requirements.txt \
    && ./venv/bin/pip install -r cli/requirements.txt

# Build zk_engine
RUN cd zk_engine && cargo build --release

# Install Hardhat globally (ETH environment)
RUN npm install -g hardhat

# Default command: show available demos
CMD [ "make", "help" ]
