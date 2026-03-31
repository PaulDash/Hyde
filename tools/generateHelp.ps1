#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$ModuleManifestPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'src/Hyde.psd1'),

    [string]$MarkdownOutputPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'docs/help'),

    [string]$ExternalHelpOutputPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'src/en-US'),

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module PlatyPS -MinimumVersion 0.14.2 -ErrorAction Stop

$resolvedManifestPath = [System.IO.Path]::GetFullPath($ModuleManifestPath)
$resolvedMarkdownOutputPath = [System.IO.Path]::GetFullPath($MarkdownOutputPath)
$resolvedExternalHelpOutputPath = [System.IO.Path]::GetFullPath($ExternalHelpOutputPath)

if (-not (Test-Path -LiteralPath $resolvedManifestPath -PathType Leaf)) {
    throw "Could not find the module manifest at '$resolvedManifestPath'."
}

if ($Force -and (Test-Path -LiteralPath $resolvedMarkdownOutputPath -PathType Container)) {
    Get-ChildItem -LiteralPath $resolvedMarkdownOutputPath -Filter '*.md' -File -ErrorAction SilentlyContinue |
        Remove-Item -Force
}

foreach ($path in @($resolvedMarkdownOutputPath, $resolvedExternalHelpOutputPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
}

Write-Verbose "Importing module from '$resolvedManifestPath'."
Import-Module $resolvedManifestPath -Force -ErrorAction Stop

$moduleName = (Test-ModuleManifest -Path $resolvedManifestPath).Name
$projectRoot = Split-Path -Parent $PSScriptRoot
$pluginAuthoringSourcePath = Join-Path -Path $projectRoot -ChildPath 'src/Plugins/PluginAuthoring.md'

function New-HydePluginAuthoringAboutTopic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$OutputFolder
    )

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        Write-Warning "Skipping about topic generation because source markdown was not found at '$SourcePath'."
        return
    }

    $raw = Get-Content -LiteralPath $SourcePath -Raw
    $raw = ($raw -replace "`r`n", "`n") -replace "`r", "`n"

    # Remove the document title heading; the about topic provides its own canonical heading.
    $body = [System.Text.RegularExpressions.Regex]::Replace($raw, '^#\s+Plugin\s+Authoring\s*\n+', '', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $body = $body.Trim()

    $aboutPath = Join-Path -Path $OutputFolder -ChildPath 'about_Hyde_Plugin_Authoring.md'
    $aboutContent = @"
# about_Hyde_Plugin_Authoring

## SHORT DESCRIPTION
Guidance for authoring Hyde plugins.

## LONG DESCRIPTION

$body
"@

    Set-Content -LiteralPath $aboutPath -Encoding UTF8 -Value $aboutContent
    Write-Verbose "Generated about topic markdown at '$aboutPath'."
}

$proceed = Read-Host -Prompt "Type [Y] if you want to regenerate markdown help from comment-based help in the module's .ps1 files. This will overwrite any existing .md files in '$resolvedMarkdownOutputPath'.`nType [N] to skip to external help generation from the existing markdown files."

if ($proceed -match '^[Yy]$') {
    Write-Verbose "Regenerating markdown help from comment-based help in the module's .ps1 files into '$resolvedMarkdownOutputPath'."
    New-MarkdownHelp -Module $moduleName -OutputFolder $resolvedMarkdownOutputPath -WithModulePage -Force -ExcludeDontShow | Out-Null
} else {
    Write-Verbose "Skipping markdown help regeneration and proceeding to external help generation from the existing markdown files in '$resolvedMarkdownOutputPath'."
}

New-HydePluginAuthoringAboutTopic -SourcePath $pluginAuthoringSourcePath -OutputFolder $resolvedMarkdownOutputPath

$proceed = Read-Host -Prompt "Type [Y] to continue with external help generation from the markdown files.`nThis will overwrite any existing .xml help files in '$resolvedExternalHelpOutputPath'."

if ($proceed -match '^[Yy]$') {
    Write-Verbose "Generating external help into '$resolvedExternalHelpOutputPath'."
    New-ExternalHelp -Path $resolvedMarkdownOutputPath -OutputPath $resolvedExternalHelpOutputPath -Force -Verbose
}
