# Base: Python 3.12 slim
FROM python:3.12-slim

# Environment
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/root/.cargo/bin:$PATH"

# Install system dependencies, Rust (rustup/cargo), and keep image minimal
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash \
      curl \
      git \
      tini \
      ca-certificates \
      build-essential \
      pkg-config \
      libssl-dev \
      gnupg \
 && rm -rf /var/lib/apt/lists/* \
 && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal 

# Install Node.js 22.x
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy the project
COPY . .

# Run zk_engine setup (requires cargo at runtime)
RUN cd zk_engine && cargo run --release -- setup

# Initialize git submodules 
RUN git submodule update --init --recursive

# Install Python dependencies system-wide (ignoring PEP 668)
RUN pip install --upgrade pip --break-system-packages \
    && pip install --break-system-packages -r zkscript_package/requirements.txt \
    && pip install --break-system-packages -r cli/requirements.txt

# Install Hardhat + EVM environment globally
RUN npm install -g \
      hardhat@2.26.3 \
      typescript \
      ts-node \
      @nomicfoundation/hardhat-ethers@3.0.8 \
      ethers \
      @nomicfoundation/hardhat-toolbox-viem@4.1.0 \
    && npm cache clean --force

# Tini for proper signal handling
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["bash"]
