# Makefile

# Variables
VENV = venv
PYTHON = $(VENV)/bin/python
PIP = $(VENV)/bin/pip

# Setup everything
setup: venv submodules deps zk_engine_setup
	@echo "Setup complete."

# Create virtual environment
venv:
	@echo "Checking for virtual environment..."
	@if [ ! -d "$(VENV)" ]; then \
		echo "Creating virtual environment..."; \
		python3 -m venv $(VENV); \
	else \
		echo "Virtual environment already exists."; \
	fi

# Git submodule initialization
submodules:
	@echo "Updating git submodules..."
	git submodule update --init --recursive
	git submodule update --remote

# Install dependencies (main + submodules)
deps: venv
	@echo "Installing dependencies..."
	$(PIP) install --upgrade pip
	@echo "Installing zkscript_package dependencies..."
	$(PIP) install -r zkscript_package/requirements.txt
	@echo "Installing CLI dependencies..."
	$(PIP) install -r cli/requirements.txt

# Setup zk_engine
zk_engine_setup: deps
	@echo "Setting up zk_engine..."
	(cd zk_engine && cargo run --release -- setup)
