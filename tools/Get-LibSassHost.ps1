[CmdletBinding()]
param(
    [string]$Version = 'latest',
    [string]$DestinationRoot = (Join-Path -Path $PSScriptRoot -ChildPath '..\src\Plugins\libsass-converter\lib'),
    [switch]$Force
)

<#
.SYNOPSIS
Download and bundle LibSassHost assets for Hyde's libsass-converter plugin.

.DESCRIPTION
This tool downloads a LibSassHost NuGet package, extracts managed/native assets,
and writes them into the plugin-local bundle folder expected by libsass-converter.

.EXAMPLE
.\tools\Get-LibSassHost.ps1
Downloads the latest package version and bundles it into src/Plugins/libsass-converter/lib.

.EXAMPLE
.\tools\Get-LibSassHost.ps1 -Version 2.2.0
Pins package acquisition to a specific version.

.EXAMPLE
.\tools\Get-LibSassHost.ps1 -Force
Deletes and rebuilds the destination bundle folder.

.EXAMPLE
.\tools\Get-LibSassHost.ps1 -DestinationRoot .\scratch\libsass
Writes assets to a custom destination for packaging or troubleshooting.

.NOTES
Run this from the Hyde repository root for the default destination.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LatestLibSassHostVersion {
    # NuGet flat container index lists every published version.
    $indexUrl = 'https://api.nuget.org/v3-flatcontainer/libsasshost/index.json'
    $indexPayload = Invoke-RestMethod -Uri $indexUrl -Method Get
    if ($null -eq $indexPayload -or -not $indexPayload.versions -or $indexPayload.versions.Count -eq 0) {
        throw 'Could not discover LibSassHost versions from NuGet.'
    }

    return [string]($indexPayload.versions | Select-Object -Last 1)
}

function Resolve-LibSassVersion {
    param([string]$RequestedVersion)

    # "latest" resolves dynamically so users do not need to edit this script.
    if ([string]::IsNullOrWhiteSpace($RequestedVersion) -or $RequestedVersion -eq 'latest') {
        return Get-LatestLibSassHostVersion
    }

    return $RequestedVersion.Trim()
}

function Copy-LibSassAsset {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    # Ensure parent folders exist before copying each asset.
    $targetDirectory = Split-Path -Path $TargetPath -Parent
    if (-not (Test-Path -LiteralPath $targetDirectory -PathType Container)) {
        [void](New-Item -Path $targetDirectory -ItemType Directory -Force)
    }

    Copy-Item -LiteralPath $SourcePath -Destination $TargetPath -Force
}

$resolvedVersion = Resolve-LibSassVersion -RequestedVersion $Version
$packageUrl = "https://api.nuget.org/v3-flatcontainer/libsasshost/$resolvedVersion/libsasshost.$resolvedVersion.nupkg"

$tempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("hyde-libsasshost-{0}" -f [System.Guid]::NewGuid().ToString('N'))
$packagePath = Join-Path -Path $tempRoot -ChildPath 'libsasshost.nupkg'
$extractPath = Join-Path -Path $tempRoot -ChildPath 'pkg'

try {
    [void](New-Item -Path $tempRoot -ItemType Directory -Force)

    Write-Host "Downloading LibSassHost $resolvedVersion from NuGet..."
    Invoke-WebRequest -Uri $packageUrl -OutFile $packagePath

    Write-Host 'Extracting package...'
    Expand-Archive -LiteralPath $packagePath -DestinationPath $extractPath -Force

    # Resolve destination deterministically so output paths are stable in logs and CI.
    $destinationParent = Split-Path -Path $DestinationRoot -Parent
    if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
        [void](New-Item -Path $destinationParent -ItemType Directory -Force)
    }

    $destinationRootFull = (Resolve-Path -Path $destinationParent).Path
    $destinationRootPath = Join-Path -Path $destinationRootFull -ChildPath (Split-Path -Path $DestinationRoot -Leaf)

    if ((Test-Path -LiteralPath $destinationRootPath) -and $Force) {
        Remove-Item -LiteralPath $destinationRootPath -Recurse -Force
    }

    # Preserve NuGet layout so plugin probing logic can remain simple and predictable.
    $managedCandidates = @(
        (Join-Path -Path $extractPath -ChildPath 'lib\netstandard2.0\LibSassHost.dll'),
        (Join-Path -Path $extractPath -ChildPath 'lib\net8.0\LibSassHost.dll'),
        (Join-Path -Path $extractPath -ChildPath 'lib\net7.0\LibSassHost.dll')
    )

    $managedAssemblyPath = $managedCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace([string]$managedAssemblyPath)) {
        throw 'Could not find LibSassHost.dll in NuGet package contents.'
    }

    $relativeManagedPath = $managedAssemblyPath.Substring($extractPath.Length).TrimStart([char[]]@('\', '/'))
    Copy-LibSassAsset -SourcePath $managedAssemblyPath -TargetPath (Join-Path -Path $destinationRootPath -ChildPath $relativeManagedPath)

    foreach ($runtimeFolder in @('win-x64', 'win-x86')) {
        $nativeSourcePath = Join-Path -Path $extractPath -ChildPath ("runtimes\\$runtimeFolder\\native")
        if (-not (Test-Path -LiteralPath $nativeSourcePath -PathType Container)) {
            continue
        }

        $nativeTargetPath = Join-Path -Path $destinationRootPath -ChildPath ("runtimes\\$runtimeFolder\\native")
        if (-not (Test-Path -LiteralPath $nativeTargetPath -PathType Container)) {
            [void](New-Item -Path $nativeTargetPath -ItemType Directory -Force)
        }

        foreach ($nativeAsset in Get-ChildItem -LiteralPath $nativeSourcePath -File) {
            Copy-LibSassAsset -SourcePath $nativeAsset.FullName -TargetPath (Join-Path -Path $nativeTargetPath -ChildPath $nativeAsset.Name)
        }
    }

    Write-Host "LibSassHost $resolvedVersion bundled at '$destinationRootPath'."
    Write-Host 'If this repository is your runtime, no further setup is required.'
    Write-Host 'For distribution, include the plugin folder and this lib subtree together.'
    Write-Host 'You can now enable plugin: libsass-converter in your Hyde site config.'
} finally {
    # Always remove temp artifacts even when download/extract fails.
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
