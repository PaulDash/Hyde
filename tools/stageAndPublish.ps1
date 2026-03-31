#Requires -Version 7.0

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function getPublishContext {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $moduleSourceRoot = Join-Path -Path $projectRoot -ChildPath 'src'
    $manifestPath = Join-Path -Path $moduleSourceRoot -ChildPath 'Hyde.psd1'
    $manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
    $tempRoot = Join-Path -Path $env:TEMP -ChildPath 'HydePublish'

    return @{
        ProjectRoot      = $projectRoot
        ModuleSourceRoot = $moduleSourceRoot
        ModuleName       = $manifest.RootModule -replace '\.psm1$', ''
        ManifestPath     = $manifestPath
        Manifest         = $manifest
        TempRoot         = $tempRoot
        StagePath        = Join-Path -Path $tempRoot -ChildPath 'stage'
        StageModulePath  = Join-Path -Path (Join-Path -Path $tempRoot -ChildPath 'stage') -ChildPath ($manifest.RootModule -replace '\.psm1$', '')
        RepoPath         = Join-Path -Path $tempRoot -ChildPath 'repo'
        ShareName        = 'HydeLocalRepo'
        RepositoryName   = 'HydeLocal'
        SharePath        = Join-Path -Path $tempRoot -ChildPath 'repo'
        ShareLocation    = "\\{0}\{1}" -f $env:COMPUTERNAME, 'HydeLocalRepo'
    }
}

function initializePublishDirectories {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    foreach ($path in @($Context.TempRoot, $Context.StagePath, $Context.StageModulePath, $Context.RepoPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }
}

function clearStageDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    if (Test-Path -LiteralPath $Context.StageModulePath -PathType Container) {
        Get-ChildItem -LiteralPath $Context.StageModulePath -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force
    } else {
        New-Item -ItemType Directory -Path $Context.StageModulePath -Force | Out-Null
    }
}

function stageManifestFiles {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    initializePublishDirectories -Context $Context
    clearStageDirectory -Context $Context

    $stagedFiles = New-Object System.Collections.ArrayList
    foreach ($relativePath in $Context.Manifest.FileList) {
        $sourcePath = Join-Path -Path $Context.ModuleSourceRoot -ChildPath $relativePath
        $destinationPath = Join-Path -Path $Context.StageModulePath -ChildPath $relativePath
        $destinationDirectory = Split-Path -Parent $destinationPath

        if (-not (Test-Path -LiteralPath $sourcePath)) {
            throw "The manifest FileList entry '$relativePath' does not exist at '$sourcePath'."
        }

        if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        }

        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
        [void]$stagedFiles.Add($destinationPath)
        Write-Verbose "Staged '$relativePath' to '$destinationPath'."
    }

    Write-Host "Staged $($stagedFiles.Count) file(s) into '$($Context.StageModulePath)'." -ForegroundColor Green
    foreach ($stagedFile in $stagedFiles) {
        Write-Host "  $stagedFile"
    }
}

function ensureLocalRepository {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    initializePublishDirectories -Context $Context

    if (-not (Get-SmbShare -Name $Context.ShareName -ErrorAction SilentlyContinue)) {
        New-SmbShare -Name $Context.ShareName -Path $Context.SharePath -FullAccess Administrators -ReadAccess Everyone | Out-Null
    }

    $repository = Get-PSRepository -Name $Context.RepositoryName -ErrorAction SilentlyContinue
    if ($null -eq $repository) {
        Register-PSRepository -Name $Context.RepositoryName -SourceLocation $Context.ShareLocation -PublishLocation $Context.ShareLocation -InstallationPolicy Trusted
        return
    }

    if ($repository.SourceLocation -ne $Context.ShareLocation) {
        throw "The repository '$($Context.RepositoryName)' is already registered to '$($repository.SourceLocation)', not '$($Context.ShareLocation)'."
    }
}

function publishToLocalRepository {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    stageManifestFiles -Context $Context
    ensureLocalRepository -Context $Context

    Write-Host "Publishing staged module files to local repository '$($Context.RepositoryName)' at '$($Context.ShareLocation)'." -ForegroundColor Cyan
    Publish-Module -Path $Context.StageModulePath -Repository $Context.RepositoryName -Verbose
}

function cleanupLocalRepositoryArtifacts {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    $repository = Get-PSRepository -Name $Context.RepositoryName -ErrorAction SilentlyContinue
    if ($null -ne $repository) {
        if ($repository.SourceLocation -ne $Context.ShareLocation) {
            throw "Refusing to unregister '$($Context.RepositoryName)' because it points to '$($repository.SourceLocation)' instead of '$($Context.ShareLocation)'."
        }

        Unregister-PSRepository -Name $Context.RepositoryName
    }

    if (Get-SmbShare -Name $Context.ShareName -ErrorAction SilentlyContinue) {
        Remove-SmbShare -Name $Context.ShareName -Force
    }

    if (Test-Path -LiteralPath $Context.TempRoot) {
        Remove-Item -LiteralPath $Context.TempRoot -Recurse -Force
    }

    Write-Host 'Removed the local repository registration, share, and temp staging files.' -ForegroundColor Green
}

function publishToPowerShellGallery {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    stageManifestFiles -Context $Context

    $apiKey = Read-Host -Prompt 'Enter the PowerShell Gallery API key'
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        throw 'A PowerShell Gallery API key is required to publish.'
    }

    Write-Host 'Running a WhatIf publish to PowerShell Gallery first...' -ForegroundColor Cyan
    Publish-Module -Path $Context.StageModulePath -NuGetApiKey $apiKey -WhatIf -Verbose

    $confirmation = Read-Host -Prompt 'Continue with the real publish? Enter Y to continue'
    if ($confirmation -notin @('Y', 'y')) {
        Write-Host 'Publishing cancelled after the WhatIf run.' -ForegroundColor Yellow
        return
    }

    Publish-Module -Path $Context.StageModulePath -NuGetApiKey $apiKey -Verbose
}

$context = getPublishContext

Write-Host ''
Write-Host 'Hyde stage and publish options:' -ForegroundColor Cyan
Write-Host '1. Publish to a TEMP-backed local repository'
Write-Host '2. Clean up the local repository registration, share, and staging files'
Write-Host '3. Publish to the PowerShell Gallery'
Write-Host ''

$selection = Read-Host -Prompt 'Choose 1, 2, or 3'

switch ($selection) {
    '1' { publishToLocalRepository -Context $context }
    '2' { cleanupLocalRepositoryArtifacts -Context $context }
    '3' { publishToPowerShellGallery -Context $context }
    default { throw "Unknown option '$selection'. Choose 1, 2, or 3." }
}
