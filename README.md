# Leap Deploy

A declarative deployment configuration system for managing workloads across multiple environments and regions.

## Overview

Leap Deploy provides a JSON schema-based configuration format that allows you to define deployment specifications for your applications in a structured, validated way. The schema supports:

- Multiple workload types (APIs, workers)
- Environment-specific overrides
- Region-specific configurations
- Resource management (CPU, memory)
- Autoscaling configuration
- Container image specifications
- Ingress routing

## Using the Schema in Your Configuration Files

To enable IDE autocomplete, validation, and documentation while editing your configuration files, reference the schema using one of the following methods:

### For JSON Files

Add a `$schema` property at the top of your `leap-deploy.json`:

```json
{
  "$schema": "https://github.com/workleap/wl-leap-deploy/releases/latest/download/leap-deploy.v1.schema.json",
  "version": "1.0.0",
  "id": "my-application",
  "workloads": {
    "api-service": {
      "type": "api",
      "replicas": 3,
      "image": {
        "registry": "myregistry.azurecr.io",
        "repository": "my-app/api",
        "tag": "1.2.3"
      },
      "ingress": {
        "pathPrefix": "/api",
        "fqdn": "api.example.com"
      }
    }
  }
}
```

### For YAML Files

Add a YAML language server directive as the first line of your `leap-deploy.yaml`:

```yaml
# yaml-language-server: $schema=https://github.com/workleap/wl-leap-deploy/releases/latest/download/leap-deploy.v1.schema.json

version: "1.0.0"
id: my-application
workloads:
  api-service:
    type: api
    replicas: 3
    image:
      registry: myregistry.azurecr.io
      repository: my-app/api
      tag: 1.2.3
    ingress:
      pathPrefix: /api
      fqdn: api.example.com
```

### IDE Setup

#### VS Code
- **JSON**: Automatically recognizes the `$schema` property (no setup needed)
- **YAML**: Install the [YAML extension by Red Hat](https://marketplace.visualstudio.com/items?itemName=redhat.vscode-yaml)

#### JetBrains IDEs
- **JSON**: Automatically recognizes the `$schema` property (no setup needed)
- **YAML**: Recognizes the `# yaml-language-server: $schema=` directive automatically

### Alternative: Workspace Configuration

You can also configure schema mappings in your workspace settings (VS Code `.vscode/settings.json`):

```json
{
  "json.schemas": [
    {
      "fileMatch": ["**/leap-deploy.json"],
      "url": "https://github.com/workleap/wl-leap-deploy/releases/latest/download/leap-deploy.v1.schema.json"
    }
  ],
  "yaml.schemas": {
    "https://github.com/workleap/wl-leap-deploy/releases/latest/download/leap-deploy.v1.schema.json": "**/leap-deploy.yaml"
  }
}
```

## Configuration Structure

### Required Fields

Every configuration file must include:

- `version`: Schema version (e.g., `"1.0.0"`, `"1.0"`, or `"1"`)
- `id`: Unique identifier for the deployment configuration
- `workloads`: Map of workload names to their configurations

### Workload Configuration

Each workload supports:

```yaml
workload-name:
  type: api | worker                    # Required: workload type
  replicas: 3                            # Number of replicas
  annotations: {}                        # Kubernetes annotations
  labels: {}                             # Kubernetes labels
  
  image:                                 # Container image configuration
    registry: myregistry.azurecr.io
    repository: my-app/service
    tag: 1.2.3
  
  resources:                             # Resource requests
    requests:
      cpu: "500m"
      memory: "512Mi"
  
  autoscaling:                           # Autoscaling configuration
    horizontal:
      enabled: true
      minReplicas: 2
      maxReplicas: 10
    vertical:
      enabled: false
  
  ingress:                               # Ingress configuration (for APIs)
    pathPrefix: /api
    fqdn: api.example.com
  
  regions:                               # Region-specific overrides
    na:
      replicas: 5
      ingress:
        fqdn: api-na.example.com
    eu:
      replicas: 3
      ingress:
        fqdn: api-eu.example.com
  
  environments:                          # Environment-specific overrides
    dev:
      replicas: 1
    prod:
      replicas: 5
```

## Reusable GitHub Actions

This repository provides several reusable GitHub Actions for working with `leap-deploy.yaml` files:

- **[validate](.github/actions/validate/README.md)** - Validates `leap-deploy.yaml` against the predefined schema to ensure correctness
- **[fold-config](.github/actions/fold-config/README.md)** - Folds configuration by merging workload configs for a specific environment and region
- **[generate-chart](.github/actions/generate-chart/README.md)** - Generates a Helm chart based on the folded configuration

## Examples

See [./schemas/v0/examples/leap-deploy.yaml](./schemas/v0/examples/leap-deploy.yaml) for complete configuration examples.

## Schema Versions

This project uses semantic versioning for schemas. Schema files are organized in the `schemas/` directory:

- **v1.x.x**: Current stable version (`schemas/v1/`)
  - Schema URL: `https://github.com/workleap/wl-leap-deploy/releases/latest/download/leap-deploy.v1.schema.json`
  - All v1.x.x versions are backward compatible with v1.0.0

When v2 is released, the schema will be in `schemas/v2/` and accessible via:
- `https://github.com/workleap/wl-leap-deploy/releases/latest/download/leap-deploy.v2.schema.json`

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines and versioning strategy.

## License

This project is licensed under the terms of the Apache License 2.0. See the [LICENSE](LICENSE) file for details.
