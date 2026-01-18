.DEFAULT_GOAL := all
SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c
	
OUT_DIR := out
BANNER := .workleap

SCHEMAS_DIRECTORY := schemas
SCHEMA_FILE_NAME := leap-deploy.schema.json
FOLDED_SCHEMA_FILE_NAME := leap-deploy-folded.schema.json
EXAMPLES_DIRECTORY_NAME := examples
ASSERTIONS_DIRECTORY_NAME := assertions

SCHEMA_FILES := $(shell find $(SCHEMAS_DIRECTORY) -name '*.schema.json' -type f)
OUT_SCHEMA_FILES := $(addprefix $(OUT_DIR)/,$(SCHEMA_FILES))

FOLD_SCRIPT := scripts/fold-config.sh
FOLD_TEST_ENVIRONMENTS := dev staging prod
FOLD_TEST_REGIONS := na eu
FOLD_TEST_OUTPUT := $(OUT_DIR)/folded

JSONSCHEMA_VERSION := 14.0.4
JSONSCHEMA_BINARY := jsonschema

# GitHub repository info (inferred from environment or defaults for local)
GITHUB_REPOSITORY ?= workleap/wl-leap-deploy

.DEFAULT_GOAL := all

all: validate lint test

$(OUT_DIR)/%.schema.json: %.schema.json
	@mkdir -p $(dir $@)
	cp $< $@

.PHONY: banner
banner: $(BANNER)
	@cat $(BANNER)

.PHONY: install-cli
install-cli:  ## Install the jsonschema CLI if not present
	@if ! command -v $(JSONSCHEMA_BINARY) &> /dev/null; then \
		echo "Installing jsonschema CLI v$(JSONSCHEMA_VERSION)..."; \
		curl --retry 5 --location --fail-early --silent --show-error \
			--output /tmp/jsonschema-install.sh \
			"https://raw.githubusercontent.com/sourcemeta/jsonschema/main/install"; \
		chmod +x /tmp/jsonschema-install.sh; \
		/tmp/jsonschema-install.sh $(JSONSCHEMA_VERSION) $$HOME/.local; \
		rm /tmp/jsonschema-install.sh; \
		echo "Installed jsonschema CLI to $$HOME/.local/bin"; \
		echo "Make sure $$HOME/.local/bin is in your PATH"; \
	else \
		echo "jsonschema CLI already installed: $$($(JSONSCHEMA_BINARY) --version)"; \
	fi

.PHONY: test/folding
test/folding:  # Test folding examples and asserting against expected outputs
	@mkdir -p $(FOLD_TEST_OUTPUT)
	@echo "Testing example folding against assertion files..."
	@has_errors=0; \
	for example in $(SCHEMAS_DIRECTORY)/v*/$(EXAMPLES_DIRECTORY_NAME)/*.yaml; do \
		if [ -f "$$example" ]; then \
			example_name=$$(basename "$$example" .yaml); \
			example_dir=$$(dirname "$$example"); \
			version_dir=$$(echo "$$example" | cut -d'/' -f2); \
			schema_dir="$(SCHEMAS_DIRECTORY)/$$version_dir"; \
			folded_schema="$$schema_dir/$(FOLDED_SCHEMA_FILE_NAME)"; \
			assertions_dir="$$example_dir/$(ASSERTIONS_DIRECTORY_NAME)"; \
			if [ ! -d "$$assertions_dir" ]; then \
				echo "⚠️  No assertions directory for $$example_dir, skipping..."; \
				continue; \
			fi; \
			for env in $(FOLD_TEST_ENVIRONMENTS); do \
				assertion_file="$$assertions_dir/$${example_name}.$${env}.yaml"; \
				if [ ! -f "$$assertion_file" ]; then \
					echo "⚠️  Missing assertion file: $$assertion_file"; \
					continue; \
				fi; \
				echo "Testing $$example_name for env=$$env (no region)..."; \
				temp_file="$(FOLD_TEST_OUTPUT)/$$example_name-$$env.json"; \
				$(FOLD_SCRIPT) "$$example" "$$env" "" false | jq . > "$$temp_file"; \
				folded_yaml=$$(cat "$$temp_file" | yq -P); \
				assertion_content=$$(cat "$$assertion_file"); \
				if [ "$$folded_yaml" != "$$assertion_content" ]; then \
					echo "❌ ASSERTION FAILED: $$example_name env=$$env (no region)"; \
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
						echo "❌ SCHEMA VALIDATION FAILED: $$example_name env=$$env (no region)"; \
						has_errors=1; \
					fi; \
				fi; \
				for region in $(FOLD_TEST_REGIONS); do \
					assertion_file="$$assertions_dir/$${example_name}.$${env}.$${region}.yaml"; \
					if [ ! -f "$$assertion_file" ]; then \
						echo "⚠️  Missing assertion file: $$assertion_file"; \
						continue; \
					fi; \
					echo "Testing $$example_name for env=$$env region=$$region..."; \
					temp_file="$(FOLD_TEST_OUTPUT)/$$example_name-$$env-$$region.json"; \
					$(FOLD_SCRIPT) "$$example" "$$env" "$$region" false | jq . > "$$temp_file"; \
					folded_yaml=$$(cat "$$temp_file" | yq -P); \
					assertion_content=$$(cat "$$assertion_file"); \
					if [ "$$folded_yaml" != "$$assertion_content" ]; then \
						echo "❌ ASSERTION FAILED: $$example_name env=$$env region=$$region"; \
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
							echo "❌ SCHEMA VALIDATION FAILED: $$example_name env=$$env region=$$region"; \
							has_errors=1; \
						fi; \
					fi; \
				done; \
			done; \
		fi; \
	done; \
	if [ $$has_errors -eq 1 ]; then \
		echo ""; \
		echo "❌ Example folding tests failed"; \
		exit 1; \
	else \
		echo ""; \
		echo "✅ All example folding tests passed!"; \
	fi

.PHONY: validate/metaschema
validate/metaschema: package  # Validate that schema files are valid JSON Schema
	@echo "Validating schema files against their metaschemas..."
	@has_errors=0; \
	for schema_dir in $(OUT_DIR)/$(SCHEMAS_DIRECTORY)/v*/; do \
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
lint: package  ## Lint schema files
	@echo "Linting schema files..."
	@has_errors=0; \
	for schema_dir in $(OUT_DIR)/$(SCHEMAS_DIRECTORY)/v*/; do \
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
validate/versions: package  # Test that schema version patterns and $id are correct
	@echo "Testing schema version patterns and '\$$id' fields..."
	@for schema in $(OUT_DIR)/$(SCHEMAS_DIRECTORY)/v*/$(SCHEMA_FILE_NAME) $(OUT_DIR)/$(SCHEMAS_DIRECTORY)/v*/$(FOLDED_SCHEMA_FILE_NAME); do \
		if [ -f "$$schema" ]; then \
			version_dir=$$(echo "$$schema" | cut -d'/' -f3); \
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
validate: validate/metaschema validate/versions ## Validate schemas

.PHONY: upload-artifacts
upload-artifacts: package  ## Upload schema artifacts to GitHub release
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
	@echo "Uploading artifacts to release $${LATEST_RELEASE}..."
	@for schema_version in $(OUT_DIR)/$(SCHEMAS_DIRECTORY)/v*/$(SCHEMA_FILE_NAME); do \
		latest_release=$${LATEST_RELEASE:-unset}; \
		if [ -f "$$schema_version" ]; then \
			version=$$(echo "$$schema_version" | cut -d'/' -f3); \
			target_name="leap-deploy.$$version.schema.json"; \
			echo "  Uploading $$schema_version as $$target_name"; \
			if [ "$$CI" = "true" ]; then \
				cp "$$schema_version" "$$target_name"; \
				gh release upload $${latest_release} "$$target_name"; \
				rm "$$target_name"; \
			else \
				echo "    [DRY RUN] cp \"$$schema_version\" \"$$target_name\""; \
				echo "    [DRY RUN] gh release upload $${latest_release} \"$$target_name\""; \
				echo "    [DRY RUN] rm \"$$target_name\""; \
			fi; \
		fi; \
	done
	@for schema_version in $(OUT_DIR)/$(SCHEMAS_DIRECTORY)/v*/$(FOLDED_SCHEMA_FILE_NAME); do \
		latest_release=$${LATEST_RELEASE:-unset}; \
		if [ -f "$$schema_version" ]; then \
			version=$$(echo "$$schema_version" | cut -d'/' -f3); \
			target_name="leap-deploy-folded.$$version.schema.json"; \
			main_schema_artifact="leap-deploy.$$version.schema.json"; \
			release_url="https://github.com/$(GITHUB_REPOSITORY)/releases/download/$${latest_release}/$$main_schema_artifact"; \
			current_ref=$$(jq -r '.properties.workloads.additionalProperties."$$ref"' "$$schema_version" | sed 's|#.*||'); \
			echo "  Uploading $$schema_version as $$target_name (with rewritten \$$ref)"; \
			if [ "$$CI" = "true" ]; then \
				sed "s|$$current_ref|$$release_url|" "$$schema_version" > "$$target_name"; \
				gh release upload $${latest_release} "$$target_name"; \
				rm "$$target_name"; \
			else \
				echo "    [DRY RUN] sed \"s|$$current_ref|$$release_url|\" \"$$schema_version\" > \"$$target_name\""; \
				echo "    [DRY RUN] gh release upload $${latest_release} \"$$target_name\""; \
				echo "    [DRY RUN] rm \"$$target_name\""; \
			fi; \
		fi; \
	done
	@echo "✅ All artifacts uploaded successfully!"

.PHONY: test
test: test/folding  ## Run all tests

.PHONY: build
build: $(OUT_SCHEMA_FILES)  ## Build all schema files to out directory

.PHONY: package
package: build  ## Package schemas with embedded examples
	@echo "Embedding examples into schemas..."
	@for schema in $(OUT_SCHEMA_FILES); do \
		schema_dir=$$(dirname "$$schema" | sed 's|^$(OUT_DIR)/||'); \
		examples_dir="$$schema_dir/$(EXAMPLES_DIRECTORY_NAME)"; \
		if [ -d "$$examples_dir" ]; then \
			echo "  Embedding examples from $$examples_dir into $$schema"; \
			examples_json=$$(for ex in "$$examples_dir"/*.yaml; do yq -o=json "$$ex"; done | jq -s '.'); \
			jq --argjson examples "$$examples_json" '.examples = $$examples' "$$schema" > "$$schema.tmp" && mv "$$schema.tmp" "$$schema"; \
		fi; \
	done
	@echo "✅ All examples embedded!"

.PHONY: clean
clean:
	@rm -rf $(OUT_DIR)

.PHONY: help
help: banner  ## Display this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_/-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
