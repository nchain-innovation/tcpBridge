# Docker-in-Docker base
FROM docker:28.3-dind

# Variables
ENV RUST_VERSION=1.87.0
ENV DOCKER_COMPOSE_VERSION=2.21.1
ENV REGTEST_DIR=/app/wild-bit-lab
ENV REGTEST_CONF=$REGTEST_DIR/data/bitcoin.conf

# Install system dependencies
RUN apk add --no-cache \
    bash \
    curl \
    git \
    tini \
    build-base \
    openssl \
    pkgconfig \
    python3 \
    py3-pip \
    py3-virtualenv \
    nodejs \
    npm \
    libc6-compat # required for some binaries

# Install Rust
ENV PATH="/root/.cargo/bin:$PATH"
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain ${RUST_VERSION} \
    && rustc --version

# Environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/root/.cargo/bin:$PATH"

# Set working directory
WORKDIR /app

# Copy project
COPY . .

# Update git submodules
RUN git submodule update --init --recursive

# Setup zk-engine
RUN cd zk_engine && cargo run --release -- setup

# Clone wild-bit-lab and modify config
RUN if ! grep -q '^maxscriptsizepolicy=100000000' "$REGTEST_CONF"; then \
        echo 'maxscriptsizepolicy=100000000' >> "$REGTEST_CONF"; \
    fi

# Mark /app as safe Git directory
RUN git config --global --add safe.directory /app

# Tini for proper signal handling
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["bash", "-l"]
