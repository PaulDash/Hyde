Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module powershell-yaml -ErrorAction Stop
$moduleRoot = Split-Path -Parent $PSCommandPath
$script:HydeModuleRoot = $moduleRoot
$script:HydeManifestPath = Join-Path -Path $moduleRoot -ChildPath 'Hyde.psd1'
$script:HydeVersion = (Test-ModuleManifest -Path $script:HydeManifestPath).Version.ToString()

function importHydePowerLiquidDependency {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleRoot
    )

    $powerLiquidManifestPath = Join-Path -Path $ModuleRoot -ChildPath '..\..\PowerLiquid\PowerLiquid.psd1'
    $resolvedPowerLiquidManifestPath = if (Test-Path -LiteralPath $powerLiquidManifestPath -PathType Leaf) {
        (Resolve-Path -LiteralPath $powerLiquidManifestPath).Path
    } else {
        $null
    }

    if ($resolvedPowerLiquidManifestPath) {
        # Prefer the sibling repo during local development.
        Import-Module $resolvedPowerLiquidManifestPath
        return
    }

    if (Get-Module -ListAvailable -Name 'PowerLiquid') {
        Import-Module 'PowerLiquid'
        return
    }

    $installModuleCommand = Get-Command -Name 'Install-Module' -ErrorAction SilentlyContinue
    if ($null -eq $installModuleCommand) {
        throw "Could not load the PowerLiquid module. Install PowerLiquid from PowerShell Gallery or place the sibling repo at '$powerLiquidManifestPath'."
    }

    Write-Verbose "PowerLiquid is not installed locally. Trying to install it from PowerShell Gallery for the current user."

    try {
        Install-Module -Name 'PowerLiquid' -Repository 'PSGallery' -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    } catch {
        Write-Verbose "Stable PowerLiquid install did not succeed. Trying the prerelease package."
        Install-Module -Name 'PowerLiquid' -Repository 'PSGallery' -Scope CurrentUser -Force -AllowClobber -AllowPrerelease -ErrorAction Stop
    }

    Import-Module 'PowerLiquid' -ErrorAction Stop
}

importHydePowerLiquidDependency -ModuleRoot $moduleRoot

# Load PowerShell classes first so the remaining scripts can reference them.
. (Join-Path -Path $moduleRoot -ChildPath 'Private\HydeTypes.ps1')

# Dot-source private helpers before public commands so exported functions have all dependencies available.
Get-ChildItem -Path (Join-Path -Path $moduleRoot -ChildPath 'Private') -Filter '*.ps1' -Recurse |
    Where-Object { $_.Name -ne 'HydeTypes.ps1' } |
    Sort-Object FullName |
    ForEach-Object { . $_.FullName }

# Dot-source public entry points last, then export only the supported surface area.
Get-ChildItem -Path (Join-Path -Path $moduleRoot -ChildPath 'Public') -Filter '*.ps1' -Recurse |
    Sort-Object FullName |
    ForEach-Object { . $_.FullName }

Export-ModuleMember -Function Hyde, New-StaticSite, New-StaticTheme, Publish-StaticSite, Clear-StaticSite, Test-StaticSite
