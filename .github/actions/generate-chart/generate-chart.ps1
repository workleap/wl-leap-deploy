#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Generates Helm Chart.yaml and values.yaml files based on folded leap-deploy configuration.

.DESCRIPTION
    Takes the folded configuration JSON and other variables to generate:
    - A Helm Chart.yaml file with dependencies for each workload
    - A values.yaml file with configuration values for each workload subchart

.PARAMETER ChartRegistry
    The OCI Helm chart repository URL for the leap-app chart.

.PARAMETER ChartName
    The name of the leap-app Helm chart to use.

.PARAMETER ChartVersion
    The version of the leap-app chart to use.

.PARAMETER ProductName
    The product name. Used for referencing the workload identity service account.

.PARAMETER FoldedConfigJson
    The folded configuration JSON string containing workload definitions.

.PARAMETER Environment
    The environment name (e.g., dev, staging, prod).

.PARAMETER Region
    The Azure region name.

.PARAMETER OutputDirectory
    The directory where the generated files will be written. If the directory does not exist, it will be created.
    Defaults to ".generated" if not specified.

.EXAMPLE
    ./generate-chart.ps1 -ChartRegistry 'oci://infra0prod0global0registry0acr0ea18c271c312.azurecr.io/helm' -ChartName 'leap-app' -ChartVersion '0.1.2' -ProductName 'foobar' -FoldedConfigJson '{"workloads": {...}}' -Environment 'prod' -Region 'eastus' -OutputDirectory './output'
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
    [string]$Environment,

    [Parameter(Mandatory = $false, Position = 6)]
    [string]$Region,

    [Parameter(Mandatory = $false, Position = 7)]
    [string]$OutputDirectory = ".generated"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Module version constants
$POWERSHELL_YAML_VERSION = "0.4.12"

# Label and annotation constants
$ANNOTATION_GITHUB_REPO = "workleap.github.com/repo"
$ANNOTATION_GITHUB_RUN_ID = "workleap.github.com/run-id"
$ANNOTATION_GITHUB_WORKFLOW_REF = "workleap.github.com/workflow"
$ANNOTATION_GITHUB_SHA = "workleap.github.com/commit-sha"
$ANNOTATION_GITHUB_ACTOR = "workleap.github.com/actor"
$ANNOTATION_WORKLEAP_CHART = "apps.workleap.com/chart"
$ANNOTATION_WORKLEAP_GENERATED_BY = "apps.workleap.com/generated-by"

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
    [OutputType([PSCustomObject])]
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

# Helper function to add environment variable as annotation if present
function Add-EnvironmentAnnotation {
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$AnnotationObject,
        
        [Parameter(Mandatory = $true)]
        [string]$AnnotationKey,
        
        [Parameter(Mandatory = $true)]
        [string]$EnvironmentVariableName,
        
        [Parameter(Mandatory = $false)]
        [string]$WarningMessage
    )
    
    $value = [Environment]::GetEnvironmentVariable($EnvironmentVariableName)
    if (-not $value) {
        if ($WarningMessage) {
            Write-Warning $WarningMessage
        } else {
            Write-Warning "$EnvironmentVariableName environment variable is not set. $AnnotationKey annotation will be omitted."
        }
    } else {
        $AnnotationObject | Add-Member -NotePropertyName $AnnotationKey -NotePropertyValue $value
    }
}

# Function to build LeapApp annotations from environment variables and input parameters
function Get-LeapAppAnnotations {
    [OutputType([PSCustomObject])]
    param()
    
    # Build LeapApps annotations. Those will be set on the LeapApp metadata
    $leapAppsAnnotations = [PSCustomObject]@{}

    # Chart reference annotation
    $leapAppsAnnotations | Add-Member -NotePropertyName $ANNOTATION_WORKLEAP_CHART -NotePropertyValue "${ChartName}:${ChartVersion}"
    $leapAppsAnnotations | Add-Member -NotePropertyName $ANNOTATION_WORKLEAP_GENERATED_BY -NotePropertyValue "wl-leap-deploy/${scriptName}@${scriptHash}"

    # GitHub annotations using the helper function
    $githubServerUrl = $env:GITHUB_SERVER_URL
    $githubRepository = $env:GITHUB_REPOSITORY

    if (-not $githubServerUrl -or -not $githubRepository) {
        if (-not $githubServerUrl) {
            Write-Warning "GITHUB_SERVER_URL environment variable is not set. Repository annotation will be omitted."
        }
        
        if (-not $githubRepository) {
            Write-Warning "GITHUB_REPOSITORY environment variable is not set. Repository annotation will be omitted."
        }
    } else {
        $repoUrl = "$githubServerUrl/$githubRepository"
        $leapAppsAnnotations | Add-Member -NotePropertyName $ANNOTATION_GITHUB_REPO -NotePropertyValue $repoUrl
    }

    Add-EnvironmentAnnotation -AnnotationObject $leapAppsAnnotations -AnnotationKey $ANNOTATION_GITHUB_RUN_ID -EnvironmentVariableName 'GITHUB_RUN_ID'
    Add-EnvironmentAnnotation -AnnotationObject $leapAppsAnnotations -AnnotationKey $ANNOTATION_GITHUB_WORKFLOW_REF -EnvironmentVariableName 'GITHUB_WORKFLOW_REF'
    Add-EnvironmentAnnotation -AnnotationObject $leapAppsAnnotations -AnnotationKey $ANNOTATION_GITHUB_SHA -EnvironmentVariableName 'GITHUB_SHA'
    Add-EnvironmentAnnotation -AnnotationObject $leapAppsAnnotations -AnnotationKey $ANNOTATION_GITHUB_ACTOR -EnvironmentVariableName 'GITHUB_ACTOR'

    return $leapAppsAnnotations
}

# Functions which creates an Helm Chart for the leap-deploy folded config - Generates one LeapApp sub-chart dependency per workload
function New-LeapDeployChart {
    [OutputType([PSCustomObject])]
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
function New-LeapAppChartValues {
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Workload,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Annotations,

        [Parameter(Mandatory = $true)]
        [string]$ProductName,

        [Parameter(Mandatory = $true)]
        [string]$Environment,

        [Parameter(Mandatory = $false)]
        [string]$Region
    )

    if (-not $Workload) {
        throw "Workload parameter cannot be null"
    }

    # Build LeapApp chart's values
    $leapAppChartValues = [PSCustomObject]@{
        # fullnameOverride can be added here if needed
        annotations = $Annotations
        product = $ProductName
        environment = $Environment
        # Leap-Deploy WorkloadConfig values
        workloadConfig = $Workload
    }

    if ($Region) {
        $leapAppChartValues | Add-Member -NotePropertyName "region" -NotePropertyValue $Region
    }
    
    return $leapAppChartValues
}

# ========================================
# Main Script Execution
# ========================================

# Get script information for tracking
$scriptHash = (Get-FileHash -Path $PSCommandPath -Algorithm SHA1).Hash.Substring(0, 7)
$scriptName = [System.IO.Path]::GetFileName($PSCommandPath)
Write-Host "Running $scriptName (hash: $scriptHash)"

# Parse and validate JSON inputs
try {
    Write-Host "Parsing configuration inputs..."
    $foldedConfig = Get-JsonContent $FoldedConfigJson
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
    
    $annotations = Get-LeapAppAnnotations

    # Add each workload's values under its alias
    foreach ($workloadName in $workloadNames) {
        Write-Host "  Processing workload: $workloadName"
        
        # Each workload matches a subchart alias with its own set of values
        $workload = $foldedConfig.workloads.$workloadName
        
        if (-not $workload) {
            throw "Workload '$workloadName' not found in folded config"
        }
        
        # Generate this sub chart values from the workload config
        $workloadConfig = New-LeapAppChartValues `
            -Workload $workload `
            -Annotations $annotations `
            -ProductName $ProductName `
            -Region $Region `
            -Environment $Environment
        
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
