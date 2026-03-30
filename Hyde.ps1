#Requires -Version 5.1
#Requires -Modules powershell-yaml

[CmdletBinding()]
param(
    # Keep the wrapper permissive and let the module command perform command-specific validation.
    [Parameter(Position = 0)]
    [string]$Command,
    [string]$Source,
    [string]$SourcePath,
    [string]$Destination,
    [string]$Environment,
    [switch]$Quiet,
    [switch]$Blank,
    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$ArgumentList
)

begin {
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Handle PowerLiquid module dependency
$powerLiquidModule = Get-Module -Name 'PowerLiquid' -ErrorAction SilentlyContinue
if (-not $powerLiquidModule) {
    # Try to load from sibling repo first
    $powerLiquidManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\PowerLiquid\PowerLiquid.psd1'
    $resolvedPowerLiquidManifestPath = if (Test-Path -LiteralPath $powerLiquidManifestPath -PathType Leaf) {
        (Resolve-Path -LiteralPath $powerLiquidManifestPath).Path
    } else {
        $null
    }

    if ($resolvedPowerLiquidManifestPath) {
        Import-Module $resolvedPowerLiquidManifestPath -ErrorAction Stop
    } elseif (Get-Module -ListAvailable -Name 'PowerLiquid') {
        Import-Module 'PowerLiquid' -ErrorAction Stop
    } else {
        $installModuleCommand = Get-Command -Name 'Install-Module' -ErrorAction SilentlyContinue
        if ($null -eq $installModuleCommand) {
            throw "Could not load the PowerLiquid module. Install PowerLiquid from PowerShell Gallery or place the sibling repo at '$powerLiquidManifestPath'."
        }

        Write-Host "PowerLiquid is not installed locally. Installing from PowerShell Gallery..." -ForegroundColor Yellow

        try {
            Install-Module -Name 'PowerLiquid' -Repository 'PSGallery' -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        } catch {
            Write-Host "Stable PowerLiquid install did not succeed. Trying prerelease package..." -ForegroundColor Yellow
            Install-Module -Name 'PowerLiquid' -Repository 'PSGallery' -Scope CurrentUser -Force -AllowClobber -AllowPrerelease -ErrorAction Stop
        }

        Import-Module 'PowerLiquid' -ErrorAction Stop
    }
}

# Get PowerLiquid module info
$powerLiquidModule = Get-Module -Name 'PowerLiquid'
$powerLiquidVersion = $powerLiquidModule.Version.ToString()
$powerLiquidPath = $powerLiquidModule.Path

Write-Host "PowerLiquid module loaded: Version $powerLiquidVersion from $powerLiquidPath" -ForegroundColor Green

switch ($Command) {
    'Clean' {
        if ($PSBoundParameters.ContainsKey('Source')) {
            throw "A parameter cannot be found that matches parameter name 'Source'."
        }
    }
    'Doctor' {
        if ($PSBoundParameters.ContainsKey('Destination')) {
            throw "A parameter cannot be found that matches parameter name 'Destination'."
        }
    }
}

# Load the module manifest so the module can act as the real entry point.
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'src/Hyde.psd1'

# Reuse an existing Hyde module instance in the current session.
$loadedHydeModule = Get-Module |
    Where-Object {
        $_.Path -and $_.Path.Equals($modulePath, [System.StringComparison]::OrdinalIgnoreCase)
    } |
    Select-Object -First 1

if (-not $loadedHydeModule) {
    Import-Module $modulePath
}

# Forward the parsed wrapper arguments to the module command so the module remains the primary surface area.
$commandParameters = @{}
if ($PSBoundParameters.ContainsKey('Command')) {
    $commandParameters['Command'] = $Command
}

if ($PSBoundParameters.ContainsKey('Source')) {
    $commandParameters['Source'] = $Source
}

if ($PSBoundParameters.ContainsKey('SourcePath')) {
    $commandParameters['SourcePath'] = $SourcePath
}

if ($PSBoundParameters.ContainsKey('Destination')) {
    $commandParameters['Destination'] = $Destination
} elseif ($Command -eq 'New' -and $ArgumentList.Count -gt 0) {
    $commandParameters['Destination'] = [string]$ArgumentList[0]
}

if ($PSBoundParameters.ContainsKey('Environment')) {
    $commandParameters['Environment'] = $Environment
}

if ($PSBoundParameters.ContainsKey('Quiet')) {
    $commandParameters['Quiet'] = $Quiet
}

if ($PSBoundParameters.ContainsKey('Blank')) {
    $commandParameters['Blank'] = $Blank
}

if ($VerbosePreference -eq 'Continue') {
    Hyde @commandParameters -Verbose
} else {
    Hyde @commandParameters
}
}
