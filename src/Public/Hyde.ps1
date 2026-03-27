<#
.SYNOPSIS
PowerShell static site generator. The ugly Mr. Hyde to the popular Jekyll.
.DESCRIPTION
Hyde is a PowerShell static site generator inspired by Jekyll. Created as a fun project to only generate a private webpage, but useful as an example when teaching about PowerShell.

The current implementation supports:
- `New`
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
Supported by: `Build`, `Clean`, `New`
.PARAMETER Blank
Creates a minimal new-site scaffold.
Supported by: `New`
.PARAMETER Environment
Sets the build environment value exposed internally during the build.
Supported by: `Build`
.PARAMETER Quiet
Suppresses Hyde information messages during execution.
Supported by: `Build`, `Clean`, `Doctor`
.EXAMPLE
Hyde Build

Builds the site using paths from configuration.
.EXAMPLE
Hyde Build -Source . -Destination .\_site

Builds the site from the current directory into `.\_site`.
.EXAMPLE
Hyde Clean

Removes the generated destination folder, metadata file, and cache directories for the site.
.EXAMPLE
Hyde New mysite

Creates a new Hyde site scaffold at `.\mysite`.
.EXAMPLE
Hyde New mysite -Blank

Creates a minimal new Hyde site scaffold at `.\mysite`.
.EXAMPLE
Hyde Doctor

Checks the site for common problems such as invalid front matter, missing layouts, and output-path conflicts.
.EXAMPLE
Hyde Help

Shows command help for the module command.
#>
function Hyde {
    [CmdletBinding()]
    param(
        # Chooses the top-level Hyde action to run from the imported module.
        [Parameter(Position = 0)]
        [ValidateSet('New', 'Build', 'Clean', 'Doctor', 'Help')]
        [string]$Command
    )

    dynamicparam {
        $dynamicParameters = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()

        function newHydeDynamicParameter {
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

        # Dynamic parameters remain the best fit for a "Hyde build" command shape because
        # parameter sets cannot branch on the value of a positional string argument.
        switch ($Command) {
            'New' {
                $dynamicParameters.Add('Destination', (newHydeDynamicParameter -Name 'Destination' -Type ([string]) -Aliases @('Path')))
                $dynamicParameters['Destination'].Attributes[0].Position = 1
                $dynamicParameters.Add('Blank', (newHydeDynamicParameter -Name 'Blank' -Type ([switch])))
                $dynamicParameters.Add('Quiet', (newHydeDynamicParameter -Name 'Quiet' -Type ([switch])))
            }
            'Build' {
                $dynamicParameters.Add('Source', (newHydeDynamicParameter -Name 'Source' -Type ([string])))
                $dynamicParameters.Add('Destination', (newHydeDynamicParameter -Name 'Destination' -Type ([string])))
                $dynamicParameters.Add('Environment', (newHydeDynamicParameter -Name 'Environment' -Type ([string]) -Aliases @('JEKYLL_ENV', 'HYDE_ENV')))
                $dynamicParameters.Add('Quiet', (newHydeDynamicParameter -Name 'Quiet' -Type ([switch])))
            }
            'Clean' {
                $dynamicParameters.Add('Destination', (newHydeDynamicParameter -Name 'Destination' -Type ([string])))
                $dynamicParameters.Add('Quiet', (newHydeDynamicParameter -Name 'Quiet' -Type ([switch])))
            }
            'Doctor' {
                $dynamicParameters.Add('Source', (newHydeDynamicParameter -Name 'Source' -Type ([string])))
                $dynamicParameters.Add('Quiet', (newHydeDynamicParameter -Name 'Quiet' -Type ([switch])))
            }
        }

        return $dynamicParameters
    }

    begin {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        if ($PSBoundParameters.ContainsKey('Quiet') -and $VerbosePreference -eq 'Continue') {
            throw "It doesn't make sense to ask for verbose output AND to keep quiet!"
        }

        switch ($Command) {
            'New' {
                if (-not $PSBoundParameters.ContainsKey('Destination') -or [string]::IsNullOrWhiteSpace([string]$PSBoundParameters['Destination'])) {
                    throw "The New command requires a destination path."
                }

                $commandParameters = @{
                    Destination = [string]$PSBoundParameters['Destination']
                    Quiet       = [bool]($PSBoundParameters.ContainsKey('Quiet') -and $PSBoundParameters['Quiet'])
                }

                if ($PSBoundParameters.ContainsKey('Blank')) {
                    $commandParameters['Blank'] = [bool]$PSBoundParameters['Blank']
                }

                if ($VerbosePreference -eq 'Continue') {
                    $commandParameters['Verbose'] = $true
                }

                New-StaticSite @commandParameters
            }
            'Build' {
                $commandParameters = @{
                    Environment = if ($PSBoundParameters.ContainsKey('Environment')) { [string]$PSBoundParameters['Environment'] } else { 'development' }
                    Quiet       = [bool]($PSBoundParameters.ContainsKey('Quiet') -and $PSBoundParameters['Quiet'])
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
                    Quiet = [bool]($PSBoundParameters.ContainsKey('Quiet') -and $PSBoundParameters['Quiet'])
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
                    Quiet = [bool]($PSBoundParameters.ContainsKey('Quiet') -and $PSBoundParameters['Quiet'])
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
                Get-Help -Name Hyde
            }
            default {
                throw "Choose one of: Build, New, Clean, Doctor, Help. Use 'Help' to see command documentation."
            }
        }
    }
}
