.DEFAULT_GOAL := all
SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c
	
SCHEMAS_DIRECTORY := schemas
SCHEMA_FILE_NAME := leap-deploy.schema.json
FOLDED_SCHEMA_FILE_NAME := leap-deploy-folded.schema.json
EXAMPLES_DIRECTORY_NAME := examples
OUT_DIR := out

FOLD_SCRIPT := .github/actions/fold-config/fold-config.sh
FOLD_TEST_ENVIRONMENTS := dev staging prod
FOLD_TEST_REGIONS := na eu
FOLD_TEST_OUTPUT := $(OUT_DIR)/folded

AJV_VERSION := 5.0.0
AJV_BINARY := npx ajv-cli@$(AJV_VERSION)

# GitHub repository info (inferred from environment or defaults for local)
GITHUB_REPOSITORY ?= workleap/wl-leap-deploy

all: validate

.PHONY: test/examples
test/examples:
	@echo "Testing examples against schemas..."
	@has_errors=0; \
	for schema in $(SCHEMAS_DIRECTORY)/v*/$(SCHEMA_FILE_NAME); do \
		if [ -f "$$schema" ]; then \
			version_dir=$$(echo "$$schema" | cut -d'/' -f2); \
			version_number=$$(echo "$$version_dir" | sed 's/v//'); \
			examples_dir="$(SCHEMAS_DIRECTORY)/$$version_dir/$(EXAMPLES_DIRECTORY_NAME)"; \
			echo "Validating examples in $$examples_dir against $$schema..."; \
			if ! $(AJV_BINARY) validate -s $$schema -d "$$examples_dir/*" --all-errors --verbose; then \
				has_errors=1; \
			fi; \
		fi; \
	done; \
	if [ $$has_errors -eq 1 ]; then \
		echo ""; \
		echo "❌ Validation failed for one or more schemas"; \
		exit 1; \
	else \
		echo ""; \
		echo "✅ All validations passed successfully!"; \
	fi

.PHONY: test/fold
test/fold:
	@mkdir -p $(FOLD_TEST_OUTPUT)
	@echo "Testing folding of configurations and results against schemas..."
	@has_errors=0; \
	for example in $(SCHEMAS_DIRECTORY)/v*/$(EXAMPLES_DIRECTORY_NAME)/*.yaml; do \
		if [ -f "$$example" ]; then \
			version_dir=$$(echo "$$example" | cut -d'/' -f2); \
			version_number=$$(echo "$$version_dir" | sed 's/v//'); \
			examples_dir="$(SCHEMAS_DIRECTORY)/$$version_dir/$(EXAMPLES_DIRECTORY_NAME)"; \
			schema="$(SCHEMAS_DIRECTORY)/$$version_dir/$(SCHEMA_FILE_NAME)"; \
			folded_schema="$(SCHEMAS_DIRECTORY)/$$version_dir/$(FOLDED_SCHEMA_FILE_NAME)"; \
		for env in $(FOLD_TEST_ENVIRONMENTS); do \
			out_folded="$(FOLD_TEST_OUTPUT)/$$version_number-$$env.json"; \
			echo "Folding $$example for environment $$env (no region)..."; \
			if ! $(FOLD_SCRIPT) "$$example" $$env "" false | jq . > "$$out_folded"; then \
				has_errors=1; \
			else \
				echo "Validating folded output against $$folded_schema..."; \
				if ! $(AJV_BINARY) validate -s $$folded_schema -r $$schema -d "$$out_folded" --all-errors --verbose; then \
					has_errors=1; \
				fi; \
			fi; \
			for region in $(FOLD_TEST_REGIONS); do \
				out_folded="$(FOLD_TEST_OUTPUT)/$$version_number-$$env-$$region.json"; \
				echo "Folding $$example for environment $$env and region $$region..."; \
				if ! $(FOLD_SCRIPT) "$$example" $$env $$region false | jq . > "$$out_folded"; then \
					has_errors=1; \
				else \
					echo "Validating folded output against $$folded_schema..."; \
					if ! $(AJV_BINARY) validate -s $$folded_schema -r $$schema -d "$$out_folded" --all-errors --verbose; then \
						has_errors=1; \
					fi; \
				fi; \
			done; \
			done; \
		fi; \
	done; \
	if [ $$has_errors -eq 1 ]; then \
		echo ""; \
		echo "❌ Validation failed for one or more schemas"; \
		exit 1; \
	else \
		echo ""; \
		echo "✅ All validations passed successfully!"; \
	fi

.PHONY: test/chart
test/chart: .github/actions/generate-chart/Makefile  ## Generate Helm chart and template manifests
	@echo "Generating Helm chart and validating manifests..."
	@make -C .github/actions/generate-chart all

.PHONY: validate
validate:  ## Validate schema version patterns
	@echo "Validating schema version patterns..."
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
	@echo "Uploading artifacts to release $${LATEST_RELEASE}..."
	@for schema_version in $(SCHEMAS_DIRECTORY)/v*/$(SCHEMA_FILE_NAME); do \
		if [ -f "$$schema_version" ]; then \
			version=$$(echo "$$schema_version" | cut -d'/' -f2); \
			target_name="leap-deploy.$$version.schema.json"; \
			echo "  Uploading $$schema_version as $$target_name"; \
			if [ "$$CI" = "true" ]; then \
				cp "$$schema_version" "$$target_name"; \
				gh release upload $${LATEST_RELEASE} "$$target_name"; \
				rm "$$target_name"; \
			else \
				echo "    [DRY RUN] cp \"$$schema_version\" \"$$target_name\""; \
				echo "    [DRY RUN] gh release upload $${LATEST_RELEASE} \"$$target_name\""; \
				echo "    [DRY RUN] rm \"$$target_name\""; \
			fi; \
		fi; \
	done
	@for schema_version in $(SCHEMAS_DIRECTORY)/v*/$(FOLDED_SCHEMA_FILE_NAME); do \
		if [ -f "$$schema_version" ]; then \
			version=$$(echo "$$schema_version" | cut -d'/' -f2); \
			target_name="leap-deploy-folded.$$version.schema.json"; \
			main_schema_artifact="leap-deploy.$$version.schema.json"; \
			release_url="https://github.com/$(GITHUB_REPOSITORY)/releases/download/$${LATEST_RELEASE}/$$main_schema_artifact"; \
			current_ref=$$(jq -r '.properties.workloads."$$ref"' "$$schema_version" | sed 's|#.*||'); \
			echo "  Uploading $$schema_version as $$target_name (with rewritten \$$ref)"; \
			if [ "$$CI" = "true" ]; then \
				sed "s|$$current_ref|$$release_url|" "$$schema_version" > "$$target_name"; \
				gh release upload $${LATEST_RELEASE} "$$target_name"; \
				rm "$$target_name"; \
			else \
				echo "    [DRY RUN] sed \"s|$$current_ref|$$release_url|\" \"$$schema_version\" > \"$$target_name\""; \
				echo "    [DRY RUN] gh release upload $${LATEST_RELEASE} \"$$target_name\""; \
				echo "    [DRY RUN] rm \"$$target_name\""; \
			fi; \
		fi; \
	done
	@echo "✅ All artifacts uploaded successfully!"

.PHONY: test
test: test/examples test/fold ## Run all tests

.PHONY: clean
clean:
	@rm -rf $(OUT_DIR)

.PHONY: help
help:  ## Display this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_/-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
