SCRIPT_PATH := ./generate-chart.ps1

# Load .env file if it exists (for local development)
-include .env
export

ifeq ($(CI),true)
  ACR_NAME ?= $(error "ACR_NAME must be set in CI environment")
else
  # Use WORKLEAP_GLOBAL_ACR_NAME defined in .env for local development which is ignored from source control
  ACR_NAME := $(WORKLEAP_GLOBAL_ACR_NAME)
endif

CHART_REGISTRY := oci://$(ACR_NAME).azurecr.io/helm
CHART_NAME := leap-app
CHART_VERSION ?= 0.1.2

PRODUCT_NAME := foobar
LEAP_DEPLOY_CONFIG_PATH := ./examples/folded-config.json
INFRA_CONFIG_PATH := ./examples/infra.json
HELM_RELEASE_NAME := foobar

WARNING: GITHUB_RUN_ID environment variable is not set. Run ID annotation will be omitted.
WARNING: GITHUB_WORKFLOW environment variable is not set. Workflow ref annotation will be omitted.
WARNING: GITHUB_SHA environment variable is not set. Commit SHA annotation will be omitted.
WARNING: GITHUB_ACTOR environment variable is not set. Actor annotation will be omitted.

OUTPUT_DIR := ./out

all: manifests

FORCE:

$(OUTPUT_DIR)/chart:
	@mkdir -p $(OUTPUT_DIR)
	@echo "Generating Helm chart from test values..."
	GITHUB_SERVER_URL="https://github.com" \
	GITHUB_REPOSITORY="workleap/wl-leap-shop" \
	GITHUB_WORKFLOW="workleap/wl-leap-deploy/.github/workflows/generate-chart.yml@refs/heads/main" \
	GITHUB_RUN_ID="123456789" \
	GITHUB_SHA="7f4b7ce6edb5aca1e2291bd34cc8a943991baaef" \
	GITHUB_ACTOR="marcellus.wallace@workleap.com" \
	$(SCRIPT_PATH) $(CHART_REGISTRY) $(CHART_NAME) $(CHART_VERSION) $(PRODUCT_NAME) $(LEAP_DEPLOY_CONFIG_PATH) $(INFRA_CONFIG_PATH) $@

$(OUTPUT_DIR)/manifests.yaml: $(OUTPUT_DIR)/chart acr/login FORCE
	@mkdir -p $(OUTPUT_DIR)
	@helm version
	@echo "Generating manifests from Helm chart..."
	@helm dependency build $<
	@helm template $(HELM_RELEASE_NAME) $< --values $</values.yaml > $@

.PHONY: acr/login
acr/login:
	@if [ -z "$(CI)" ]; then \
		echo "Logging into Azure Container Registry $(ACR_NAME)..."; \
		az acr login --name $(ACR_NAME); \
	fi

.PHONY: chart
chart: $(OUTPUT_DIR)/chart
	
.PHONY: manifests
manifests: $(OUTPUT_DIR)/manifests.yaml

.PHONY: clean
clean:
	@rm -rf $(OUTPUT_DIR)
