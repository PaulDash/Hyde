#Requires -Version 5.1
#Requires -Modules powershell-yaml

<#PSScriptInfo
.VERSION 0.2.1
.GUID abebebd5-6f8f-4d36-b3c1-e6313b9eac6f
.AUTHOR Paul Wojcicki-Jarocki
.COPYRIGHT © 2026 Paul Dash
.LICENSEURI https://github.com/PaulDash/Hyde/raw/main/LICENSE
.PROJECTURI https://github.com/PaulDash/Hyde
.ICONURI https://github.com/PaulDash/Hyde/raw/main/res/Icon_32x32.png
.TAGS PowerShell static-site-generator jekyll markdown yaml
.RELEASENOTES Added manifest-based module entry, exported Hyde command, collection permalinks, module-first command routing, and lower-camel-case private helper names.
#>

<#
.SYNOPSIS
PowerShell static site generator. The ugly Mr. Hyde to the popular Jekyll.
.DESCRIPTION
Hyde is a PowerShell static site generator inspired by Jekyll.  Created as a fun project to only generate my own private webpage, but useful as an example when teaching about PowerShell.

The current implementation supports:
- loading Hyde defaults from `globalConfig.yaml`
- loading site settings from `_config.yml`
- loading site and built-in plugins
- discovering documents and static files
- copying HTML and static files to the destination site
- loading YAML files from `_data`
- parsing YAML front matter
- rendering Markdown documents to HTML
- rendering single-level layouts through the Liquid module
- rendering plugin-provided Liquid tags and filters
- collections
- permalinks
- cleaning generated output and cache directories
- basic doctor-style site validation

The current implementation does not yet support:
- `New`
- layout inheritance
- posts

We may never support:
- all plugins
- syntax highlighting
- new-theme command

Due to the nature of PowerShell, there is no intention to support:
- serve command
- file watch mode

.PARAMETER Command
Chooses which top-level Hyde action to run.

Available options are:
- `New`
- `Build`
- `Clean`
- `Doctor`
- `Help`

.PARAMETER Source
Overrides the configured source directory for the site.
Supported by: `Build`, `Doctor`

.PARAMETER Destination
Overrides the configured destination directory for generated output.
Supported by: `Build`, `Clean`

.PARAMETER Environment
Sets the build environment value exposed internally during the build.
Supported by: `Build`

.PARAMETER Quiet
Suppresses Hyde information messages during execution.
Supported by: `Build`, `Clean`, `Doctor`

.EXAMPLE
.\Hyde.ps1 Build

Builds the site using paths from configuration.

.EXAMPLE
.\Hyde.ps1 Build -Source . -Destination .\_site

Builds the site from the current directory into `.\_site`.

.EXAMPLE
.\Hyde.ps1 Clean

Removes the generated destination folder, metadata file, and cache directories for the site.

.EXAMPLE
.\Hyde.ps1 Doctor

Checks the site for common problems such as invalid front matter, missing layouts, and output-path conflicts.

.EXAMPLE
.\Hyde.ps1 Help

Shows command help for the script.

#>

[CmdletBinding()]
param(
    # Keep the wrapper permissive and let the module command perform command-specific validation.
    [Parameter(Position = 0)]
    [string]$Command,
    [string]$Source,
    [string]$Destination,
    [string]$Environment,
    [switch]$Quiet
)

begin {
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Load the module manifest so the module can act as the real entry point.
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'Hyde.psd1'

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

if ($PSBoundParameters.ContainsKey('Destination')) {
    $commandParameters['Destination'] = $Destination
}

if ($PSBoundParameters.ContainsKey('Environment')) {
    $commandParameters['Environment'] = $Environment
}

if ($PSBoundParameters.ContainsKey('Quiet')) {
    $commandParameters['Quiet'] = $Quiet
}

if ($VerbosePreference -eq 'Continue') {
    Hyde @commandParameters -Verbose
} else {
    Hyde @commandParameters
}
}

# TODO: Implement `New` site scaffolding
# TODO: Add posts
# TODO: implement Layout inheritance by pre-parsing files in _layouts
