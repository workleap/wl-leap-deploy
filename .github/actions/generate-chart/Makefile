SCRIPT_PATH := ./generate-chart.ps1

ifndef CI
ACR_NAME ?= $(error "ACR_NAME is not set")
else
# When running in CI, ACR login in performed through the CI workflow
ACR_NAME := ""
endif

CHART_REGISTRY := oci://$(ACR_NAME).azurecr.io/helm
CHART_NAME := leap-app
CHART_VERSION ?= 0.1.2

PRODUCT_NAME := foobar
LEAP_DEPLOY_CONFIG_PATH := ./examples/folded-config.json
INFRA_CONFIG_PATH := ./examples/infra.json
HELM_RELEASE_NAME := foobar

OUTPUT_DIR := ./out

all: manifests

FORCE:

$(OUTPUT_DIR)/chart:
	@mkdir -p $(OUTPUT_DIR)
	@GITHUB_SERVER_URL="https://github.com" GITHUB_REPOSITORY="workleap/wl-leap-shop" \
	$(SCRIPT_PATH) $(CHART_REGISTRY) $(CHART_NAME) $(CHART_VERSION) $(PRODUCT_NAME) $(LEAP_DEPLOY_CONFIG_PATH) $(INFRA_CONFIG_PATH) $@

$(OUTPUT_DIR)/manifests.yaml: $(OUTPUT_DIR)/chart acr/login FORCE
	@mkdir -p $(OUTPUT_DIR)
	@helm version
	@echo "Generating manifests from Helm chart..."
	@cat $</Chart.yaml
	@cat $</values.yaml
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
