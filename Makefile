# Makefile

# Variables
VENV = venv
PYTHON = $(VENV)/bin/python
PIP = $(VENV)/bin/pip
REGTEST_DIR = ./wild-bit-lab
REGTEST_CONF = $(REGTEST_DIR)/data/bitcoin.conf

# Setup
setup: checks venv submodules deps zk_engine_setup ## Set up the environment, the dependencies, and the zk_engine
	@echo "Setup complete."

# Check for python3, cargo
checks: ## Check for Python, Cargo, and blockchain-specific software
	@echo "Checking for Python..."
	@command -v python3 >/dev/null	
	@python3 -c 'import sys; sys.version_info >= (3,12) or (print("Python version < 3.12.", file=sys.stderr), exit(1))'
	@echo "Python version OK"

	@echo "Checking for Cargo..."
	@command -V cargo >/dev/null
	@CARGO_VER=$$(cargo -V | cut -d" " -f2 | cut -d. -f1,2); \
	REQUIRED="1.86"; \
	if [ "$$(printf '%s\n%s\n' "$$CARGO_VER" "$$REQUIRED" | sort -V | head -n1)" != "$$REQUIRED" ]; then \
		echo >&2 "Cargo version < 1.86."; exit 1; \
	fi
	@echo "Cargo version OK"

	@echo "Checking for Sui CLI..."
	@command -v sui >/dev/null 2>&1 || echo "Warning: Sui CLI not found."
	
	@echo "Checking for Hardhat..."
	@command -v hardhat >/dev/null 2>&1 || echo "Warning: Hardhat not found."


# Create virtual environment
venv: ## Create a Python virtual environment if not present
	@echo "Checking for virtual environment..."
	@if [ ! -d "$(VENV)" ]; then \
		echo "Creating virtual environment..."; \
		python3 -m venv $(VENV); \
	else \
		echo "Virtual environment already exists."; \
	fi

# Git submodule initialization
submodules: ## Initialize and update git submodules
	@echo "Updating git submodules..."
	@git submodule update --init --recursive
	@git submodule update --remote

# Install dependencies (main + submodules)
deps: venv ## Install Python dependencies
	@echo "Installing dependencies..."
	@$(PIP) install --upgrade pip
	@echo "Installing zkscript_package dependencies..."
	@$(PIP) install -r zkscript_package/requirements.txt
	@echo "Installing CLI dependencies..."
	@$(PIP) install -r cli/requirements.txt

# Setup zk_engine
zk_engine_setup: deps ## Run zk_engine setup
	@echo "Setting up zk_engine..."
	@(cd zk_engine && cargo run --release -- setup)

# Run demo

sui_demo: checks venv submodules start_regtest start_sui ## SUI to BSV bridge demo
	@echo "Demo completed."

eth_demo: checks venv submodules start_regtest start_eth ## ETH to BSV bridge demo
	@echo "Demo completed."

start_sui: ## Start the SUI environment
	@echo "Setting up SUI environment..."

start_eth: ## Start the ETH environment
	@echo "Setting up ETH environment..."

start_regtest: ## Start the regtest environment
start_regtest: ## Start the regtest environment
	@echo "Setting up Bitcoin SV regtest..."
	@echo "Checking if WildBitLab is already running..."
	@if ! nc -z 127.0.0.1 18332 2>/dev/null; then \
		echo "WildBitLab is not running. Starting it now..."; \
		if [ ! -d "$(REGTEST_DIR)" ]; then \
			echo "Cloning WildBitLab..."; \
			git clone https://github.com/nchain-innovation/wild-bit-lab.git; \
		fi; \
		if ! grep -q '^maxscriptsizepolicy=100000000' $(REGTEST_CONF); then \
			echo "Updating regtest configuration..."; \
			echo 'maxscriptsizepolicy=100000000' >> $(REGTEST_CONF); \
		fi; \
		echo "Starting WildBitLab in the background..."; \
		(cd $(REGTEST_DIR) && nohup docker compose --file three-node.yml up > ../regtest.log 2>&1 &); \
		while ! nc -z 127.0.0.1 18332 2>/dev/null; do \
			echo "Waiting for Bitcoin node to be ready..."; \
			sleep 5; \
		done; \
	fi
	@echo "Mining 100 blocks..."
	@sleep 5
	@{ \
		ADDRESS=$$(curl -s --user bitcoin:bitcoin \
			--data-binary '{"jsonrpc":"1.0","id":"curltest","method":"getnewaddress"}' \
			-H 'content-type: text/plain;' http://127.0.0.1:18332 | cut -d'"' -f4); \
		echo "Using address: $$ADDRESS"; \
		curl -s -o /dev/null --user bitcoin:bitcoin \
			--data-binary '{"jsonrpc":"1.0","id":"curltest","method":"generatetoaddress","params":[100, "'"$$ADDRESS"'"]}' \
			-H 'content-type: text/plain;' http://127.0.0.1:18332; \
	}
	@echo "BitcoinSV regtest ready."


clean: _light_clean ## Remove virtualenv, reset submodules, stop WildBitLab
	@echo "Clean complete."

_light_clean: 
	@echo "Cleaning up..."
	@if [ -d "$(VENV)" ]; then \
		echo "Removing virtual environment..."; \
		rm -rf $(VENV); \
	fi
	@echo "Resetting Git submodules..."
	@git submodule foreach -q --recursive 'echo "- Resetting $$name"; (git reset --hard && git clean -fdx) > /dev/null'

	@if nc -z 127.0.0.1 18332 2>/dev/null; then \
		echo "Stopping WildBitLab containers..."; \
		docker compose -p wildbitlab -f $(REGTEST_DIR)/three-node.yml down; \
	fi

	@if [ -d "wild-bit-lab" ]; then \
		echo "Removing WildBitLab folder..."; \
		rm -rf wild-bit-lab; \
	fi

deep_clean: _light_clean ## Remove virtualenv, reset submodules, and clean Rust artifacts
	@echo "Cleaning Rust artifacts..."
	@(cd zk_engine && cargo clean)
	@echo "Clean complete."


help: ## Show this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
