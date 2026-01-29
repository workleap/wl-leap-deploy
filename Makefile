.DEFAULT_GOAL := all
SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

OUT_DIR := out
BIN_DIR := bin

BANNER := .workleap

SCHEMAS_DIRECTORY := schemas
SCHEMA_FILE_NAME := leap-deploy.schema.json
FOLDED_SCHEMA_FILE_NAME := leap-deploy-folded.schema.json
TESTS_DIRECTORY_NAME := tests

SCHEMA_FILES := $(shell find $(SCHEMAS_DIRECTORY) -name '*.schema.json' -type f)

FOLD_SCRIPT := scripts/fold-config.sh
FOLD_TEST_ENVIRONMENTS := dev staging prod
FOLD_TEST_REGIONS := na eu
FOLD_TEST_OUTPUT := $(OUT_DIR)/folded
ARTIFACTS_OUTPUT := $(OUT_DIR)/artifacts

JSONSCHEMA_VERSION := 14.1.0
JSONSCHEMA_NPM_PACKAGE := @sourcemeta/jsonschema
JSONSCHEMA_BINARY := $(BIN_DIR)/node_modules/.bin/jsonschema

# GitHub repository info (inferred from environment or defaults for local)
GITHUB_REPOSITORY ?= workleap/wl-leap-deploy

.DEFAULT_GOAL := all

all: validate lint test

.PHONY: banner
banner: $(BANNER)
	@cat $(BANNER)

$(JSONSCHEMA_BINARY):  ## Install the jsonschema CLI if not present
	@if ! command -v $(JSONSCHEMA_BINARY) &> /dev/null; then \
		echo "Installing jsonschema CLI v$(JSONSCHEMA_VERSION)..."; \
		npm install --prefix "$(BIN_DIR)" @sourcemeta/jsonschema@14.1.0; \
	else \
		echo "jsonschema CLI already installed: $$($(JSONSCHEMA_BINARY) --version)"; \
	fi

.PHONY: test/schema
test/schema: $(JSONSCHEMA_BINARY)  ## Run schema unit tests (valid and invalid inputs)
	@echo "Running schema unit tests..."
	@has_errors=0; \
	for schema_dir in $(SCHEMAS_DIRECTORY)/v*/; do \
		if [ -d "$$schema_dir/schema-tests" ]; then \
			echo "Testing schemas in $$schema_dir..."; \
			for test_file in "$$schema_dir/schema-tests"/*.test.json; do \
				if [ -f "$$test_file" ]; then \
					echo "Running $$test_file..."; \
					if ! $(JSONSCHEMA_BINARY) test "$$test_file" \
						--resolve "$$schema_dir/$(SCHEMA_FILE_NAME)" \
						--resolve "$$schema_dir/$(FOLDED_SCHEMA_FILE_NAME)" \
						--verbose; then \
						has_errors=1; \
					fi; \
				fi; \
			done; \
		fi; \
	done; \
	if [ $$has_errors -eq 1 ]; then \
		echo ""; \
		echo "❌ Schema tests failed"; \
		exit 1; \
	else \
		echo ""; \
		echo "✅ All schema tests passed!"; \
	fi

.PHONY: test/folding
test/folding: $(JSONSCHEMA_BINARY)  ## Test folding and assert against expected outputs
	@mkdir -p $(FOLD_TEST_OUTPUT)
	@echo "Testing folding inputs against assertion files..."
	@has_errors=0; \
	for input_file in $(SCHEMAS_DIRECTORY)/v*/$(TESTS_DIRECTORY_NAME)/*/input.yaml; do \
		if [ -f "$$input_file" ]; then \
			test_dir=$$(dirname "$$input_file"); \
			test_name=$$(basename "$$test_dir"); \
			version_dir=$$(echo "$$input_file" | cut -d'/' -f2); \
			schema_dir="$(SCHEMAS_DIRECTORY)/$$version_dir"; \
			folded_schema="$$schema_dir/$(FOLDED_SCHEMA_FILE_NAME)"; \
			for env in $(FOLD_TEST_ENVIRONMENTS); do \
				assertion_file="$$test_dir/$${env}.yaml"; \
				if [ ! -f "$$assertion_file" ]; then \
					echo "⚠️  Missing assertion file: $$assertion_file"; \
					continue; \
				fi; \
				echo "Testing $$test_name for env=$$env (no region)..."; \
				temp_file="$(FOLD_TEST_OUTPUT)/$$test_name-$$env.json"; \
				$(FOLD_SCRIPT) "$$input_file" "$$env" "" false | jq . > "$$temp_file"; \
				folded_yaml=$$(cat "$$temp_file" | yq -P); \
				assertion_content=$$(cat "$$assertion_file"); \
				if [ "$$folded_yaml" != "$$assertion_content" ]; then \
					echo "❌ ASSERTION FAILED: $$test_name env=$$env (no region)"; \
					echo "Expected (from $$assertion_file):"; \
					echo "$$assertion_content"; \
					echo "---"; \
					echo "Got:"; \
					echo "$$folded_yaml"; \
					has_errors=1; \
				else \
					echo "Validating against schema..."; \
					if ! $(JSONSCHEMA_BINARY) validate "$$folded_schema" "$$temp_file" \
						--resolve "$$schema_dir" \
						--extension .schema.json; then \
						echo "❌ SCHEMA VALIDATION FAILED: $$test_name env=$$env (no region)"; \
						has_errors=1; \
					fi; \
				fi; \
				for region in $(FOLD_TEST_REGIONS); do \
					assertion_file="$$test_dir/$${env}.$${region}.yaml"; \
					if [ ! -f "$$assertion_file" ]; then \
						echo "⚠️  Missing assertion file: $$assertion_file"; \
						continue; \
					fi; \
					echo "Testing $$test_name for env=$$env region=$$region..."; \
					temp_file="$(FOLD_TEST_OUTPUT)/$$test_name-$$env-$$region.json"; \
					$(FOLD_SCRIPT) "$$input_file" "$$env" "$$region" false | jq . > "$$temp_file"; \
					folded_yaml=$$(cat "$$temp_file" | yq -P); \
					assertion_content=$$(cat "$$assertion_file"); \
					if [ "$$folded_yaml" != "$$assertion_content" ]; then \
						echo "❌ ASSERTION FAILED: $$test_name env=$$env region=$$region"; \
						echo "Expected (from $$assertion_file):"; \
						echo "$$assertion_content"; \
						echo "---"; \
						echo "Got:"; \
						echo "$$folded_yaml"; \
						has_errors=1; \
					else \
						echo "Validating against schema..."; \
						if ! $(JSONSCHEMA_BINARY) validate "$$folded_schema" "$$temp_file" \
							--resolve "$$schema_dir" \
							--extension .schema.json; then \
							echo "❌ SCHEMA VALIDATION FAILED: $$test_name env=$$env region=$$region"; \
							has_errors=1; \
						fi; \
					fi; \
				done; \
			done; \
		fi; \
	done; \
	if [ $$has_errors -eq 1 ]; then \
		echo ""; \
		echo "❌ Folding tests failed"; \
		exit 1; \
	else \
		echo ""; \
		echo "✅ All folding tests passed!"; \
	fi

.PHONY: validate/metaschema
validate/metaschema: $(JSONSCHEMA_BINARY)  # Validate that schema files are valid JSON Schema
	@echo "Validating schema files against their metaschemas..."
	@has_errors=0; \
	for schema_dir in $(SCHEMAS_DIRECTORY)/v*/; do \
		if [ -d "$$schema_dir" ]; then \
			echo "Validating schemas in $$schema_dir..."; \
			if ! $(JSONSCHEMA_BINARY) metaschema "$$schema_dir"*.schema.json --verbose; then \
				has_errors=1; \
			fi; \
		fi; \
	done; \
	if [ $$has_errors -eq 1 ]; then \
		echo ""; \
		echo "❌ Metaschema validation failed"; \
		exit 1; \
	else \
		echo ""; \
		echo "✅ All schemas are valid!"; \
	fi

.PHONY: lint
lint: $(JSONSCHEMA_BINARY)  ## Lint schema files
	@echo "Linting schema files..."
	@has_errors=0; \
	for schema_dir in $(SCHEMAS_DIRECTORY)/v*/; do \
		if [ -d "$$schema_dir" ]; then \
			echo "Linting schemas in $$schema_dir..."; \
			if ! $(JSONSCHEMA_BINARY) lint "$$schema_dir"*.schema.json --resolve "$$schema_dir"/$(SCHEMA_FILE_NAME) --verbose; then \
				has_errors=1; \
			fi; \
		fi; \
	done; \
	if [ $$has_errors -eq 1 ]; then \
		echo ""; \
		echo "❌ Linting failed for one or more schemas"; \
		exit 1; \
	else \
		echo ""; \
		echo "✅ All schemas linted successfully!"; \
	fi

.PHONY: format
format: $(JSONSCHEMA_BINARY)  ## Format schema files
	@echo "Formatting schema files..."
	@for schema_dir in $(SCHEMAS_DIRECTORY)/v*/; do \
		if [ -d "$$schema_dir" ]; then \
			echo "Formatting schemas in $$schema_dir..."; \
			$(JSONSCHEMA_BINARY) fmt "$$schema_dir"*.schema.json; \
		fi; \
	done
	@echo ""
	@echo "✅ All schemas formatted successfully!"

.PHONY: validate/versions
validate/versions: $(JSONSCHEMA_BINARY)  # Validate that schema version patterns and $id are correct
	@echo "Testing schema version patterns and '\$$id' fields..."
	@for schema in $(SCHEMAS_DIRECTORY)/v*/$(SCHEMA_FILE_NAME) $(SCHEMAS_DIRECTORY)/v*/$(FOLDED_SCHEMA_FILE_NAME); do \
		if [ -f "$$schema" ]; then \
			version_dir=$$(echo "$$schema" | cut -d'/' -f2); \
			version_number=$$(echo "$$version_dir" | sed 's/v//'); \
			expected_pattern="^$${version_number}(\\.[0-9]+){0,2}\$$"; \
			actual_pattern=$$(jq -r '.properties.version.pattern' "$$schema"); \
			echo "Checking $$schema..."; \
			echo "  Expected pattern: $$expected_pattern"; \
			echo "  Actual pattern:   $$actual_pattern"; \
			if [ "$$actual_pattern" != "$$expected_pattern" ]; then \
				echo "❌ ERROR: Version pattern mismatch in $$schema"; \
				echo "  Expected: $$expected_pattern"; \
				echo "  Found:    $$actual_pattern"; \
				exit 1; \
			fi; \
			expected_id_segment="/$$version_dir/"; \
			actual_id=$$(jq -r '."$$id"' "$$schema"); \
			echo "  Expected \$$id segment: $$expected_id_segment"; \
			echo "  Actual \$$id:           $$actual_id"; \
			if ! echo "$$actual_id" | grep -q "$$expected_id_segment"; then \
				echo "❌ ERROR: \$$id version segment mismatch in $$schema"; \
				echo "  Expected segment: $$expected_id_segment"; \
				echo "  Found \$$id:      $$actual_id"; \
				exit 1; \
			fi; \
			echo "✅ $$schema validation passed"; \
		fi; \
	done
	@echo ""
	@echo "All schema validations passed!"

.PHONY: validate
validate: validate/metaschema validate/versions  ## Validate schemas against metaschema and version conventions

# Process and upload schema artifacts
# $(1) = file pattern (e.g., $(SCHEMAS_DIRECTORY)/v*/$(SCHEMA_FILE_NAME))
# $(2) = target name prefix (e.g., leap-deploy)
define process_schema_artifact
	@for schema_version in $(1); do \
		latest_release=$${LATEST_RELEASE:-dry-run-release-placeholder}; \
		if [ -f "$$schema_version" ]; then \
			version=$$(echo "$$schema_version" | cut -d'/' -f2); \
			target_name="$(2).$$version.schema.json"; \
			target_path="$(ARTIFACTS_OUTPUT)/$$target_name"; \
			echo "  Preparing $$schema_version as $$target_name"; \
			cp "$$schema_version" "$$target_path"; \
			$(JSONSCHEMA_BINARY) fmt "$$target_path"; \
			if [ "$$CI" = "true" ]; then \
				echo "  Uploading $$target_path"; \
				gh release upload $${latest_release} "$$target_path"; \
			else \
				echo "    [DRY RUN] gh release upload $${latest_release} \"$$target_path\""; \
			fi; \
		fi; \
	done
endef

.PHONY: upload-artifacts
upload-artifacts: $(JSONSCHEMA_BINARY)  ## Upload schema artifacts to GitHub release
	@if [ "$$CI" = "true" ]; then \
		if [ -z "$$LATEST_RELEASE" ]; then \
			echo "❌ ERROR: LATEST_RELEASE environment variable is not set"; \
			exit 1; \
		fi; \
		if [ -z "$$GH_TOKEN" ]; then \
			echo "❌ ERROR: GH_TOKEN environment variable is not set"; \
			exit 1; \
		fi; \
	else \
		echo "🏠 Running locally - commands will be echoed but not executed"; \
	fi
	@mkdir -p $(ARTIFACTS_OUTPUT)
	@echo "Uploading artifacts to release $${LATEST_RELEASE}..."
	$(call process_schema_artifact,$(SCHEMAS_DIRECTORY)/v*/$(SCHEMA_FILE_NAME),leap-deploy)
	$(call process_schema_artifact,$(SCHEMAS_DIRECTORY)/v*/$(FOLDED_SCHEMA_FILE_NAME),leap-deploy-folded)
	@echo "✅ All artifacts uploaded successfully!"

.PHONY: test
test: test/schema test/folding  ## Run all tests

.PHONY: clean
clean:
	@rm -rf $(OUT_DIR)

.PHONY: help
help: banner  ## Display this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_/-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
