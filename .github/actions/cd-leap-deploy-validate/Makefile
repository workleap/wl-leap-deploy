SCHEMA_FILE := schema.json

AJV_BINARY := ajv
AJV_VERSION := 5.0.0

all: validate

.PHONY: install-ajv
install-ajv:
	@which $(AJV_BINARY) > /dev/null 2>&1 || (echo "ajv not found, installing..." && npm install -g ajv-cli@$(AJV_VERSION))

.PHONY: validate
validate: examples/leap-deploy.yaml install-ajv
	@$(AJV_BINARY) validate -s $(SCHEMA_FILE) -d $<