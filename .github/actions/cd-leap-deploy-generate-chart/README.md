# Leap Deploy Generate Chart

**Action Path:** `.github/actions/cd-leap-deploy-generate-chart`

Generates a Helm chart (Chart.yaml and values.yaml) from a folded leap-deploy configuration, enabling atomic deployment of multiple workloads to Kubernetes. The generated chart creates a dependency on the [LeapApp Helm Chart](https://github.com/workleap/wl-leap-controller/tree/main/charts/leap-app) for each workload, designed to work with the [Kubernetes Leap Controller](https://github.com/workleap/wl-leap-controller/).

## Features

- **Helm Chart Generation**: Creates a complete Helm chart structure with LeapApp subchart dependencies for each workload
- **LeapApp Integration**: Generated values.yaml conforms to the [LeapApp Helm Chart schema](https://github.com/workleap/wl-leap-controller/tree/main/charts/leap-app)
- **Values Transformation**: Converts folded configuration into Helm-compatible values.yaml
- **Multi-Workload Support**: Generates subcharts for each workload (APIs, workers) defined in the configuration
- **Infrastructure Integration**: Incorporates infrastructure details (ACR registry, AKS cluster info) into chart values
- **Atomic Deployment**: Enables deploying all workloads together as a single Helm release

## Inputs

| Input                | Required | Default | Description                                                                    |
| -------------------- | -------- | ------- | ------------------------------------------------------------------------------ |
| `chart-registry`     | Yes      | -       | The Azure Container Registry address containing the chart to use for workloads |
| `chart-name`         | Yes      | -       | The name of the chart to use for workloads                                     |
| `chart-version`      | Yes      | -       | The version of the chart to use for workloads                                  |
| `product-name`       | Yes      | -       | The product name                                                               |
| `leap-deploy-config` | Yes      | -       | The folded Leap Deploy configuration for the target environment/region         |
| `infra-config`       | Yes      | -       | Infra config for the target environment                                        |

## Outputs

| Output            | Description                                                                  |
| ----------------- | ---------------------------------------------------------------------------- |
| `chart-directory` | The directory path containing the generated Chart.yaml and values.yaml files |

## Usage

### Basic Chart Generation

```yaml
- name: Generate Helm chart
  id: generate-chart
  uses: workleap/wl-leap-deploy/.github/actions/cd-leap-deploy-generate-chart@main
  with:
    chart-registry: myregistry.azurecr.io
    chart-name: leap-app
    chart-version: 0.1.2
    product-name: my-product
    leap-deploy-config: ${{ steps.fold.outputs.folded-config }}
    infra-config: ${{ steps.infra.outputs.environment-config }}

- name: View generated chart
  run: |
    ls -la ${{ steps.generate-chart.outputs.chart-directory }}
    cat ${{ steps.generate-chart.outputs.chart-directory }}/Chart.yaml
    cat ${{ steps.generate-chart.outputs.chart-directory }}/values.yaml
```

### Complete Deployment Pipeline

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Get infrastructure config
        id: infra
        uses: workleap/wl-leap-deploy/.github/actions/tools-get-infra-config@main
        with:
          variables: ${{ toJSON(vars) }}
          environment: dev
          region: na

      - name: Fold leap-deploy configuration
        id: fold
        uses: workleap/wl-leap-deploy/.github/actions/cd-leap-deploy-fold-config@main
        with:
          file-path: devops/leap-deploy.yaml
          environment: dev
          region: na

      - name: Generate Helm chart
        id: generate
        uses: workleap/wl-leap-deploy/.github/actions/cd-leap-deploy-generate-chart@main
        with:
          chart-registry: ${{ vars.CHART_REGISTRY }}
          chart-name: ${{ vars.CHART_NAME }}
          chart-version: 0.1.2
          product-name: ${{ vars.PRODUCT_NAME }}
          leap-deploy-config: ${{ steps.fold.outputs.folded-config }}
          infra-config: ${{ steps.infra.outputs.environment-config }}

      - name: Deploy with Helm
        run: |
          helm upgrade --install my-release \
            ${{ steps.generate.outputs.chart-directory }} \
            --namespace my-namespace \
            --create-namespace \
            --wait
```

### Using Generated Chart in Subsequent Jobs

```yaml
jobs:
  generate:
    runs-on: ubuntu-latest
    outputs:
      chart-path: ${{ steps.generate.outputs.chart-directory }}
    steps:
      - name: Generate chart
        id: generate
        uses: workleap/wl-leap-deploy/.github/actions/cd-leap-deploy-generate-chart@main
        with:
          chart-registry: ${{ vars.CHART_REGISTRY }}
          chart-name: ${{ vars.CHART_NAME }}
          chart-version: 0.1.2
          product-name: my-product
          leap-deploy-config: ${{ steps.fold.outputs.folded-config }}
          infra-config: ${{ steps.infra.outputs.environment-config }}

      - name: Upload chart artifact
        uses: actions/upload-artifact@v4
        with:
          name: helm-chart
          path: ${{ steps.generate.outputs.chart-directory }}

  deploy:
    needs: generate
    runs-on: ubuntu-latest
    steps:
      - name: Download chart
        uses: actions/download-artifact@v4
        with:
          name: helm-chart
          path: ./chart

      - name: Deploy
        run: helm upgrade --install my-release ./chart
```

## Generated Chart Structure

The action generates a Helm chart with the following structure:

```
chart-directory/
├── Chart.yaml          # Helm chart metadata with LeapApp subchart dependencies
└── values.yaml         # Values conforming to LeapApp chart schema
```

### How It Works

The generated chart creates a dependency on the [LeapApp Helm Chart](https://github.com/workleap/wl-leap-controller/tree/main/charts/leap-app) for each workload defined in your leap-deploy configuration. The LeapApp chart is managed by the [Kubernetes Leap Controller](https://github.com/workleap/wl-leap-controller/), which orchestrates workload deployments in your cluster.

Each workload becomes a subchart with values that conform to the LeapApp chart's schema, ensuring compatibility with the Leap Controller.

### Chart.yaml Example

```yaml
apiVersion: v2
name: my-product
version: 1.0.0
dependencies:
  - name: api-workload
    repository: oci://ghcr.io/workleap/charts
    version: 1.0.0
    alias: leap-app-api
  - name: worker-workload
    repository: oci://ghcr.io/workleap/charts
    version: 1.0.0
    alias: leap-app-worker
```

### values.yaml Example

```yaml
api-workload:
  image:
    registry: myregistry.azurecr.io
    repository: my-app-api
    tag: v1.2.3
  replicas: 3
  resources:
    requests:
      cpu: 200m
      memory: 256Mi
  ingress:
    enabled: true
    fqdn: api.example.com
    pathPrefix: /api

worker-workload:
  image:
    registry: myregistry.azurecr.io
    repository: my-app-worker
    tag: v1.2.3
  replicas: 2
```

## Input Requirements

### leap-deploy-config Format

Must be a folded configuration JSON (output from cd-leap-deploy-fold-config):

```json
{
  "id": "my-app",
  "workloads": {
    "api": {
      "type": "api",
      "image": { "repository": "my-app", "tag": "v1.0.0" },
      "replicas": 3,
      "resources": { "requests": { "cpu": "200m", "memory": "256Mi" } }
    }
  }
}
```

### infra-config Format

Must contain infrastructure details (output from tools-get-infra-config):

```json
{
  "acr_registry_name": "myregistry",
  "aks": {
    "default": {
      "cluster_name": "my-aks-cluster",
      "resource_group_name": "my-rg"
    }
  }
}
```

## Troubleshooting

**Missing ACR registry name:**

- Ensure `infra-config` contains `acr_registry_name` property
- Verify the infrastructure configuration was generated correctly
- Check that the tools-get-infra-config action ran successfully

**PowerShell module errors:**

- The action automatically installs the `powershell-yaml` module if needed
- Ensure the runner has internet access to download PowerShell modules

**Invalid JSON inputs:**

- Verify that `leap-deploy-config` is valid JSON (use `jq` to validate)
- Ensure `infra-config` is properly formatted JSON
- Check that both inputs contain all required fields

**Chart directory not found:**

- The action creates a temporary directory for the chart
- Access the chart immediately after generation or upload as an artifact
- The directory path is available via `chart-directory` output
