# Makefile

# Variables
VENV = venv
PYTHON = $(VENV)/bin/python
PIP = $(VENV)/bin/pip
REGTEST_DIR = ./wild-bit-lab
REGTEST_CONF = $(REGTEST_DIR)/data/bitcoin.conf
PAUSE = @if [ -t 0 ]; then printf "Press Enter to continue..."; read _; fi

# Helper function to check version
define check_version
@CUR=$$($(1)); \
REQ="$(2)"; \
CUR_NUM=$$(echo $$CUR | awk -F. '{print $$1*1000 + $$2}'); \
REQ_NUM=$$(echo $$REQ | awk -F. '{print $$1*1000 + $$2}'); \
if [ $$CUR_NUM -lt $$REQ_NUM ]; then \
	echo >&2 "$(3) version too old: $$CUR (need >= $$REQ)"; exit 1; \
else \
	echo "$(3) version OK"; \
fi
endef


setup: _check _venv _submodules _deps _zk_engine_setup ## Set up the environment, the dependencies, and the zk_engine
	@echo "Setup complete"

_check_python: ## Check Python version
	@echo "Checking Python..."
	@command -v python3 >/dev/null || (echo >&2 "Python3 not found"; exit 1)
	@python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3,12) else 1)' \
		|| (echo >&2 "Python version < 3.12"; exit 1)
	@echo "Python version OK"

_check_cargo: ## Check Cargo version
	@echo "Checking Cargo..."
	@command -v cargo >/dev/null || (echo >&2 "Cargo not found"; exit 1)
	$(call check_version,cargo -V | awk '{print $$2}' | awk -F. '{print $$1 "." $$2}',1.86,Cargo)

_check_node: ## Check Node.js version and location
	@echo "Checking Node.js version..."
	@command -v node >/dev/null || (echo >&2 "Node.js not found"; exit 1)
	$(call check_version,node -v | cut -d. -f1 | cut -c2-,22,Node.js)
	@echo "Checking Node.js location..."
	@if echo "$$(which node)" | grep -q "/mnt/"; then \
		echo >&2 "Node.js is installed in /mnt (Windows side). Please install inside WSL/macOS/Linux"; \
		exit 1; \
	fi
	@echo "Node.js location OK"

_check_npm: ## Check NPM version and location
	@echo "Checking NPM version..."
	@command -v npm >/dev/null || (echo >&2 "NPM not found"; exit 1)
	$(call check_version,npm -v | cut -d. -f1,7,NPM)
	@echo "Checking NPM location..."
	@if echo "$$(which npm)" | grep -q "/mnt/"; then \
		echo >&2 "NPM is installed in /mnt (Windows side). Please install inside WSL/macOS/Linux"; \
		exit 1; \
	fi
	@echo "NPM location OK"

_check_brew: ## Check Homebrew installation
	@echo "Checking Homebrew..."
	@command -v brew >/dev/null || (echo >&2 "Homebrew not found")
	@echo "Homebrew OK"

_check: _check_python _check_cargo _check_node _check_npm ## Check all dependencies
	@echo "Dependencies up to date"

_venv: ## Create a Python virtual environment if not present
	@echo "Creating virtual environment..."
	@rm -rf $(VENV)
	@python3 -m venv $(VENV);
	@echo "Upgrading pip and setuptools..."
	@$(VENV)/bin/python -m ensurepip --upgrade
	@$(VENV)/bin/pip install --upgrade pip setuptools wheel


_submodules: ## Initialize and update git submodules
	@echo "Updating git submodules..."
	@git submodule update --init --recursive

_deps: _venv ## Install Python dependencies
	@echo "Installing dependencies..."
	@$(PIP) install --upgrade pip
	@echo "Installing zkscript_package dependencies..."
	@$(PIP) install -r zkscript_package/requirements.txt
	@echo "Installing CLI dependencies..."
	@$(PIP) install -r cli/requirements.txt

_zk_engine_setup: _deps ## Run zk_engine setup
	@if [ ! -d "zk_engine/data/pob_engine/keys" ] || [ ! -d "zk_engine/data/tcp_engine/keys" ]; then \
		echo "Setting up zk_engine..."; \
		(cd zk_engine && cargo run --release -- setup); \
	fi
sui_demo: start_regtest start_sui _sui_demo_no_setup ## SUI to BSV bridge demo
evm_demo: start_regtest start_evm _evm_demo_no_setup ## ETH to BSV bridge demo
_sui_demo_no_setup: ## SUI to BSV bridge demo without setting up the environment
	@echo "Setting up the environment..."
	@(cd cli && PYTHONPATH=$$PWD:$$PWD/.. ../$(PYTHON) -m sui_demo setup --network regtest)
	@echo "Setup completed"
	$(PAUSE)
	@echo "Pegging-in..."
	@(cd cli && PYTHONPATH=$$PWD:$$PWD/.. ../$(PYTHON) -m sui_demo pegin --user alice --pegin-amount 42000000000 --network regtest)
	@echo "Peg-in completed"
	$(PAUSE)
	@echo "Transferring token..."
	@(cd cli && PYTHONPATH=$$PWD:$$PWD/.. ../$(PYTHON) -m sui_demo transfer --sender alice --receiver bob --token-index 0 --network regtest)
	@echo "Token transfer completed"
	$(PAUSE)
	@echo "Burning token..."
	@(cd cli && PYTHONPATH=$$PWD:$$PWD/.. ../$(PYTHON) -m sui_demo burn --user bob --token-index 0 --network regtest)
	@echo "Token burned"
	$(PAUSE)
	@echo "Pegging-out..."
	@(cd cli && PYTHONPATH=$$PWD:$$PWD/.. ../$(PYTHON) -m sui_demo pegout --user bob --token-index 0 --network regtest --update)
	@echo "SUI-BSV bridge demo completed"

_evm_demo_no_setup: ## ETH to BSV bridge demo without setting up the environment
	@echo "Setting up the environment..."
	@(cd cli && PYTHONPATH=$$PWD:$$PWD/.. ../$(PYTHON) -m evm_demo setup)
	@echo "Setup completed"
	$(PAUSE)
	@echo "Pegging-in..."
	@(cd cli && PYTHONPATH=$$PWD:$$PWD/.. ../$(PYTHON) -m evm_demo pegin --user alice --pegin-amount 10 --network regtest)
	@echo "Peg-in completed"
	$(PAUSE)
	@echo "Transferring token..."
	@(cd cli && PYTHONPATH=$$PWD:$$PWD/.. ../$(PYTHON) -m evm_demo transfer --sender alice --receiver bob --token-index 0 --network regtest)
	@echo "Token transfer completed"
	$(PAUSE)
	@echo "Burning token..."
	@(cd cli && PYTHONPATH=$$PWD:$$PWD/.. ../$(PYTHON) -m evm_demo burn --user bob --token-index 0 --network regtest)
	@echo "Token burned"
	$(PAUSE)
	@echo "Pegging-out..."
	@(cd cli && PYTHONPATH=$$PWD:$$PWD/.. ../$(PYTHON) -m evm_demo pegout)
	@echo "ETH-BSV bridge demo completed"

start_sui: ## Start local SUI environment
	@echo "Setting up SUI environment..."
	@PATH="$(HOME)/.cargo/bin:$$PATH" \
	RUST_LOG="off,sui_node=info" \
	sui start --with-faucet --force-regenesis > sui.log 2>&1 & \
	echo $$! > sui.pid
	@sleep 5
	@PATH="$(HOME)/.cargo/bin:$$PATH" sui client envs | grep -q local \
	  || PATH="$(HOME)/.cargo/bin:$$PATH" sui client new-env --alias local --rpc http://127.0.0.1:9000
	@PATH="$(HOME)/.cargo/bin:$$PATH" sui client switch --env local
	@PATH="$(HOME)/.cargo/bin:$$PATH" sui client active-address
	@PATH="$(HOME)/.cargo/bin:$$PATH" sui client faucet
	@PATH="$(HOME)/.cargo/bin:$$PATH" sui-explorer-local start > explorer.log 2>&1 &
	@echo "SUI environment ready"

start_evm: ## Start local ETH environment
	@echo "Setting up ETH environment..."
	@cd evm && npm init -y >/dev/null
	@cd evm && npm install --save-dev hardhat@2.26.3 typescript ts-node @nomicfoundation/hardhat-ethers@3.0.8 ethers @nomicfoundation/hardhat-toolbox-viem@4.1.0 >/dev/null
	@cd evm && nohup npx hardhat node > ../hardhat-node.log 2>&1 &
	@echo $$! > hardhat-node.pid
	@echo "ETH environment ready"

start_regtest: ## Start the regtest environment
	@echo "Setting up Bitcoin SV regtest..."
	@if [ ! -d "$(REGTEST_DIR)" ]; then \
		echo "Cloning WildBitLab..."; \
		git clone https://github.com/nchain-innovation/wild-bit-lab.git; \
	fi;
	@echo "Updating regtest configuration...";
	@if ! grep -q '^maxscriptsizepolicy=100000000' $(REGTEST_CONF); then \
		echo 'maxscriptsizepolicy=100000000' >> $(REGTEST_CONF); \
	fi;
	@echo "Starting WildBitLab in the background...";
	@(cd $(REGTEST_DIR) && docker compose -p wildbitlab --file one-node.yml up -d > ../regtest.log 2>&1 &);
	@while ! nc -z 127.0.0.1 18332 2>/dev/null; do \
		echo "Waiting for Bitcoin node to be ready..."; \
		sleep 2; \
	done;
	@echo "Mining 100 blocks..."
	@sleep 2
	@{ \
		ADDRESS=$$(curl -s --user bitcoin:bitcoin \
			--data-binary '{"jsonrpc":"1.0","id":"curltest","method":"getnewaddress"}' \
			-H 'content-type: text/plain;' http://127.0.0.1:18332 | cut -d'"' -f4); \
		echo "Using address: $$ADDRESS"; \
		curl -s -o /dev/null --user bitcoin:bitcoin \
			--data-binary '{"jsonrpc":"1.0","id":"curltest","method":"generatetoaddress","params":[100, "'"$$ADDRESS"'"]}' \
			-H 'content-type: text/plain;' http://127.0.0.1:18332; \
	}
	@echo "BitcoinSV regtest ready"


clean: _light_clean ## Remove temporary files, reset submodules, stop blockchain nodes
	@echo "Clean complete"

_light_clean: ## Equivalent to the clean command
	@echo "Resetting Git submodules..."
	@git submodule foreach -q --recursive 'echo "- Resetting $$name"; (git reset --hard && git clean -fdx) > /dev/null'

	@if [ -d "wild-bit-lab" ]; then \
		echo "Stopping WildBitLab containers..."; \
		(cd $(REGTEST_DIR) && docker compose -p wildbitlab --file one-node.yml down --remove-orphans > ../regtest.log 2>&1 &); \
		echo "Removing WildBitLab folder..."; \
		rm -rf wild-bit-lab; \
	fi

	@echo "Stopping Hardhat node..."
	@if [ -f hardhat-node.pid ]; then \
		PID=$$(cat hardhat-node.pid); \
		if kill -0 $$PID 2>/dev/null; then \
			kill $$PID; \
		fi; \
		rm -f hardhat-node.pid; \
		rm -f hardhat-node.log; \
	fi
	
	@echo "Stopping SUI node..."
	@if [ -f sui.pid ]; then \
		PID=$$(cat sui.pid); \
		if kill -0 $$PID 2>/dev/null; then \
			kill $$PID; \
		fi; \
		rm -f sui.pid; \
	fi
	@echo "Stopping Sui explorer...";
	@sui-explorer-local stop > /dev/null 2>&1 || true


deep_clean: _light_clean ## Reset the git repository to its original state
	@echo "Cleaning up..."
	@if [ -d "$(VENV)" ]; then \
		echo "Removing virtual environment..."; \
		rm -rf $(VENV); \
	fi
	@echo "Cleaning Rust artifacts..."
	@(cd zk_engine && cargo clean)
	@echo "Resetting Git repository..."
	$(PAUSE)
	@git reset --hard HEAD
	@git clean -fdx
	@echo "Clean complete"


help: ## Show the list of targets
	@echo "Available targets:"
	@grep -E '^[a-zA-Z][a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'


help_hidden: ## Show the list of hidden targets
	@echo "Available targets:"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
