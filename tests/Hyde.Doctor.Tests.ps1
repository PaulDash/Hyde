Describe 'Hyde doctor pipeline' {
    BeforeAll {
        # Import the module once so each test can call the public entry points directly.
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $modulePath = Join-Path -Path $projectRoot -ChildPath 'src\Hyde.psm1'
        $entryScriptPath = Join-Path -Path $projectRoot -ChildPath 'src\Hyde.ps1'
        Import-Module $modulePath

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

    It 'reports a healthy site with no issues' {
        $siteRoot = New-TestSiteDirectory -Name 'doctor-site'
        $layoutsDirectory = Join-Path -Path $siteRoot -ChildPath '_layouts'

        [void](New-Item -Path $layoutsDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        Set-Content -LiteralPath (Join-Path -Path $layoutsDirectory -ChildPath 'default.html') -Encoding UTF8 -Value @'
<main>{{ content }}</main>
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
title: Home
layout: default
---
# Hello
'@

        $report = Test-StaticSite -Source $siteRoot -Environment development -ScriptPath $entryScriptPath

        $report.Healthy | Should -BeTrue
        $report.Issues.Count | Should -Be 0
    }

    It 'reports missing layouts and duplicate output paths' {
        $siteRoot = New-TestSiteDirectory -Name 'doctor-problem-site'
        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
title: Home
layout: missing
---
# Hello
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.html') -Encoding UTF8 -Value '<h1>Collision</h1>'

        $report = Test-StaticSite -Source $siteRoot -Environment development -ScriptPath $entryScriptPath

        $report.Healthy | Should -BeFalse
        ($report.Issues.Code -contains 'MissingLayout') | Should -BeTrue
        ($report.Issues.Code -contains 'DuplicateOutputPath') | Should -BeTrue
    }

    It 'reports invalid front matter without stopping the whole doctor run' {
        $siteRoot = New-TestSiteDirectory -Name 'doctor-front-matter-site'

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'broken.md') -Encoding UTF8 -Value @'
---
title: [unterminated
---
# Broken
'@

        $report = Test-StaticSite -Source $siteRoot -Environment development -ScriptPath $entryScriptPath

        $report.Healthy | Should -BeFalse
        $report.Issues.Count | Should -Be 1
        $report.Issues[0].Code | Should -Be 'InvalidFrontMatter'
    }
}
