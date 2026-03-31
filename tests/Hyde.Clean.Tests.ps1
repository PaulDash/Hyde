Describe 'Hyde clean pipeline' {
    BeforeAll {
        # Import the module once so each test can call the public entry points directly.
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
            Clear-StaticSite | Out-Null
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
            Clear-StaticSite -Destination '.\public' | Out-Null
        } finally {
            Pop-Location
        }

        Test-Path -LiteralPath $destinationRoot | Should -BeFalse
    }

    It 'uses SourcePath to read the configured destination from another site root' {
        $siteRoot = New-TestSiteDirectory -Name 'remote-site'
        $destinationRoot = Join-Path -Path $siteRoot -ChildPath 'output'
        $workingDirectory = New-TestSiteDirectory -Name 'clean-caller'

        [void](New-Item -Path $destinationRoot -ItemType Directory -Force)
        Set-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Encoding UTF8 -Value '<h1>Hello</h1>'
        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
destination: output
'@

        Push-Location -LiteralPath $workingDirectory
        try {
            Clear-StaticSite -SourcePath $siteRoot | Out-Null
        } finally {
            Pop-Location
        }

        Test-Path -LiteralPath $destinationRoot | Should -BeFalse
    }

    It 'lets Destination override the configured destination discovered through SourcePath' {
        $siteRoot = New-TestSiteDirectory -Name 'override-site'
        $configuredDestinationRoot = Join-Path -Path $siteRoot -ChildPath 'output'
        $overrideDestinationRoot = Join-Path -Path $siteRoot -ChildPath 'public'
        $workingDirectory = New-TestSiteDirectory -Name 'override-caller'

        [void](New-Item -Path $configuredDestinationRoot -ItemType Directory -Force)
        [void](New-Item -Path $overrideDestinationRoot -ItemType Directory -Force)
        Set-Content -LiteralPath (Join-Path -Path $configuredDestinationRoot -ChildPath 'index.html') -Encoding UTF8 -Value '<h1>Configured</h1>'
        Set-Content -LiteralPath (Join-Path -Path $overrideDestinationRoot -ChildPath 'index.html') -Encoding UTF8 -Value '<h1>Override</h1>'
        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
destination: output
'@

        Push-Location -LiteralPath $workingDirectory
        try {
            Clear-StaticSite -SourcePath $siteRoot -Destination $overrideDestinationRoot | Out-Null
        } finally {
            Pop-Location
        }

        Test-Path -LiteralPath $overrideDestinationRoot | Should -BeFalse
        Test-Path -LiteralPath $configuredDestinationRoot | Should -BeTrue
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
            $verboseRecords = @(Clear-StaticSite -Verbose 4>&1)
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
            Clear-StaticSite -WhatIf | Out-Null
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
                Clear-StaticSite -Destination '.' | Out-Null
            } | Should -Throw -ExpectedMessage '*Clean failed while removing destination folder*source of a site*'
        } finally {
            Pop-Location
        }

        Test-Path -LiteralPath $siteRoot | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') | Should -BeTrue
    }

    It 'refuses to remove a destination that is a parent of source path' {
        $parentRoot = Join-Path -Path $TestDrive -ChildPath 'clean-parent-root'
        $siteRoot = Join-Path -Path $parentRoot -ChildPath 'nested-site'

        [void](New-Item -Path $siteRoot -ItemType Directory -Force)
        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        Push-Location -LiteralPath $siteRoot
        try {
            {
                Clear-StaticSite -Destination '..' | Out-Null
            } | Should -Throw -ExpectedMessage '*Clean failed while removing destination folder*parent of source path*'
        } finally {
            Pop-Location
        }

        Test-Path -LiteralPath $siteRoot | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') | Should -BeTrue
    }

    It 'refuses to remove a destination that resolves to a drive root' {
        if (-not $IsWindows) {
            Set-ItResult -Skipped -Because 'Drive-root safety test is Windows-specific.'
            return
        }

        $siteRoot = New-TestSiteDirectory -Name 'drive-root-clean-site'
        $driveRoot = [System.IO.Path]::GetPathRoot($siteRoot)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        Push-Location -LiteralPath $siteRoot
        try {
            {
                Clear-StaticSite -Destination $driveRoot | Out-Null
            } | Should -Throw -ExpectedMessage '*Clean failed while removing destination folder*drive root*'
        } finally {
            Pop-Location
        }

        Test-Path -LiteralPath $siteRoot | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') | Should -BeTrue
    }
}
