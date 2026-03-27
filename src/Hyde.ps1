#Requires -Version 5.1
#Requires -Modules powershell-yaml

<#PSScriptInfo
.VERSION 0.0.2.0
.GUID abebebd5-6f8f-4d36-b3c1-e6313b9eac6f
.AUTHOR Paul Wojcicki-Jarocki
.COPYRIGHT © 2026 Paul Dash
.LICENSEURI https://github.com/PaulDash/Hyde/raw/main/LICENSE
.PROJECTURI https://github.com/PaulDash/Hyde
.ICONURI https://github.com/PaulDash/Hyde/raw/main/res/Icon_32x32.png
.TAGS PowerShell static-site-generator jekyll markdown yaml
.RELEASENOTES Build and clean commands now use module-based internals, typed content items, YAML front matter parsing, markdown page rendering, static file copying, and generated-file cleanup.
#>

<#
.SYNOPSIS
PowerShell static site generator. The ugly Mr. Hyde to the popular Jekyll.
.DESCRIPTION
Hyde is a PowerShell static site generator inspired by Jekyll.  Created as a fun project to only generate my own private webpage, but useful as an example when teaching about PowerShell.

The current implementation supports:
- loading Hyde defaults from `globalConfig.yaml`
- loading site settings from `_config.yml`
- discovering documents and static files
- copying HTML and static files to the destination site
- loading YAML files from `_data`
- parsing YAML front matter
- rendering Markdown documents to HTML
- rendering single-level layouts through the Liquid module
- cleaning generated output and cache directories

The current implementation does not yet support:
- `New`
- layout inheritance
- posts
- collections
- permalinks

We may never support:
- plugins
- syntax highlighting
- new-theme command

Due to the nature of PowerShell, there is no intention to support:
- serve command
- file watch mode

.PARAMETER Command
Chooses which top-level Hyde action to run.

Available options are:
- `Build`
- `New`
- `Clean`
- `Help`

At this stage, `Build`, `Clean`, and `Help` are implemented.

.PARAMETER Source
Overrides the configured source directory for the site.

.PARAMETER Destination
Overrides the configured destination directory for generated output.

.PARAMETER Environment
Sets the build environment value exposed internally during the build.

.PARAMETER Quiet
Suppresses Hyde information messages during execution.

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
.\Hyde.ps1 Help

Shows command help for the script.

#>

[CmdletBinding()]
param(
    # Chooses main action to run during this invocation.
    [Parameter(Position = 0)]
    [ValidateSet('New', 'Build', 'Clean', 'Help')]
    [string]$Command,

    # Root location for files to be read.
    [string]$Source,

    # Location where generated site will be written.
    [string]$Destination,

    [Parameter(ParameterSetName = 'Build')]
    [Alias('JEKYLL_ENV', 'HYDE_ENV')]
    [string]$Environment = 'development',

    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Load the module wrapper so the script can delegate to the public commands.
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath 'Hyde.psm1') -Force

if ($PSBoundParameters.ContainsKey('Quiet') -and $VerbosePreference -eq 'Continue') {
    throw "It doesn't make sense to ask for verbose output AND to keep quiet!"
}

# Package the common runtime settings once, then pass them to whichever command runs.
$commandParameters = @{
    Environment = $Environment
    Quiet       = $Quiet
    ScriptPath  = $PSCommandPath
}

if ($PSBoundParameters.ContainsKey('Source')) {
    $commandParameters['Source'] = $Source
}

if ($PSBoundParameters.ContainsKey('Destination')) {
    $commandParameters['Destination'] = $Destination
}

# Route the top-level command to the matching public entry point.
switch ($Command) {
    'New' {
        throw 'TODO: Implement the New command to scaffold a site.'
    }
    'Build' {
        Invoke-HydeBuild @commandParameters
    }
    'Clean' {
        Invoke-HydeClean @commandParameters
    }
    'Help' {
        Get-Help -Name $PSCommandPath
    }
    default {
        throw "Choose one of: Build, New, Clean, Help. Use 'Help' to see script documentation."
    }
}

# read in theme info into ThemeVariables

# TODO: Implement `New` site scaffolding
# TODO: add support for "Collections"

# loop through files
    # check if file is to be "published"
    # if not, don't process

    # read "Front Matter" YAML and
    # save to PageVariables hash table
    # if not defined, this is a "Static File"

    # consider "Includes" from _includes directory

    # TODO: Add posts, collections, and permalink handling.

    # read "Layout"
    # TODO: implement Layout inheritance by pre-parsing files in _layouts

    # for processing, superimpose PageVariables on GlobalVariables

    # create output file at same location or
    # one defined in "permalink"
    # which has "Placeholders" to modify the location through variables
