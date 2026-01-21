.DEFAULT_GOAL := lint
SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

BIN_DIR := ../../bin

MARKDOWNLINT_VERSION := 0.43.0
MARKDOWNLINT_NPM_PACKAGE := markdownlint-cli
MARKDOWNLINT_BINARY := $(BIN_DIR)/node_modules/.bin/markdownlint

ADR_FILES := $(wildcard [0-9][0-9][0-9][0-9]-*.md)

$(MARKDOWNLINT_BINARY):  ## Install the markdownlint CLI if not present
	@if [ ! -f $(MARKDOWNLINT_BINARY) ]; then \
		echo "Installing markdownlint CLI v$(MARKDOWNLINT_VERSION)..."; \
		npm install --prefix "$(BIN_DIR)" $(MARKDOWNLINT_NPM_PACKAGE)@$(MARKDOWNLINT_VERSION); \
	else \
		echo "markdownlint CLI already installed"; \
	fi

.PHONY: lint
lint: $(MARKDOWNLINT_BINARY)  ## Lint ADR markdown files
	@echo "Linting ADR files..."
	@$(MARKDOWNLINT_BINARY) --config .markdownlint.yml $(ADR_FILES)
	@echo ""
	@echo "✅ All ADR files linted successfully!"

validate: $(ADR_FILES) ## Validate ADR structure
	@echo "Validating ADR structure..."
	@for f in $^; do \
		adr_header=$$(head -3 "$$f"); \
        echo "$$adr_header" | yq .status - | grep -E -q '^(proposed|accepted|rejected|deprecated|superseded by .*)$$' || { echo "Invalid status in $$f"; exit 1; }; \
        echo "$$adr_header" | yq .date - | grep -E -q '^[0-9]{4}-[0-9]{2}-[0-9]{2}$$' || { echo "Invalid date in $$f"; exit 1; }; \
    done
	@echo ""
	@echo "✅ All ADR files have valid structure!"

.PHONY: help
help:  ## Display this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_/-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
