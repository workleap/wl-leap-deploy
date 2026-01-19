.DEFAULT_GOAL := all
SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c
	
OUT_DIR := out
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
JSONSCHEMA_BINARY := npx -- @sourcemeta/jsonschema@$(JSONSCHEMA_VERSION)

# GitHub repository info (inferred from environment or defaults for local)
GITHUB_REPOSITORY ?= workleap/wl-leap-deploy

.DEFAULT_GOAL := all

all: validate lint test

.PHONY: banner
banner: $(BANNER)
	@cat $(BANNER)

.PHONY: test/folding
test/folding:  # Test folding and assert against expected outputs
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
validate/metaschema:  # Validate that schema files are valid JSON Schema
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
lint:  ## Lint schema files
	@echo "Linting schema files..."
	@has_errors=0; \
	for schema_dir in $(SCHEMAS_DIRECTORY)/v*/; do \
		if [ -d "$$schema_dir" ]; then \
			echo "Linting schemas in $$schema_dir..."; \
			if ! $(JSONSCHEMA_BINARY) lint "$$schema_dir"*.schema.json --resolve "$$schema_dir"/$(SCHEMA_FILE_NAME) --verbose --exclude orphan_definitions; then \
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

.PHONY: validate/versions
validate/versions:  # Validate that schema version patterns and $id are correct
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

.PHONY: validate/tests
validate/tests:  # Validate that test input files are valid against the schema
	@echo "Validating test input files against schemas..."
	@has_errors=0; \
	for input_file in $(SCHEMAS_DIRECTORY)/v*/$(TESTS_DIRECTORY_NAME)/*/input.yaml; do \
		if [ -f "$$input_file" ]; then \
			version_dir=$$(echo "$$input_file" | cut -d'/' -f2); \
			schema_dir="$(SCHEMAS_DIRECTORY)/$$version_dir"; \
			schema_file="$$schema_dir/$(SCHEMA_FILE_NAME)"; \
			echo "Validating $$input_file against $$schema_file..."; \
			temp_file="$$(mktemp)"; \
			yq -o=json "$$input_file" > "$$temp_file"; \
			if ! $(JSONSCHEMA_BINARY) validate "$$schema_file" "$$temp_file" \
				--resolve "$$schema_dir" \
				--extension .schema.json; then \
				echo "❌ VALIDATION FAILED: $$input_file"; \
				has_errors=1; \
			fi; \
			rm -f "$$temp_file"; \
		fi; \
	done; \
	if [ $$has_errors -eq 1 ]; then \
		echo ""; \
		echo "❌ Test validation failed"; \
		exit 1; \
	else \
		echo ""; \
		echo "✅ All test inputs are valid!"; \
	fi

.PHONY: validate/tests/assertions
validate/tests/assertions:  # Validate that test assertion files are valid against the folded schema
	@echo "Validating test assertion files against folded schema..."
	@has_errors=0; \
	for test_dir in $(SCHEMAS_DIRECTORY)/v*/$(TESTS_DIRECTORY_NAME)/*/; do \
		if [ -d "$$test_dir" ]; then \
			version_dir=$$(echo "$$test_dir" | cut -d'/' -f2); \
			schema_dir="$(SCHEMAS_DIRECTORY)/$$version_dir"; \
			schema_file="$$schema_dir/$(FOLDED_SCHEMA_FILE_NAME)"; \
			for assertion_file in "$$test_dir"*.yaml; do \
				if [ -f "$$assertion_file" ] && [ "$$(basename "$$assertion_file")" != "input.yaml" ]; then \
					echo "Validating $$assertion_file against $$schema_file..."; \
					temp_file="$$(mktemp)"; \
					yq -o=json "$$assertion_file" > "$$temp_file"; \
					if ! $(JSONSCHEMA_BINARY) validate "$$schema_file" "$$temp_file" \
						--resolve "$$schema_dir" \
						--extension .schema.json; then \
						echo "❌ VALIDATION FAILED: $$assertion_file"; \
						has_errors=1; \
					fi; \
					rm -f "$$temp_file"; \
				fi; \
			done; \
		fi; \
	done; \
	if [ $$has_errors -eq 1 ]; then \
		echo ""; \
		echo "❌ Assertion validation failed"; \
		exit 1; \
	else \
		echo ""; \
		echo "✅ All test assertions are valid!"; \
	fi

.PHONY: validate
validate: validate/metaschema validate/versions validate/tests validate/tests/assertions ## Validate schemas against metaschema and conventions as well as test inputs and assertions

.PHONY: upload-artifacts
upload-artifacts:  ## Upload schema artifacts to GitHub release
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
	@for schema_version in $(SCHEMAS_DIRECTORY)/v*/$(SCHEMA_FILE_NAME); do \
		latest_release=$${LATEST_RELEASE:-unset}; \
		if [ -f "$$schema_version" ]; then \
			version=$$(echo "$$schema_version" | cut -d'/' -f2); \
			target_name="leap-deploy.$$version.schema.json"; \
			target_path="$(ARTIFACTS_OUTPUT)/$$target_name"; \
			echo "  Preparing $$schema_version as $$target_name"; \
			cp "$$schema_version" "$$target_path"; \
			if [ "$$CI" = "true" ]; then \
				echo "  Uploading $$target_path"; \
				gh release upload $${latest_release} "$$target_path"; \
			else \
				echo "    [DRY RUN] gh release upload $${latest_release} \"$$target_path\""; \
			fi; \
		fi; \
	done
	@for schema_version in $(SCHEMAS_DIRECTORY)/v*/$(FOLDED_SCHEMA_FILE_NAME); do \
		latest_release=$${LATEST_RELEASE:-unset}; \
		if [ -f "$$schema_version" ]; then \
			version=$$(echo "$$schema_version" | cut -d'/' -f2); \
			target_name="leap-deploy-folded.$$version.schema.json"; \
			target_path="$(ARTIFACTS_OUTPUT)/$$target_name"; \
			main_schema_artifact="leap-deploy.$$version.schema.json"; \
			release_url="https://github.com/$(GITHUB_REPOSITORY)/releases/download/$${latest_release}/$$main_schema_artifact"; \
			current_ref=$$(jq -r '.properties.workloads.additionalProperties."$$ref"' "$$schema_version" | sed 's|#.*||'); \
			echo "  Preparing $$schema_version as $$target_name (with rewritten \$$ref)"; \
			sed "s|$$current_ref|$$release_url|" "$$schema_version" > "$$target_path"; \
			if [ "$$CI" = "true" ]; then \
				echo "  Uploading $$target_path"; \
				gh release upload $${latest_release} "$$target_path"; \
			else \
				echo "    [DRY RUN] gh release upload $${latest_release} \"$$target_path\""; \
			fi; \
		fi; \
	done
	@echo "✅ All artifacts uploaded successfully!"

.PHONY: test
test: test/folding  ## Run all tests

.PHONY: clean
clean:
	@rm -rf $(OUT_DIR)

.PHONY: help
help: banner  ## Display this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_/-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
