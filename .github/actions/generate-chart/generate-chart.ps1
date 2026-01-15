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

# ========================================
# Module Installation and Import
# ========================================
try {
    # Ensure powershell-yaml module is available
    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        Write-Host "Installing powershell-yaml module..."
        Install-Module -Name powershell-yaml -RequiredVersion $POWERSHELL_YAML_VERSION -Force -Scope CurrentUser -Repository PSGallery
    }
    Import-Module powershell-yaml
} catch {
    Write-Error "Failed to install or import required PowerShell modules: $_"
    exit 1
}

# ========================================
# Helper Functions
# ========================================

# Helper function to get JSON content (from string or file)
function Get-JsonContent {
    param([string]$JsonInput)
    
    if ([string]::IsNullOrWhiteSpace($JsonInput)) {
        throw "JSON input is null or empty"
    }
    
    # Check if input looks like a file path
    if (Test-Path $JsonInput -PathType Leaf) {
        $content = Get-Content $JsonInput -Raw
        return $content | ConvertFrom-Json
    } else {
        return $JsonInput | ConvertFrom-Json
    }
}

# Function to build LeapApp labels from workload config and input parameters
function Get-LeapAppLabels {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Workload
    )
    
    if (-not $Workload) {
        throw "Workload parameter cannot be null"
    }
    
    if (-not $Workload.PSObject.Properties['type']) {
        throw "Workload must have a 'type' property"
    }
    
    # Build LeapApps labels. Those will be set on the LeapApp metadata
    $leapAppsLabels = [PSCustomObject]@{}

    $LABEL_WORKLEAP_TYPE = "apps.workleap.com/type"
    $LABEL_WORKLEAP_PRODUCT = "apps.workleap.com/product"

    # Add type and product labels
    $leapAppsLabels | Add-Member -NotePropertyName $LABEL_WORKLEAP_TYPE -NotePropertyValue $workload.type
    $leapAppsLabels | Add-Member -NotePropertyName $LABEL_WORKLEAP_PRODUCT -NotePropertyValue $ProductName

    return $leapAppsLabels
}

# Function to build LeapApp annotations from environment variables and input parameters
function Get-LeapAppAnnotations {
    # Build LeapApps annotations. Those will be set on the LeapApp metadata
    $leapAppsAnnotations = [PSCustomObject]@{}

    $ANNOTATION_WORKLEAP_CHART = "apps.workleap.com/chart"

    $ANNOTATION_GITHUB_REPO = "workleap.github.com/repo"
    $ANNOTATION_GITHUB_RUN_ID = "workleap.github.com/run-id"
    $ANNOTATION_GITHUB_WORKFLOW_REF = "workleap.github.com/workflow"
    $ANNOTATION_GITHUB_SHA = "workleap.github.com/commit-sha"
    $ANNOTATION_GITHUB_ACTOR = "workleap.github.com/actor"

    # Chart reference annotation
    $leapAppsAnnotations | Add-Member -NotePropertyName $ANNOTATION_WORKLEAP_CHART -NotePropertyValue "${ChartName}:${ChartVersion}"

    # GitHub annotations
    $githubServerUrl = $env:GITHUB_SERVER_URL
    if (-not $githubServerUrl) {
        Write-Warning "GITHUB_SERVER_URL environment variable is not set. Repository annotation will be omitted."
    }
    
    $githubRepository = $env:GITHUB_REPOSITORY
    if (-not $githubRepository) {
        Write-Warning "GITHUB_REPOSITORY environment variable is not set. Repository annotation will be omitted."
    }
        
    $repoUrl = $null
    if ($githubServerUrl -and $githubRepository) {
        $repoUrl = "$githubServerUrl/$githubRepository"
    }

    if ($repoUrl) {
        $leapAppsAnnotations | Add-Member -NotePropertyName $ANNOTATION_GITHUB_REPO -NotePropertyValue $repoUrl
    }

    $githubRunId = $env:GITHUB_RUN_ID
    if (-not $githubRunId) {
        Write-Warning "GITHUB_RUN_ID environment variable is not set. Run ID annotation will be omitted."
    } else {
        $leapAppsAnnotations | Add-Member -NotePropertyName $ANNOTATION_GITHUB_RUN_ID -NotePropertyValue $githubRunId
    }

    $githubWorkflowRef = $env:GITHUB_WORKFLOW
    if (-not $githubWorkflowRef) {
        Write-Warning "GITHUB_WORKFLOW environment variable is not set. Workflow ref annotation will be omitted."
    } else {
        $leapAppsAnnotations | Add-Member -NotePropertyName $ANNOTATION_GITHUB_WORKFLOW_REF -NotePropertyValue $githubWorkflowRef
    }

    $githubCommitSha = $env:GITHUB_SHA
    if (-not $githubCommitSha) {
        Write-Warning "GITHUB_SHA environment variable is not set. Commit SHA annotation will be omitted."
    } else {
        $leapAppsAnnotations | Add-Member -NotePropertyName $ANNOTATION_GITHUB_SHA -NotePropertyValue $githubCommitSha
    }

    $githubActor = $env:GITHUB_ACTOR
    if (-not $githubActor) {
        Write-Warning "GITHUB_ACTOR environment variable is not set. Actor annotation will be omitted."
    } else {
        $leapAppsAnnotations | Add-Member -NotePropertyName $ANNOTATION_GITHUB_ACTOR -NotePropertyValue $githubActor
    }

    return $leapAppsAnnotations
}

# Functions which creates an Helm Chart for the leap-deploy folded config - Generates one LeapApp sub-chart dependency per workload
function New-LeapDeployChart {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$WorkloadNames,
        
        [Parameter(Mandatory = $true)]
        [string]$ChartName,
        
        [Parameter(Mandatory = $true)]
        [string]$ChartVersion,
        
        [Parameter(Mandatory = $true)]
        [string]$ChartRegistry
    )

    if ($WorkloadNames.Count -eq 0) {
        throw "WorkloadNames array cannot be empty"
    }

    # Build Chart.yaml as PSCustomObject
    $dependencies = @()
    foreach ($workloadName in $WorkloadNames) {
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

    return $chartObject
}

# Function to generate LeapApp chart values from workload config
function GenerateLeapAppChartValuesFromWorkloadConfig {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Workload,
        
        [Parameter(Mandatory = $true)]
        [string]$AcrRegistryName,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Labels,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Annotations
    )

    if (-not $Workload) {
        throw "Workload parameter cannot be null"
    }

    # Build LeapApp chart's values
    $leapAppChartValues = [PSCustomObject]@{
        #fullNameOveride = ...
        commonLabels = $Labels
        commonAnnotations = $Annotations
        # Leap-Deploy WorkloadConfig values
        workloadConfig = $Workload
    }
    
    return $leapAppChartValues
}

# ========================================
# Main Script Execution
# ========================================

# Parse and validate JSON inputs
try {
    Write-Host "Parsing configuration inputs..."
    $foldedConfig = Get-JsonContent $FoldedConfigJson
    $infraConfig = Get-JsonContent $infraConfigJson
    Write-Host "Configuration inputs parsed successfully."
} catch {
    Write-Error "Failed to parse JSON configuration: $_"
    exit 1
}

# Validate configuration structure
try {
    Write-Host "Validating configuration structure..."
    
    # Validate that workloads exist
    if (-not $foldedConfig.PSObject.Properties['workloads']) {
        throw "Folded config must contain 'workloads' property"
    }
    
    # Get workload names sorted for consistent output
    $workloadNames = $foldedConfig.workloads.PSObject.Properties | Select-Object -ExpandProperty Name | Sort-Object
    
    if ($workloadNames.Count -eq 0) {
        throw "Folded config must contain at least one workload"
    }
    
    Write-Host "Found $($workloadNames.Count) workload(s): $($workloadNames -join ', ')"
    
    # Get ACR registry name from the infra config's content
    $acrRegistryName = $null
    if ($infraConfig.PSObject.Properties['acr_registry_name']) {
        $acrRegistryName = $infraConfig.acr_registry_name
        Write-Host "Found ACR registry name: $acrRegistryName"
    } else {
        Write-Warning "acr_registry_name not found in infra config JSON. ACR registry name will be null."
    }
    
    Write-Host "Configuration validation completed successfully."
} catch {
    Write-Error "Configuration validation failed: $_"
    exit 1
}

# Generate Chart.yaml
try {
    Write-Host "Generating Chart.yaml..."
    Write-Host "Using ${ChartRegistry}/${ChartName}:${ChartVersion} for each workload..."
    
    # Build Chart.yaml object
    $chartObject = New-LeapDeployChart `
        -WorkloadNames $workloadNames `
        -ChartName $ChartName `
        -ChartVersion $ChartVersion `
        -ChartRegistry $ChartRegistry
    
    Write-Host "Chart.yaml object created successfully."
} catch {
    Write-Error "Failed to generate Chart.yaml object: $_"
    exit 1
}

# Generate values.yaml
try {
    Write-Host "Generating values.yaml..."
    
    # Build values.yaml as PSCustomObject
    $valuesObject = [PSCustomObject]@{}
    
    # Add each workload's values under its alias
    foreach ($workloadName in $workloadNames) {
        Write-Host "  Processing workload: $workloadName"
        
        # Each workload matches a subchart alias with its own set of values
        $workload = $foldedConfig.workloads.$workloadName
        
        if (-not $workload) {
            throw "Workload '$workloadName' not found in folded config"
        }

        $annotations = Get-LeapAppAnnotations
        $labels = Get-LeapAppLabels -Workload $workload
        
        # Generate this sub chart values from the workload config
        $workloadConfig = GenerateLeapAppChartValuesFromWorkloadConfig `
            -Workload $workload `
            -AcrRegistryName $acrRegistryName `
            -Labels $labels `
            -Annotations $annotations
        
        # Add workload to values object
        $valuesObject | Add-Member -NotePropertyName $workloadName -NotePropertyValue $workloadConfig
    }
    
    Write-Host "values.yaml object created successfully."
} catch {
    Write-Error "Failed to generate values.yaml object: $_"
    exit 1
}

# Write generated files to disk
try {
    Write-Host "Writing generated files to disk..."
    
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

    # Write values.yaml to output directory
    $valuesOutputPath = Join-Path $OutputDirectory "values.yaml"
    $valuesYaml = ConvertTo-Yaml $valuesObject
    Set-Content -Path $valuesOutputPath -Value $valuesYaml
    Write-Host "Generated values.yaml written to: $valuesOutputPath"
    
    Write-Host "All files written successfully."
} catch {
    Write-Error "Failed to write generated files to disk: $_"
    exit 1
}

Write-Host "Chart generation completed successfully!"
