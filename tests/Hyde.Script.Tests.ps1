Describe 'Hyde module command options' {
    BeforeAll {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $moduleManifestPath = Join-Path -Path $projectRoot -ChildPath 'src\Hyde.psd1'
        Import-Module $moduleManifestPath -Force

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

    It 'shows module help through Hyde Help' {
        $helpText = @(Hyde Help | Out-String)

        $helpText | Should -Match 'PowerShell static site generator'
    }

    It 'allows Hyde Build to use source destination and environment' {
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
            Hyde Build -Source $siteRoot -Destination $destinationRoot -Environment production -Quiet
        } | Should -Not -Throw

        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') | Should -BeTrue
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

        {
            Hyde Build -Source $siteRoot -Destination $destinationRoot -Environment production -Quiet
        } | Should -Not -Throw

        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') | Should -BeTrue
    }

    It 'allows Hyde New to scaffold a site from the imported module' {
        $siteRoot = Join-Path -Path $TestDrive -ChildPath 'new-module-site'

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

        $verboseRecords = @(Hyde Build -Source $siteRoot -Destination $destinationRoot -Verbose 4>&1)
        $verboseText = $verboseRecords | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message }

        $verboseText | Should -Contain "Initializing Hyde build context."
        $verboseText | Should -Contain "Starting document rendering phase."
    }

    It 'can run the Hyde build command twice in the same session' {
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
            Hyde Build -Source $siteRoot -Destination $firstDestinationRoot -Quiet
            Hyde Build -Source $siteRoot -Destination $secondDestinationRoot -Quiet
        } | Should -Not -Throw
    }

    It 'allows Hyde New to create a blank site scaffold' {
        $siteRoot = Join-Path -Path $TestDrive -ChildPath 'new-blank-site'

        {
            Hyde New $siteRoot -Blank -Quiet
        } | Should -Not -Throw

        Test-Path -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_layouts') | Should -BeFalse
    }

    It 'treats Source as SourcePath for Clean via PowerShell partial parameter matching' {
        $siteRoot = New-TestSiteDirectory -Name 'clean-source-alias-site'
        $destinationRoot = Join-Path -Path $siteRoot -ChildPath '_site'

        [void](New-Item -Path $destinationRoot -ItemType Directory -Force)
        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        {
            Hyde Clean -Source $siteRoot -Quiet
        } | Should -Not -Throw

        Test-Path -LiteralPath $destinationRoot | Should -BeFalse
    }

    It 'allows SourcePath for Clean' {
        $siteRoot = New-TestSiteDirectory -Name 'clean-sourcepath-site'
        $destinationRoot = Join-Path -Path $siteRoot -ChildPath '_site'

        [void](New-Item -Path $destinationRoot -ItemType Directory -Force)
        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        {
            Hyde Clean -SourcePath $siteRoot -Quiet
        } | Should -Not -Throw
    }

    It 'rejects Environment for Clean' {
        {
            Hyde Clean -Environment production
        } | Should -Throw -ExpectedMessage "*parameter name 'Environment'*"
    }

    It 'rejects Destination for Doctor' {
        {
            Hyde Doctor -Destination '.\_site'
        } | Should -Throw -ExpectedMessage "*parameter name 'Destination'*"
    }
}
