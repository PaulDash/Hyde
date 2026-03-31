#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$ModuleManifestPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'src/Hyde.psd1'),

    [string]$MarkdownOutputPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'docs'),

    [string]$ExternalHelpOutputPath = (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'en-US'),

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module PlatyPS -ErrorAction Stop

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

    $aboutPath = Join-Path -Path $OutputFolder -ChildPath 'about_Hyde_Plugin_Authoring.md'

    if (Test-Path -LiteralPath $aboutPath -PathType Leaf) {
        Write-Warning "An about topic markdown file already exists at '$aboutPath'. It will be overwritten."
        Remove-Item -LiteralPath $aboutPath -Force
    }

    # Create a correctly structured about topic skeleton using PlatyPS.
    New-MarkdownAboutHelp -AboutName 'Hyde_Plugin_Authoring' -OutputFolder $OutputFolder | Out-Null

    # Load the source content and normalise line endings.
    $raw = Get-Content -LiteralPath $SourcePath -Raw
    $raw = ($raw -replace "`r`n", "`n") -replace "`r", "`n"

    # Strip the document title heading; New-MarkdownAboutHelp provides the canonical heading.
    $body = [System.Text.RegularExpressions.Regex]::Replace(
        $raw,
        '^#\s+Plugin\s+Authoring\s*\n+',
        '',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    ).Trim()

    # Fill in the placeholder sections PlatyPS left in the skeleton.
    $skeleton = Get-Content -LiteralPath $aboutPath -Raw
    $skeleton = ($skeleton -replace "`r`n", "`n") -replace "`r", "`n"
    $skeleton = $skeleton -replace '\{\{[^}]*SHORT DESCRIPTION[^}]*\}\}', 'Guidance for authoring Hyde plugins.'
    $skeleton = $skeleton -replace '\{\{[^}]*LONG DESCRIPTION[^}]*\}\}', $body

    Set-Content -LiteralPath $aboutPath -Encoding UTF8 -Value $skeleton
    Write-Verbose "Generated about topic at '$aboutPath'."
}

Write-Host "`nCreate about_ file" -BackgroundColor DarkBlue
$proceed = Read-Host -Prompt "Type [Y] to generate a plugin authoring about topic from '$pluginAuthoringSourcePath' into '$resolvedMarkdownOutputPath'.`nThis will overwrite any existing about topic markdown file at '$resolvedMarkdownOutputPath\about_Hyde_Plugin_Authoring.md'.`nType [N] to skip about topic generation."
if ($proceed -match '^[Yy]$') {
    Write-Verbose "Generating plugin authoring about topic from '$pluginAuthoringSourcePath' into '$resolvedMarkdownOutputPath'."
    New-HydePluginAuthoringAboutTopic -SourcePath $pluginAuthoringSourcePath -OutputFolder $resolvedMarkdownOutputPath
} else {
    Write-Verbose "Skipping plugin authoring about topic generation."
}

Write-Host "`nGenerate markdown help" -BackgroundColor DarkBlue
$proceed = Read-Host -Prompt "Type [Y] to regenerate markdown help from comment-based help in the module's .ps1 files.`nType [A] if you also want to generate a BLANK!!! module description.`nThis will overwrite any existing .md files in '$resolvedMarkdownOutputPath'.`nType [N] to skip to external help generation from the existing markdown files."

if ($proceed -match '^[Yy]$') {
    Write-Verbose "Regenerating markdown help from comment-based help in the module's .ps1 files into '$resolvedMarkdownOutputPath'."
    New-MarkdownHelp -Module $moduleName -OutputFolder $resolvedMarkdownOutputPath -Force -ExcludeDontShow | Out-Null
} elseif ($proceed -match '^[Aa]$') {
    Write-Verbose "Regenerating markdown help from comment-based help in the module's .ps1 files into '$resolvedMarkdownOutputPath' with a blank module description."
    New-MarkdownHelp -Module $moduleName -OutputFolder $resolvedMarkdownOutputPath -WithModulePage -ExcludeDontShow -Force  | Out-Null
} else {
    Write-Verbose "Skipping markdown help regeneration and proceeding to external help generation from the existing markdown files in '$resolvedMarkdownOutputPath'."
}

Write-Host "`nGenerate external help" -BackgroundColor DarkBlue
$proceed = Read-Host -Prompt "Type [Y] to continue with external help generation from the markdown files.`nThis will overwrite any existing .xml help files in '$resolvedExternalHelpOutputPath'."

if ($proceed -match '^[Yy]$') {
    Write-Verbose "Generating external help into '$resolvedExternalHelpOutputPath'."
    New-ExternalHelp -Path $resolvedMarkdownOutputPath -OutputPath $resolvedExternalHelpOutputPath -Force -Verbose
}
