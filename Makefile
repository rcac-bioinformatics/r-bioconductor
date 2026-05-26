##############################################################################
# Makefile — Build, test, and deploy Bioconductor HPC container
#
# Usage:
#   make                  # Build Docker image (default)
#   make build            # Build Docker image
#   make apptainer        # Convert to Apptainer SIF
#   make test             # Run CLI tests
#   make test-rstudio     # Run RStudio dependency checks
#   make test-all         # Run all tests
#   make deploy           # Install modulefile
#   make versions         # Check upstream versions
#   make clean            # Remove build artifacts
#   make help             # Show this help
#
# Override versions:
#   make build BIOC_VERSION=3.20 R_VERSION=4.4.2
##############################################################################

# Load defaults from VERSION file
include VERSION

# Configurable variables
IMAGE_NAME    ?= bioconductor-hpc
IMAGE_TAG     ?= $(BIOC_VERSION)
SIF_NAME      ?= bioconductor-hpc-$(BIOC_VERSION).sif

# Export for sub-scripts
export BIOC_VERSION R_VERSION UBUNTU_VERSION RSTUDIO_VERSION
export IMAGE_NAME IMAGE_TAG SIF_NAME

.PHONY: all build apptainer test test-rstudio test-all deploy versions clean help

# Default target
all: build

# -------------------------------------------------------------------------
# Build targets
# -------------------------------------------------------------------------

build: ## Build the Docker image
	@./scripts/build.sh

build-no-cache: ## Build Docker image without cache
	@./scripts/build.sh --no-cache

apptainer: ## Convert Docker image to Apptainer SIF
	@./scripts/build_apptainer.sh

apptainer-def: ## Build Apptainer SIF from definition file
	@./scripts/build_apptainer.sh --def

# -------------------------------------------------------------------------
# Test targets
# -------------------------------------------------------------------------

test: ## Run CLI tests against Docker image
	@./scripts/test_cli.sh $(IMAGE_NAME):$(IMAGE_TAG)

test-rstudio: ## Run RStudio dependency checks
	@./scripts/test_rstudio.sh $(IMAGE_NAME):$(IMAGE_TAG)

test-apptainer: ## Run CLI tests against SIF image
	@./scripts/test_cli.sh --apptainer $(SIF_NAME)

test-all: test test-rstudio ## Run all tests

# -------------------------------------------------------------------------
# Deployment targets
# -------------------------------------------------------------------------

deploy: ## Install modulefile to module path
	@./scripts/install_module.sh

# -------------------------------------------------------------------------
# Utility targets
# -------------------------------------------------------------------------

versions: ## Check upstream versions
	@./scripts/detect_versions.sh

clean: ## Remove build artifacts
	rm -f *.sif *.img
	@echo "Cleaned build artifacts."

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
