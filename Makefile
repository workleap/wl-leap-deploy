SCHEMAS_DIRECTORY := schemas
SCHEMA_FILE_NAME := leap-deploy.schema.json
EXAMPLES_DIRECTORY_NAME := examples
OUT_DIR := out

AJV_BINARY := ajv
AJV_VERSION := 5.0.0

all: validate

.PHONY: install-ajv
install-ajv:
	@which $(AJV_BINARY) > /dev/null 2>&1 || (echo "ajv not found, installing..." && npm install -g ajv-cli@$(AJV_VERSION))


# 	@$(AJV_BINARY) validate -s $(SCHEMA_FILE) -d $<

.PHONY: test
test: install-ajv  ## Validate example files against the schemas
	@mkdir -p $(OUT_DIR)
	@echo "Testing examples against schemas..."
	@has_errors=0; \
	for schema in schemas/v*/$(SCHEMA_FILE_NAME); do \
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

.PHONY: validate
validate:  ## Validate schema version patterns
	@echo "Validating schema version patterns..."
	@for schema in schemas/v*/$(SCHEMA_FILE_NAME); do \
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
	@for schema_version in schemas/v*/$(SCHEMA_FILE_NAME); do \
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
	@echo "✅ All artifacts uploaded successfully!"
