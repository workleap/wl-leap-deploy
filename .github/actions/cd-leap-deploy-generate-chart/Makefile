SCRIPT_PATH := ./generate-chart.ps1

CHART_REGISTRY := oci://infra0prod0global0registry0acr0ea18c271c312.azurecr.io/helm
CHART_NAME := leap-app
CHART_VERSION ?= 0.1.2

PRODUCT_NAME := foobar
LEAP_DEPLOY_CONFIG_PATH := ./examples/folded-config.json
INFRA_CONFIG_PATH := ./examples/infra.json
HELM_RELEASE_NAME := foobar

OUTPUT_DIR := ./.out

all: manifests

FORCE:

$(OUTPUT_DIR)/chart:
	@mkdir -p $(OUTPUT_DIR)
	@$(SCRIPT_PATH) $(CHART_REGISTRY) $(CHART_NAME) $(CHART_VERSION) $(PRODUCT_NAME) $(LEAP_DEPLOY_CONFIG_PATH) $(INFRA_CONFIG_PATH) $@

$(OUTPUT_DIR)/manifests.yaml: $(OUTPUT_DIR)/chart FORCE
	@helm dependency build $<
	@helm template $(HELM_RELEASE_NAME) $< --values $</values.yaml > $@

.PHONY: chart
chart: $(OUTPUT_DIR)/chart
	
.PHONY: manifests
manifests: $(OUTPUT_DIR)/manifests.yaml

.PHONY: clean
clean:
	@rm -rf $(OUTPUT_DIR)
