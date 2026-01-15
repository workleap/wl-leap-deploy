.DEFAULT_GOAL := all
SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

SCRIPT_PATH := ./generate-chart.ps1

# Load .env file if it exists (for local development)
-include .env
export

ifeq ($(CI),true)
  ACR_NAME ?= $(error "ACR_NAME must be set in CI environment")
endif

CHART_REGISTRY := oci://$(ACR_NAME).azurecr.io/helm
CHART_NAME := leap-app
CHART_VERSION ?= 0.1.2

PRODUCT_NAME := foobar
LEAP_DEPLOY_CONFIG_PATH := ./examples/folded-config.json
ENVIRONMENT := dev
REGION := eastus
HELM_RELEASE_NAME := foobar

# Mock GitHub Actions environment variables (for annotations) when not in CI
ifndef CI
GITHUB_SERVER_URL="https://github.com"
GITHUB_REPOSITORY="workleap/wl-leap-shop"
GITHUB_WORKFLOW="workleap/wl-leap-deploy/.github/workflows/generate-chart.yml@refs/heads/main"
GITHUB_RUN_ID="123456789"
GITHUB_SHA="7f4b7ce6edb5aca1e2291bd34cc8a943991baaef"
GITHUB_ACTOR="marcellus.wallace@workleap.com"
endif

OUTPUT_DIR := ./out

all: manifests

FORCE:

$(OUTPUT_DIR)/chart: FORCE
	@mkdir -p $(OUTPUT_DIR)
	@if [ -z "$(ACR_NAME)" ]; then \
		echo "ACR_NAME is not set."; \
		echo "Set ACR_NAME environment variable, pass it inline to Make, or define it in a .env file."; \
		exit 1; \
	fi;
	@echo "Generating Helm chart from test values..."
	$(SCRIPT_PATH) \
	-ChartRegistry $(CHART_REGISTRY) -ChartName $(CHART_NAME) -ChartVersion $(CHART_VERSION) \
	-ProductName $(PRODUCT_NAME) \
	-FoldedConfigJson $(LEAP_DEPLOY_CONFIG_PATH) \
	-Environment $(ENVIRONMENT) \
	-Region $(REGION) \
	-OutputDirectory $@

$(OUTPUT_DIR)/manifests.yaml: $(OUTPUT_DIR)/chart acr/login FORCE
	@mkdir -p $(OUTPUT_DIR)
	@helm version
	@echo "Generating manifests from Helm chart..."
	@helm dependency build $<
	@helm template $(HELM_RELEASE_NAME) $< --values $</values.yaml > $@

.PHONY: acr/login
acr/login:  ## Log in to Azure Container Registry if not in CI
	@if [ -z "$(CI)" ]; then \
		if [ -z "$(ACR_NAME)" ]; then \
			echo "ACR_NAME is not set."; \
			echo "Set ACR_NAME environment variable, pass it inline to Make, or define it in a .env file."; \
			exit 1; \
		fi; \
		echo "Logging into Azure Container Registry $(ACR_NAME)..."; \
		az acr login --name $(ACR_NAME); \
	fi

.PHONY: chart  ## Create Helm chart from examples config files
chart: $(OUTPUT_DIR)/chart
	
.PHONY: manifests  ## Generate manifests from Helm chart
manifests: $(OUTPUT_DIR)/manifests.yaml

.PHONY: clean
clean:
	@rm -rf $(OUTPUT_DIR)

.PHONY: help
help:  ## Display this help message
	@echo "Available targets:"
	@grep -hE '^[a-zA-Z_/-]+:.*?##|^\.PHONY: [a-zA-Z_/-]+.*?##' $(MAKEFILE_LIST) | sed 's/^\.PHONY: \([^ ]*\)  */\1:  /' | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'