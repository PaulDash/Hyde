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
                throw 'TODO: Implement the New command to scaffold a site.'
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
