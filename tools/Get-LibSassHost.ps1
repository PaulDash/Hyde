[CmdletBinding()]
param(
    [string]$Version = 'latest',
    [string]$DestinationRoot = (Join-Path -Path $PSScriptRoot -ChildPath '..\src\Plugins\libsass-converter'),
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

    try {
        Copy-Item -LiteralPath $SourcePath -Destination $TargetPath -Force
    } catch {
        if ((Test-Path -LiteralPath $TargetPath -PathType Leaf) -and
            ($_.Exception.Message -match 'being used by another process|Access to the path')) {
            Write-Warning "Skipping locked file '$TargetPath'. Close active Hyde/PowerShell sessions and re-run with -Force to fully refresh."
            return
        }

        throw
    }
}

function Download-NuGetPackage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageId,

        [Parameter(Mandatory = $true)]
        [string]$PackageVersion,

        [Parameter(Mandatory = $true)]
        [string]$DownloadRoot
    )

    $packageRoot = Join-Path -Path $DownloadRoot -ChildPath ("{0}.{1}" -f $PackageId, $PackageVersion)
    $packageFile = Join-Path -Path $packageRoot -ChildPath ("{0}.{1}.nupkg" -f $PackageId, $PackageVersion)
    $extractRoot = Join-Path -Path $packageRoot -ChildPath 'pkg'

    [void](New-Item -Path $packageRoot -ItemType Directory -Force)

    $lowerId = $PackageId.ToLowerInvariant()
    $lowerVersion = $PackageVersion.ToLowerInvariant()
    $packageUrl = "https://api.nuget.org/v3-flatcontainer/$lowerId/$lowerVersion/$lowerId.$lowerVersion.nupkg"

    Invoke-WebRequest -Uri $packageUrl -OutFile $packageFile
    Expand-Archive -LiteralPath $packageFile -DestinationPath $extractRoot -Force

    return $extractRoot
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
        (Join-Path -Path $bundleRoot -ChildPath 'LibSassHost.dll'),
        (Join-Path -Path $bundleRoot -ChildPath 'lib\net10.0\LibSassHost.dll'),
        (Join-Path -Path $bundleRoot -ChildPath 'lib\net9.0\LibSassHost.dll'),
        (Join-Path -Path $bundleRoot -ChildPath 'lib\net8.0\LibSassHost.dll'),
        (Join-Path -Path $bundleRoot -ChildPath 'lib\net7.0\LibSassHost.dll'),
        (Join-Path -Path $bundleRoot -ChildPath 'lib\netstandard2.0\LibSassHost.dll')
    )

    $managedAssemblyPath = $managedCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace([string]$managedAssemblyPath)) {
        throw 'Could not find LibSassHost.dll in NuGet package contents.'
    }

    $relativeManagedPath = $managedAssemblyPath.Substring($extractPath.Length).TrimStart([char[]]@('\', '/'))
    $managedTargetPath = Join-Path -Path $destinationRootPath -ChildPath $relativeManagedPath
    Copy-LibSassAsset -SourcePath $managedAssemblyPath -TargetPath $managedTargetPath

    # Bundle known managed dependencies used by LibSassHost so runtime type loading succeeds.
    $dependencySpecs = @(
        @{ Id = 'AdvancedStringBuilder'; Version = '0.1.1' }
        @{ Id = 'System.Buffers'; Version = '4.5.1' }
    )

    $managedTargetDirectory = Split-Path -Path $managedTargetPath -Parent
    foreach ($dependencySpec in $dependencySpecs) {
        try {
            Write-Host ("Downloading dependency {0} {1}..." -f $dependencySpec.Id, $dependencySpec.Version)
            $dependencyExtractRoot = Download-NuGetPackage -PackageId $dependencySpec.Id -PackageVersion $dependencySpec.Version -DownloadRoot $tempRoot

            $dependencyCandidates = @(
                (Join-Path -Path $dependencyExtractRoot -ChildPath 'lib\netstandard2.0'),
                (Join-Path -Path $dependencyExtractRoot -ChildPath 'lib\netstandard1.3'),
                (Join-Path -Path $dependencyExtractRoot -ChildPath 'lib\netstandard1.0')
            )

            $dependencyLibFolder = $dependencyCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Container } | Select-Object -First 1
            if ($null -eq $dependencyLibFolder) {
                continue
            }

            foreach ($dependencyDll in Get-ChildItem -LiteralPath $dependencyLibFolder -Filter '*.dll' -File) {
                Copy-LibSassAsset -SourcePath $dependencyDll.FullName -TargetPath (Join-Path -Path $managedTargetDirectory -ChildPath $dependencyDll.Name)
            }
        } catch {
            Write-Warning ("Could not bundle dependency {0} {1}. {2}" -f $dependencySpec.Id, $dependencySpec.Version, $_.Exception.Message)
        }
    }

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

    # Bundle native packages that carry libsass.dll for current architecture.
    $nativePackageSpecs = @(
        @{ Id = 'LibSassHost.Native.win-x64'; Version = $resolvedVersion; Runtime = 'win-x64' }
        @{ Id = 'LibSassHost.Native.win-x86'; Version = $resolvedVersion; Runtime = 'win-x86' }
    )

    foreach ($nativePackageSpec in $nativePackageSpecs) {
        try {
            Write-Host ("Downloading native package {0} {1}..." -f $nativePackageSpec.Id, $nativePackageSpec.Version)
            $nativeExtractRoot = Download-NuGetPackage -PackageId $nativePackageSpec.Id -PackageVersion $nativePackageSpec.Version -DownloadRoot $tempRoot

            $nativeCandidates = @(
                (Join-Path -Path $nativeExtractRoot -ChildPath ("runtimes\\{0}\\native" -f $nativePackageSpec.Runtime)),
                (Join-Path -Path $nativeExtractRoot -ChildPath 'native')
            )

            $nativeSourceFolder = $nativeCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Container } | Select-Object -First 1
            if ($null -eq $nativeSourceFolder) {
                continue
            }

            $nativeTargetFolder = Join-Path -Path $destinationRootPath -ChildPath ("runtimes\\{0}\\native" -f $nativePackageSpec.Runtime)
            if (-not (Test-Path -LiteralPath $nativeTargetFolder -PathType Container)) {
                [void](New-Item -Path $nativeTargetFolder -ItemType Directory -Force)
            }

            foreach ($nativeAsset in Get-ChildItem -LiteralPath $nativeSourceFolder -File) {
                Copy-LibSassAsset -SourcePath $nativeAsset.FullName -TargetPath (Join-Path -Path $nativeTargetFolder -ChildPath $nativeAsset.Name)
            }
        } catch {
            Write-Warning ("Could not bundle native package {0} {1}. {2}" -f $nativePackageSpec.Id, $nativePackageSpec.Version, $_.Exception.Message)
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
