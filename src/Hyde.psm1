Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module powershell-yaml -ErrorAction Stop
$moduleRoot = Split-Path -Parent $PSCommandPath
$script:HydeModuleRoot = $moduleRoot
$script:HydeManifestPath = Join-Path -Path $moduleRoot -ChildPath 'Hyde.psd1'
$script:HydeVersion = (Test-ModuleManifest -Path $script:HydeManifestPath).Version.ToString()

$powerLiquidManifestPath = Join-Path -Path $moduleRoot -ChildPath '..\..\PowerLiquid\PowerLiquid.psd1'
$resolvedPowerLiquidManifestPath = if (Test-Path -LiteralPath $powerLiquidManifestPath -PathType Leaf) {
    (Resolve-Path -LiteralPath $powerLiquidManifestPath).Path
} else {
    $null
}

if ($resolvedPowerLiquidManifestPath) {
    # Importing without -Force reuses the existing module instance while still making its exports available in Hyde's module scope.
    Import-Module $resolvedPowerLiquidManifestPath
} elseif (Get-Module -ListAvailable -Name 'PowerLiquid') {
    Import-Module 'PowerLiquid'
} else {
    throw "Could not load the PowerLiquid module. Install PowerLiquid or place the sibling repo at '$powerLiquidManifestPath'."
}

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

Export-ModuleMember -Function Hyde, New-StaticSite, Publish-StaticSite, Clear-StaticSite, Test-StaticSite
