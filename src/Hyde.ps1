#Requires -Version 5.1
#Requires -Modules powershell-yaml

<#PSScriptInfo
.VERSION 0.0.2.1
.GUID abebebd5-6f8f-4d36-b3c1-e6313b9eac6f
.AUTHOR Paul Wojcicki-Jarocki
.COPYRIGHT © 2026 Paul Dash
.LICENSEURI https://github.com/PaulDash/Hyde/raw/main/LICENSE
.PROJECTURI https://github.com/PaulDash/Hyde
.ICONURI https://github.com/PaulDash/Hyde/raw/main/res/Icon_32x32.png
.TAGS PowerShell static-site-generator jekyll markdown yaml
.RELEASENOTES Build, clean, and doctor commands now use module-based internals, typed content items, YAML front matter parsing, markdown page rendering, static file copying, generated-file cleanup, and site validation.
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
- cleaning generated output and cache directories
- basic doctor-style site validation

The current implementation does not yet support:
- `New`
- layout inheritance
- posts
- collections
- permalinks

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
- `Build`
- `New`
- `Clean`
- `Doctor`
- `Help`

At this stage, `Build`, `Clean`, `Doctor`, and `Help` are implemented.

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
    # Chooses main action to run during this invocation.
    [Parameter(Position = 0)]
    [ValidateSet('New', 'Build', 'Clean', 'Doctor', 'Help')]
    [string]$Command
)

dynamicparam {
    $dynamicParameters = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()

    function New-HydeDynamicParameter {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Name,

            [Parameter(Mandatory = $true)]
            [Type]$Type,

            [string[]]$Aliases = @()
        )

        $attributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
        $parameterAttribute = [System.Management.Automation.ParameterAttribute]::new()
        [void]$attributeCollection.Add($parameterAttribute)

        if ($Aliases.Count -gt 0) {
            $aliasAttribute = [System.Management.Automation.AliasAttribute]::new($Aliases)
            [void]$attributeCollection.Add($aliasAttribute)
        }

        return [System.Management.Automation.RuntimeDefinedParameter]::new($Name, $Type, $attributeCollection)
    }

    switch ($Command) {
        'Build' {
            $dynamicParameters.Add('Source', (New-HydeDynamicParameter -Name 'Source' -Type ([string])))
            $dynamicParameters.Add('Destination', (New-HydeDynamicParameter -Name 'Destination' -Type ([string])))
            $dynamicParameters.Add('Environment', (New-HydeDynamicParameter -Name 'Environment' -Type ([string]) -Aliases @('JEKYLL_ENV', 'HYDE_ENV')))
            $dynamicParameters.Add('Quiet', (New-HydeDynamicParameter -Name 'Quiet' -Type ([switch])))
        }
        'Clean' {
            $dynamicParameters.Add('Destination', (New-HydeDynamicParameter -Name 'Destination' -Type ([string])))
            $dynamicParameters.Add('Quiet', (New-HydeDynamicParameter -Name 'Quiet' -Type ([switch])))
        }
        'Doctor' {
            $dynamicParameters.Add('Source', (New-HydeDynamicParameter -Name 'Source' -Type ([string])))
            $dynamicParameters.Add('Quiet', (New-HydeDynamicParameter -Name 'Quiet' -Type ([switch])))
        }
    }

    return $dynamicParameters
}

begin {
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Load the module wrapper so the script can delegate to the public commands.
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'Hyde.psm1'
$liquidModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'Liquid\Hyde.Liquid.psm1'

# In long-lived editor sessions, unload any existing Hyde modules first so the script uses the current code on disk.
Get-Module |
    Where-Object {
        $_.Path -and (
            $_.Path.Equals($modulePath, [System.StringComparison]::OrdinalIgnoreCase) -or
            $_.Path.Equals($liquidModulePath, [System.StringComparison]::OrdinalIgnoreCase)
        )
    } |
    Sort-Object Name -Descending |
    ForEach-Object { Remove-Module -ModuleInfo $_ -Force -ErrorAction SilentlyContinue }

Import-Module $modulePath

if ($PSBoundParameters.ContainsKey('Quiet') -and $VerbosePreference -eq 'Continue') {
    throw "It doesn't make sense to ask for verbose output AND to keep quiet!"
}

# Route the top-level command to the matching public entry point.
switch ($Command) {
    'New' {
        throw 'TODO: Implement the New command to scaffold a site.'
    }
    'Build' {
        $commandParameters = @{
            Environment = if ($PSBoundParameters.ContainsKey('Environment')) { [string]$PSBoundParameters['Environment'] } else { 'development' }
            Quiet       = [bool]($PSBoundParameters.ContainsKey('Quiet') -and $PSBoundParameters['Quiet'])
            ScriptPath  = $PSCommandPath
        }

        if ($VerbosePreference -eq 'Continue') {
            $commandParameters['Verbose'] = $true
        }

        if ($PSBoundParameters.ContainsKey('Source')) {
            $commandParameters['Source'] = [string]$PSBoundParameters['Source']
        }

        if ($PSBoundParameters.ContainsKey('Destination')) {
            $commandParameters['Destination'] = [string]$PSBoundParameters['Destination']
        }

        Publish-StaticSite @commandParameters
    }
    'Clean' {
        $commandParameters = @{
            Quiet      = [bool]($PSBoundParameters.ContainsKey('Quiet') -and $PSBoundParameters['Quiet'])
            ScriptPath = $PSCommandPath
        }

        if ($VerbosePreference -eq 'Continue') {
            $commandParameters['Verbose'] = $true
        }

        if ($PSBoundParameters.ContainsKey('Destination')) {
            $commandParameters['Destination'] = [string]$PSBoundParameters['Destination']
        }

        Clear-StaticSite @commandParameters
    }
    'Doctor' {
        $commandParameters = @{
            Quiet      = [bool]($PSBoundParameters.ContainsKey('Quiet') -and $PSBoundParameters['Quiet'])
            ScriptPath = $PSCommandPath
        }

        if ($VerbosePreference -eq 'Continue') {
            $commandParameters['Verbose'] = $true
        }

        if ($PSBoundParameters.ContainsKey('Source')) {
            $commandParameters['Source'] = [string]$PSBoundParameters['Source']
        }

        Test-StaticSite @commandParameters
    }
    'Help' {
        Get-Help -Name $PSCommandPath
    }
    default {
        throw "Choose one of: Build, New, Clean, Doctor, Help. Use 'Help' to see script documentation."
    }
}
}

# read in theme info into ThemeVariables

# TODO: Implement `New` site scaffolding

# loop through files
    # check if file is to be "published"
    # if not, don't process

    # read "Front Matter" YAML and
    # save to PageVariables hash table
    # if not defined, this is a "Static File"

    # consider "Includes" from _includes directory

    # TODO: Add posts and permalink handling.

    # read "Layout"
    # TODO: implement Layout inheritance by pre-parsing files in _layouts

    # for processing, superimpose PageVariables on GlobalVariables

    # create output file at same location or
    # one defined in "permalink"
    # which has "Placeholders" to modify the location through variables
