<#
.SYNOPSIS
Built-in Hyde plugin that fills missing titles from Markdown headings.

.DESCRIPTION
`titles-from-headings` assigns a semantic page title from the first Markdown H1
when front matter does not provide one.

This plugin has no external installation requirements.

.PARAMETER Context
Plugin execution context supplied by Hyde.

.PARAMETER Install
Runs plugin installation flow.

For this plugin, installation is not required. The command returns `$true`.

.EXAMPLE
./src/Plugins/titles-from-headings.ps1 -Install

Returns `True` because no installation is needed.
#>
[CmdletBinding()]
param(
    $Context,

    [switch]$Install
)

if ($Install) {
    if ($VerbosePreference -eq 'Continue' -or $VerbosePreference -eq 'Inquire') {
        Write-Verbose "Plugin 'titles-from-headings' does not require installation."
    }

    return $true
}

# This built-in plugin fills missing page titles from the first Markdown H1 heading.
$null = $Context
@{
    Name = 'titles-from-headings'
    Hooks = @{
        BeforeRenderDocument = {
            param($Invocation)

            $document = $Invocation.Document
            if ($null -eq $document) {
                return
            }

            if (-not [string]::IsNullOrWhiteSpace($document.Title)) {
                return
            }

            $markdownExtensions = getHydeMarkdownExtensions -Settings $Invocation.Context.Settings
            if ($document.Extension -notin $markdownExtensions) {
                return
            }

            $match = [System.Text.RegularExpressions.Regex]::Match(
                $document.RawContent,
                '(?m)^\s*#\s+(.+?)\s*$'
            )

            if (-not $match.Success) {
                return
            }

            # Pull a semantic title from the first Markdown heading and trim a few common inline markdown markers.
            $resolvedTitle = $match.Groups[1].Value.Trim()
            $resolvedTitle = $resolvedTitle -replace '\s+#+\s*$', ''
            $resolvedTitle = $resolvedTitle -replace '\[([^\]]+)\]\([^)]+\)', '$1'
            $resolvedTitle = $resolvedTitle -replace '`([^`]+)`', '$1'
            $resolvedTitle = $resolvedTitle -replace '\*\*([^\*]+)\*\*', '$1'
            $resolvedTitle = $resolvedTitle -replace '__([^_]+)__', '$1'
            $resolvedTitle = $resolvedTitle -replace '(?<!\*)\*([^\*]+)\*(?!\*)', '$1'
            $resolvedTitle = $resolvedTitle -replace '(?<!_)_([^_]+)_(?!_)', '$1'
            $resolvedTitle = $resolvedTitle.Trim()
            if ([string]::IsNullOrWhiteSpace($resolvedTitle)) {
                return
            }

            # Store the title semantically and mirror it into front matter so existing page.title consumers see it.
            $document.Title = $resolvedTitle
            $document.FrontMatter['title'] = $resolvedTitle
        }
    }
}
