Describe 'Hyde clean pipeline' {
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

    It 'removes destination folder, metadata file, and cache directories' {
        # Build a fake generated site tree that mirrors the paths Hyde clean is expected to remove.
        $siteRoot = New-TestSiteDirectory -Name 'site'
        $destinationRoot = Join-Path -Path $siteRoot -ChildPath '_site'

        [void](New-Item -Path $destinationRoot -ItemType Directory -Force)
        [void](New-Item -Path (Join-Path -Path $siteRoot -ChildPath '.jekyll-cache') -ItemType Directory -Force)
        [void](New-Item -Path (Join-Path -Path $siteRoot -ChildPath '.sass-cache') -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@
        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '.jekyll-metadata') -Encoding UTF8 -Value 'metadata'
        Set-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Encoding UTF8 -Value '<h1>Hello</h1>'

        # Run the real clean command and verify that all generated artifacts disappear.
        Push-Location -LiteralPath $siteRoot
        try {
            Clear-StaticSite -ScriptPath $entryScriptPath | Out-Null
        } finally {
            Pop-Location
        }

        Test-Path -LiteralPath $destinationRoot | Should -BeFalse
        Test-Path -LiteralPath (Join-Path -Path $siteRoot -ChildPath '.jekyll-metadata') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path -Path $siteRoot -ChildPath '.jekyll-cache') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path -Path $siteRoot -ChildPath '.sass-cache') | Should -BeFalse
    }

    It 'removes an overridden destination folder inside the source tree' {
        # Clean should respect an explicit destination override as long as it stays inside the site tree.
        $siteRoot = New-TestSiteDirectory -Name 'site'
        $destinationRoot = Join-Path -Path $siteRoot -ChildPath 'public'

        [void](New-Item -Path $destinationRoot -ItemType Directory -Force)
        Set-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Encoding UTF8 -Value '<h1>Hello</h1>'
        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        Push-Location -LiteralPath $siteRoot
        try {
            Clear-StaticSite -Destination '.\public' -ScriptPath $entryScriptPath | Out-Null
        } finally {
            Pop-Location
        }

        Test-Path -LiteralPath $destinationRoot | Should -BeFalse
    }

    It 'emits verbose output for clean targets' {
        $siteRoot = New-TestSiteDirectory -Name 'verbose-clean-site'
        $destinationRoot = Join-Path -Path $siteRoot -ChildPath '_site'

        [void](New-Item -Path $destinationRoot -ItemType Directory -Force)
        [void](New-Item -Path (Join-Path -Path $siteRoot -ChildPath '.jekyll-cache') -ItemType Directory -Force)
        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        Push-Location -LiteralPath $siteRoot
        try {
            $verboseRecords = @(Clear-StaticSite -ScriptPath $entryScriptPath -Verbose 4>&1)
        } finally {
            Pop-Location
        }
        $verboseText = $verboseRecords | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message }

        $verboseText | Should -Contain "Cleaning generated content for '$siteRoot'."
        $verboseText | Should -Contain "Removing destination folder at '$destinationRoot'."
    }

    It 'supports WhatIf without removing generated output' {
        $siteRoot = New-TestSiteDirectory -Name 'whatif-clean-site'
        $destinationRoot = Join-Path -Path $siteRoot -ChildPath '_site'

        [void](New-Item -Path $destinationRoot -ItemType Directory -Force)
        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@
        Set-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Encoding UTF8 -Value '<h1>Hello</h1>'

        Push-Location -LiteralPath $siteRoot
        try {
            Clear-StaticSite -ScriptPath $entryScriptPath -WhatIf | Out-Null
        } finally {
            Pop-Location
        }

        Test-Path -LiteralPath $destinationRoot | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') | Should -BeTrue
    }

    It 'refuses to remove a destination that is itself a site source directory' {
        $siteRoot = New-TestSiteDirectory -Name 'site'
        $generatedDirectory = Join-Path -Path $siteRoot -ChildPath '_site'

        [void](New-Item -Path $generatedDirectory -ItemType Directory -Force)
        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        Push-Location -LiteralPath $siteRoot
        try {
            {
                Clear-StaticSite -Destination '.' -ScriptPath $entryScriptPath | Out-Null
            } | Should -Throw -ExpectedMessage '*Clean failed while removing destination folder*source of a site*'
        } finally {
            Pop-Location
        }

        Test-Path -LiteralPath $siteRoot | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') | Should -BeTrue
    }
}
