Describe 'Hyde script command options' {
    BeforeAll {
        # Use the script entry point so these tests exercise the command wrapper rather than the module functions.
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $entryScriptPath = Join-Path -Path $projectRoot -ChildPath 'src\Hyde.ps1'

        function New-TestSiteDirectory {
            param(
                [Parameter(Mandatory = $true)]
                [string]$Name
            )

            $path = Join-Path -Path $TestDrive -ChildPath $Name
            [void](New-Item -Path $path -ItemType Directory -Force)
            return $path
        }
    }

    It 'allows Build to use source destination and environment' {
        $siteRoot = New-TestSiteDirectory -Name 'build-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'build-output'

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@
        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
title: Home
---
# Hello
'@

        {
            & $entryScriptPath Build -Source $siteRoot -Destination $destinationRoot -Environment production -Quiet
        } | Should -Not -Throw
    }

    It 'passes Verbose through to the called command' {
        $siteRoot = New-TestSiteDirectory -Name 'verbose-build-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'verbose-build-output'

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@
        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
title: Home
---
# Hello
'@

        $verboseRecords = @(& $entryScriptPath Build -Source $siteRoot -Destination $destinationRoot -Verbose 4>&1)
        $verboseText = $verboseRecords | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message }

        $verboseText | Should -Contain "Initializing Hyde build context."
        $verboseText | Should -Contain "Starting document rendering phase."
    }

    It 'rejects Source for Clean' {
        {
            & $entryScriptPath Clean -Source '.'
        } | Should -Throw -ExpectedMessage "*parameter name 'Source'*"
    }

    It 'rejects Environment for Clean' {
        {
            & $entryScriptPath Clean -Environment production
        } | Should -Throw -ExpectedMessage "*parameter name 'Environment'*"
    }

    It 'rejects Destination for Doctor' {
        {
            & $entryScriptPath Doctor -Destination '.\_site'
        } | Should -Throw -ExpectedMessage "*parameter name 'Destination'*"
    }
}
