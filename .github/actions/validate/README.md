# Leap Deploy Validate

**Action Path:** `.github/actions/validate`

Validates `leap-deploy.yaml` configuration files against the leap-deploy JSON schema to ensure correctness before deployment.

## Features

- **Schema Validation**: Verifies `leap-deploy.yaml` structure, required fields, and data types
- **Early Error Detection**: Catches configuration errors before they reach deployment pipelines
- **Comprehensive Reporting**: Shows all validation errors at once for faster troubleshooting

## Inputs

| Input         | Required | Default                   | Description                                                                                               |
| ------------- | -------- | ------------------------- | --------------------------------------------------------------------------------------------------------- |
| `file-path`   | Yes      | -                         | Path to the configuration file                                                                            |
| `version`     | No       | `v0`                      | Schema version to validate against                                                                        |
| `schema-file` | No       | `leap-deploy.schema.json` | Schema filename to validate against (e.g., `leap-deploy.schema.json` or `leap-deploy-folded.schema.json`) |

## Usage

### Basic Validation

```yaml
- name: Validate deployment configuration
  uses: workleap/wl-leap-deploy/.github/actions/validate@main
  with:
    file-path: ./devops/leap-deploy.yaml
```

### In a CI Workflow

```yaml
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Validate leap-deploy.yaml
        uses: workleap/wl-leap-deploy/.github/actions/validate@main
        with:
          file-path: devops/leap-deploy.yaml
```

### Validating Folded Configuration

```yaml
- name: Validate folded configuration
  uses: workleap/wl-leap-deploy/.github/actions/validate@main
  with:
    file-path: /tmp/folded-config.json
    schema-file: leap-deploy-folded.schema.json
```

## What Gets Validated

The action validates the following aspects of your `leap-deploy.yaml`:

- Required fields (`id`, `workloads`)
- Workload configurations (type, image, resources)
- Environment and region-specific settings
- Ingress and network configurations
- Proper structure and data types

See [examples/leap-deploy.yaml](./schemas/v0/examples/leap-deploy.yaml) for a complete configuration example.

For detailed validation rules, refer to the [leap-deploy.schema.json](./schemas/v0/leap-deploy.schema.json) JSON Schema definition.

## Troubleshooting

**Validation fails with schema errors:**

- Check that all required fields are present
- Verify data types match the schema (strings, numbers, objects)
- Review the error output for specific field paths that failed validation
- Compare your configuration against the example file

**Path issues in containers:**

- If running in a container, ensure `file-path` is relative to the workspace root
- The action automatically resolves schema paths using `github.action_path`
