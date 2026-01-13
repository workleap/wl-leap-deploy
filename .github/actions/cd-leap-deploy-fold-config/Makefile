OUT_DIR := out
FILE_PATH := ./examples/leap-deploy.yaml
SCHEMA_PATH := ../cd-leap-deploy-validate/schema.json
ENVIRONMENT := dev
REGION := na
SHOW_SOURCE ?= false

AJV_BINARY := ajv
AJV_VERSION := 5.0.0

all: fold

.PHONY: install-ajv
install-ajv:
	@which $(AJV_BINARY) > /dev/null 2>&1 || (echo "ajv not found, installing..." && npm install -g ajv-cli@$(AJV_VERSION))

.INTERMEDIATE: leap-deploy.json
leap-deploy.json: examples/leap-deploy.yaml
	@yq $< -o=json > $@

$(OUT_DIR)/folded.json:
	@mkdir -p $(@D)
	@./fold-config.sh $(FILE_PATH) $(ENVIRONMENT) $(REGION) $(SHOW_SOURCE) > $@

.PHONY: validate
validate: leap-deploy.json install-ajv
	$(AJV_BINARY) validate -s $(SCHEMA_PATH) -d $<

.PHONY: fold
fold: $(OUT_DIR)/folded.json install-ajv
	@echo "Folded config written to $<"
	@jq . $<
	@$(AJV_BINARY) -s $(SCHEMA_PATH) -d $<

.PHONY: clean
clean:
	@rm -rf $(OUT_DIR)
