Describe 'Hyde script command options' {
    BeforeAll {
        # Use the script entry point so these tests exercise the command wrapper rather than the module functions.
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $entryScriptPath = Join-Path -Path $projectRoot -ChildPath 'src\Hyde.ps1'
        $moduleManifestPath = Join-Path -Path $projectRoot -ChildPath 'src\Hyde.psd1'

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

    It 'allows Hyde Build to be called from the imported module' {
        $siteRoot = New-TestSiteDirectory -Name 'module-build-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'module-build-output'

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@
        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
title: Home
---
# Hello
'@

        Import-Module $moduleManifestPath

        {
            Hyde Build -Source $siteRoot -Destination $destinationRoot -Environment production -Quiet
        } | Should -Not -Throw

        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') | Should -BeTrue
    }

    It 'allows Hyde New to scaffold a site from the imported module' {
        $siteRoot = Join-Path -Path $TestDrive -ChildPath 'new-module-site'

        Import-Module $moduleManifestPath

        {
            Hyde New $siteRoot -Quiet
        } | Should -Not -Throw

        Test-Path -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_layouts\default.html') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') | Should -BeTrue

        {
            Hyde Build -Source $siteRoot -Destination (Join-Path -Path $TestDrive -ChildPath 'new-module-output') -Quiet
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

    It 'can run the script build command twice in the same session' {
        $siteRoot = New-TestSiteDirectory -Name 'repeat-build-site'
        $firstDestinationRoot = Join-Path -Path $TestDrive -ChildPath 'repeat-build-output-1'
        $secondDestinationRoot = Join-Path -Path $TestDrive -ChildPath 'repeat-build-output-2'

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
            & $entryScriptPath Build -Source $siteRoot -Destination $firstDestinationRoot -Quiet
            & $entryScriptPath Build -Source $siteRoot -Destination $secondDestinationRoot -Quiet
        } | Should -Not -Throw
    }

    It 'allows the wrapper script to create a blank site scaffold' {
        $siteRoot = Join-Path -Path $TestDrive -ChildPath 'new-wrapper-site'

        {
            & $entryScriptPath New $siteRoot -Blank -Quiet
        } | Should -Not -Throw

        Test-Path -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_layouts') | Should -BeFalse
    }

    It 'rejects Source for Clean' {
        {
            & $entryScriptPath Clean -Source '.'
        } | Should -Throw -ExpectedMessage "*parameter name 'Source'*"
    }

    It 'allows SourcePath for Clean' {
        $siteRoot = New-TestSiteDirectory -Name 'clean-sourcepath-site'
        $destinationRoot = Join-Path -Path $siteRoot -ChildPath '_site'

        [void](New-Item -Path $destinationRoot -ItemType Directory -Force)
        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        {
            & $entryScriptPath Clean -SourcePath $siteRoot -Quiet
        } | Should -Not -Throw
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
