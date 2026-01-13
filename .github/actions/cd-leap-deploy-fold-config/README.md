# Leap Deploy Fold Config

**Action Path:** `.github/actions/cd-leap-deploy-fold-config`

Processes `leap-deploy.yaml` configuration files by merging defaults, workload settings, environment overrides, and region-specific configurations into complete deployment configurations for a target environment and region.

## Features

- **Configuration Folding**: Merges layered configuration (defaults → workload → environment → region) following precedence rules
- **Automatic Validation**: Validates configuration schema before processing
- **Source Tracking**: Provides visibility into which configuration layer provided each value
- **JSON Output**: Returns folded configuration in compact JSON format for downstream consumption

## Inputs

| Input         | Required | Default | Description                                                                             |
| ------------- | -------- | ------- | --------------------------------------------------------------------------------------- |
| `file-path`   | Yes      | -       | Path to the `leap-deploy.yaml` configuration file                                       |
| `environment` | Yes      | -       | Target environment (dev, staging, prod)                                                 |
| `region`      | No       | `""`    | Target region (na, eu, etc.). Optional if workload has no region-specific configuration |

## Outputs

| Output                  | Description                                                                       |
| ----------------------- | --------------------------------------------------------------------------------- |
| `folded-config`         | The folded configuration in compact JSON format with metadata keys filtered out   |
| `folded-config-sources` | The folded configuration formatted to show the source of each value for debugging |

## Usage

### Basic Configuration Folding

```yaml
- name: Fold deployment configuration
  id: fold
  uses: workleap/wl-github-actions/.github/actions/cd-leap-deploy-fold-config@main
  with:
    file-path: ./devops/leap-deploy.yaml
    environment: dev
    region: na

- name: Use folded configuration
  run: |
    echo "Configuration: ${{ steps.fold.outputs.folded-config }}"
```

### Multi-Region Deployment

```yaml
jobs:
  prepare:
    runs-on: ubuntu-latest
    outputs:
      folded-config: ${{ steps.fold.outputs.folded-config }}
    steps:
      - uses: actions/checkout@v4

      - name: Fold configuration for production
        id: fold
        uses: workleap/wl-github-actions/.github/actions/cd-leap-deploy-fold-config@main
        with:
          file-path: devops/leap-deploy.yaml
          environment: prod
          region: eu

      - name: Display configuration sources
        run: |
          echo "Configuration sources:"
          echo "${{ steps.fold.outputs.folded-config-sources }}"

  deploy:
    needs: prepare
    runs-on: ubuntu-latest
    steps:
      - name: Deploy with folded config
        env:
          CONFIG: ${{ needs.prepare.outputs.folded-config }}
        run: |
          echo "$CONFIG" | jq '.workloads'
```

## Configuration Precedence

The action merges configuration layers using the following precedence (highest to lowest):

1. `workloads.<name>.regions.<region>.environments.<env>` - Most specific
2. `workloads.<name>.regions.<region>` - Region-specific settings
3. `workloads.<name>.environments.<env>` - Environment-specific, cross-region
4. `workloads.<name>` - Workload-level settings
5. `defaults` - Global base settings

More specific layers override less specific ones through deep merging.

## Output Format

The `folded-config` output provides a complete configuration for each workload:

```json
{
  "id": "my-app",
  "workloads": {
    "api": {
      "type": "api",
      "replicas": 3,
      "image": {
        "registry": "myregistry.azurecr.io",
        "repository": "my-app",
        "tag": "v1.2.3"
      },
      "resources": {
        "requests": {
          "cpu": "200m",
          "memory": "256Mi"
        }
      }
    }
  }
}
```

The `folded-config-sources` output shows where each value originated for debugging.

## Troubleshooting

**Validation fails before folding:**

- The action automatically validates your configuration first
- Fix any schema validation errors reported
- See the [cd-leap-deploy-validate](cd-leap-deploy-validate.md) action documentation

**Region parameter issues:**

- If your workload has no region-specific configuration, omit the `region` input
- If your workload has region overrides, you must specify a `region`
- Check that the specified region exists in your configuration

**Unexpected merged values:**

- Review the `folded-config-sources` output to see which layer provided each value
- Verify your configuration follows the precedence order
- Ensure more specific layers properly override base settings
