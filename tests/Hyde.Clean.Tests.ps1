Describe 'Hyde clean pipeline' {
    BeforeAll {
        # Import the module once so each test can call the public entry points directly.
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $modulePath = Join-Path -Path $projectRoot -ChildPath 'src\Hyde.psm1'
        $entryScriptPath = Join-Path -Path $projectRoot -ChildPath 'src\Hyde.ps1'
        Import-Module $modulePath -Force
    }

    It 'removes destination folder, metadata file, and cache directories' {
        # Build a fake generated site tree that mirrors the paths Hyde clean is expected to remove.
        $siteRoot = Join-Path -Path $TestDrive -ChildPath 'site'
        $destinationRoot = Join-Path -Path $siteRoot -ChildPath '_site'

        [void](New-Item -Path $siteRoot -ItemType Directory -Force)
        [void](New-Item -Path $destinationRoot -ItemType Directory -Force)
        [void](New-Item -Path (Join-Path -Path $siteRoot -ChildPath '.jekyll-cache') -ItemType Directory -Force)
        [void](New-Item -Path (Join-Path -Path $siteRoot -ChildPath '.sass-cache') -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@
        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '.jekyll-metadata') -Encoding UTF8 -Value 'metadata'
        Set-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Encoding UTF8 -Value '<h1>Hello</h1>'

        # Run the real clean command and verify that all generated artifacts disappear.
        Invoke-HydeClean -Source $siteRoot -Environment development -ScriptPath $entryScriptPath | Out-Null

        Test-Path -LiteralPath $destinationRoot | Should Be $false
        Test-Path -LiteralPath (Join-Path -Path $siteRoot -ChildPath '.jekyll-metadata') | Should Be $false
        Test-Path -LiteralPath (Join-Path -Path $siteRoot -ChildPath '.jekyll-cache') | Should Be $false
        Test-Path -LiteralPath (Join-Path -Path $siteRoot -ChildPath '.sass-cache') | Should Be $false
    }

    It 'removes an overridden destination folder inside the source tree' {
        # Clean should respect an explicit destination override as long as it stays inside the site tree.
        $siteRoot = Join-Path -Path $TestDrive -ChildPath 'site'
        $destinationRoot = Join-Path -Path $siteRoot -ChildPath 'public'

        [void](New-Item -Path $siteRoot -ItemType Directory -Force)
        [void](New-Item -Path $destinationRoot -ItemType Directory -Force)
        Set-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Encoding UTF8 -Value '<h1>Hello</h1>'

        Invoke-HydeClean -Source $siteRoot -Destination '.\public' -Environment development -ScriptPath $entryScriptPath | Out-Null

        Test-Path -LiteralPath $destinationRoot | Should Be $false
    }
}
