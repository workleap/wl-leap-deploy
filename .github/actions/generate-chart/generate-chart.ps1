#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Generates Helm Chart.yaml and values.yaml files based on folded leap-deploy configuration.

.DESCRIPTION
    Takes the folded configuration JSON and repository variables to generate:
    - A Helm Chart.yaml file with dependencies for each workload
    - A values.yaml file with configuration values for each workload subchart

.PARAMETER ChartRepositoryName
    The OCI Helm chart repository URL for the leap-app chart.

.PARAMETER ChartName
    The name of the leap-app Helm chart to use.

.PARAMETER ChartVersion
    The version of the leap-app chart to use.

.PARAMETER ProductName
    The product name. Used for referencing the workload identity service account.

.PARAMETER FoldedConfigJson
    The folded configuration JSON string containing workload definitions.

.PARAMETER InfraConfigJson
    The infrastructure configuration JSON string.

.PARAMETER OutputDirectory
    The directory where the generated files will be written. If the directory does not exist, it will be created.
    Defaults to ".generated" if not specified.

.EXAMPLE
    ./generate-chart.ps1 'oci://infra0prod0global0registry0acr0ea18c271c312.azurecr.io/helm' 'leap-app' '0.1.2' foobar '{"workloads": {...}}' '{}' ./output
#>

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$ChartRegistry,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$ChartName,

    [Parameter(Mandatory = $true, Position = 2)]
    [string]$ChartVersion,

    [Parameter(Mandatory = $true, Position = 3)]
    [string]$ProductName,

    [Parameter(Mandatory = $true, Position = 4)]
    [string]$FoldedConfigJson,

    [Parameter(Mandatory = $true, Position = 5)]
    [string]$infraConfigJson,

    [Parameter(Mandatory = $false, Position = 6)]
    [string]$OutputDirectory = ".generated"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Module version constants
$POWERSHELL_YAML_VERSION = "0.4.12"

# Workleap label and annotation constants
$LABEL_WORKLEAP_TYPE = "app.workleap.com/type"
$LABEL_WORKLEAP_PRODUCT = "app.workleap.com/product"
$ANNOTATION_WORKLEAP_REPO = "apps.workleap.com/repo"

try {
    # Ensure powershell-yaml module is available
    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        Write-Host "Installing powershell-yaml module..."
        Install-Module -Name powershell-yaml -RequiredVersion $POWERSHELL_YAML_VERSION -Force -Scope CurrentUser -Repository PSGallery
    }
    Import-Module powershell-yaml

    # Helper function to get JSON content (from string or file)
    function Get-JsonContent {
        param([string]$JsonInput)
        
        # Check if input looks like a file path
        if (Test-Path $JsonInput -PathType Leaf) {
            return Get-Content $JsonInput -Raw | ConvertFrom-Json
        } else {
            return $JsonInput | ConvertFrom-Json
        }
    }

    # Parse the folded config JSON
    $foldedConfig = Get-JsonContent $FoldedConfigJson
    
    # Parse the infra config JSON
    $infraConfig = Get-JsonContent $infraConfigJson

    # Get ACR registry name from variables
    $acrRegistryName = $null
    if ($infraConfig.PSObject.Properties['acr_registry_name']) {
        $acrRegistryName = $infraConfig.acr_registry_name
        Write-Host "Found ACR registry name: $acrRegistryName"
    } else {
        Write-Warning "acr_registry_name not found in infra config JSON"
        Write-Host "infraConfig content: $($infraConfig | ConvertTo-Json -Depth 10)"
    }

    # Use the provided chart configuration parameters
    Write-Host "Using as workload chart: ${ChartRegistry}/${ChartName}:${ChartVersion}"
    # Validate that workloads exist
    if (-not $foldedConfig.PSObject.Properties['workloads']) {
        Write-Error "Folded config must contain 'workloads' property"
        exit 1
    }

    # Get workload names sorted for consistent output
    $workloadNames = $foldedConfig.workloads.PSObject.Properties | Select-Object -ExpandProperty Name | Sort-Object

    # Build Chart.yaml as PSCustomObject
    $dependencies = @()
    foreach ($workloadName in $workloadNames) {
        $dependencies += [PSCustomObject]@{
            name       = $ChartName
            version    = $ChartVersion
            repository = $ChartRegistry
            alias      = $workloadName
        }
    }

    $chartObject = [PSCustomObject]@{
        apiVersion   = "v2"
        name         = "leap-deploy.generated"
        description  = "Leap Deploy Generated Chart"
        version      = "1.0.0"
        dependencies = $dependencies
    }

    # Create output directory structure
    $templatesDir = Join-Path $OutputDirectory "templates"
    
    if (-not (Test-Path $OutputDirectory)) {
        Write-Host "Creating output directory: $OutputDirectory"
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }
    
    if (-not (Test-Path $templatesDir)) {
        New-Item -ItemType Directory -Path $templatesDir -Force | Out-Null
        # Create a placeholder file in templates directory
        Set-Content -Path (Join-Path $templatesDir ".gitkeep") -Value "# Placeholder for generated templates"
    }

    # Write the generated Chart.yaml content to output directory
    $chartOutputPath = Join-Path $OutputDirectory "Chart.yaml"
    $chartYaml = ConvertTo-Yaml $chartObject
    Set-Content -Path $chartOutputPath -Value $chartYaml
    Write-Host "Generated Chart.yaml written to: $chartOutputPath"

    # Generate values.yaml content
    # Get GitHub repository URL from environment variables
    $githubServerUrl = $env:GITHUB_SERVER_URL
    $githubRepository = $env:GITHUB_REPOSITORY
    $repoUrl = $null
    
    if ($githubServerUrl -and $githubRepository) {
        $repoUrl = "$githubServerUrl/$githubRepository"
    } else {
        Write-Warning "GITHUB_SERVER_URL and/or GITHUB_REPOSITORY environment variables are not set. Repository annotation will be omitted."
    }

    # Build values.yaml as PSCustomObject
    $valuesObject = [PSCustomObject]@{}
    
    foreach ($workloadName in $workloadNames) {
        $workload = $foldedConfig.workloads.$workloadName
        
        # Determine the registry and repository separately
        $imageRegistry = if ($acrRegistryName) { "$acrRegistryName.azurecr.io" } else { $null }
        $imageRepository = $workload.image.repository
        
        # Build image configuration
        $imageConfig = [PSCustomObject]@{
            repository = $imageRepository
            tag        = $workload.image.tag
        }
        
        # Add registry field if available
        if ($imageRegistry) {
            $imageConfig = [PSCustomObject]@{
                registry   = $imageRegistry
                repository = $imageRepository
                tag        = $workload.image.tag
            }
        }

        # Ingress
        $ingressConfig = [PSCustomObject]@{
            create = $false
        }

        if ($workload.PSObject.Properties['ingress']) {
            $ingressConfig = [PSCustomObject]@{
                create     = $true
                hostname    = $workload.ingress.fqdn
                path        = $workload.ingress.pathPrefix
            }
        }

        $serviceAccountConfig = [PSCustomObject]@{
            create = $false
            name = "workload-identity-$ProductName"
        }

        # Build commonLabels (merge workload type with custom labels)
        $commonLabels = [PSCustomObject]@{
            $LABEL_WORKLEAP_TYPE = $workload.type
            $LABEL_WORKLEAP_PRODUCT = $ProductName
        }
        if ($workload.PSObject.Properties['labels']) {
            foreach ($label in $workload.labels.PSObject.Properties) {
                $commonLabels | Add-Member -NotePropertyName $label.Name -NotePropertyValue $label.Value -Force
            }
        }

        # Build commonAnnotations (merge repo URL with custom annotations)
        $commonAnnotations = [PSCustomObject]@{}
        if ($repoUrl) {
            $commonAnnotations | Add-Member -NotePropertyName $ANNOTATION_WORKLEAP_REPO -NotePropertyValue $repoUrl
        }
        if ($workload.PSObject.Properties['annotations']) {
            foreach ($annotation in $workload.annotations.PSObject.Properties) {
                $commonAnnotations | Add-Member -NotePropertyName $annotation.Name -NotePropertyValue $annotation.Value
            }
        }
        
        # Build workload configuration
        $workloadConfig = [PSCustomObject]@{
            nameOverride = $workload.type
            commonLabels = $commonLabels
            image = $imageConfig
            ingress = $ingressConfig
            serviceAccount = $serviceAccountConfig
        }
        
        # Add commonAnnotations if there are any
        if (($commonAnnotations.PSObject.Properties | Measure-Object).Count -gt 0) {
            $workloadConfig | Add-Member -NotePropertyName commonAnnotations -NotePropertyValue $commonAnnotations
        }

        # Add replicaCount if specified
        if ($workload.PSObject.Properties['replicas']) {
            $workloadConfig | Add-Member -NotePropertyName replicaCount -NotePropertyValue $workload.replicas
        }

        # Add resources if specified
        if ($workload.PSObject.Properties['resources']) {
            $workloadConfig | Add-Member -NotePropertyName resources -NotePropertyValue $workload.resources
        }

        # Add autoscaling configuration if specified
        if ($workload.PSObject.Properties['autoscaling']) {
            $autoscalingConfig = [PSCustomObject]@{
                enabled = $false
            }

            # Handle horizontal autoscaling
            if ($workload.autoscaling.PSObject.Properties['horizontal'] -and $workload.autoscaling.horizontal.enable) {
                $autoscalingConfig.enabled = $true
                
                if ($workload.autoscaling.horizontal.PSObject.Properties['minReplicas']) {
                    $autoscalingConfig | Add-Member -NotePropertyName minReplicas -NotePropertyValue $workload.autoscaling.horizontal.minReplicas
                }
                
                if ($workload.autoscaling.horizontal.PSObject.Properties['maxReplicas']) {
                    $autoscalingConfig | Add-Member -NotePropertyName maxReplicas -NotePropertyValue $workload.autoscaling.horizontal.maxReplicas
                }
            }

            $workloadConfig | Add-Member -NotePropertyName autoscaling -NotePropertyValue $autoscalingConfig
        }
        
        # Add workload to values object
        $valuesObject | Add-Member -NotePropertyName $workloadName -NotePropertyValue $workloadConfig
    }

    # Write values.yaml to output directory
    $valuesOutputPath = Join-Path $OutputDirectory "values.yaml"
    $valuesYaml = ConvertTo-Yaml $valuesObject
    Set-Content -Path $valuesOutputPath -Value $valuesYaml
    Write-Host "Generated values.yaml written to: $valuesOutputPath"

} catch {
    Write-Error "Failed to generate Chart.yaml: $_"
    exit 1
}
