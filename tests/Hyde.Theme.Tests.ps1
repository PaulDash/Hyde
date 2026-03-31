Describe 'Hyde theme scaffolding' {
    BeforeAll {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $moduleManifestPath = Join-Path -Path $projectRoot -ChildPath 'src\Hyde.psd1'
        Import-Module $moduleManifestPath -Force

        function New-TestThemeDirectory {
            param(
                [Parameter(Mandatory = $true)]
                [string]$Name
            )

            # Each test gets an isolated destination under TestDrive so filesystem assertions stay deterministic.
            return (Join-Path -Path $TestDrive -ChildPath $Name)
        }

        function Assert-BaseThemeScaffold {
            param(
                [Parameter(Mandatory = $true)]
                [string]$ThemeRoot
            )

            # These files define the reusable parts of the theme and should exist in both scaffold modes.
            Test-Path -LiteralPath (Join-Path -Path $ThemeRoot -ChildPath '_config.yml') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path -Path $ThemeRoot -ChildPath '_layouts\default.html') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path -Path $ThemeRoot -ChildPath '_includes\head.html') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path -Path $ThemeRoot -ChildPath '_includes\site-header.html') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path -Path $ThemeRoot -ChildPath '_sass\_theme.scss') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path -Path $ThemeRoot -ChildPath 'assets\css\site.scss') | Should -BeTrue
        }
    }

    It 'allows Hyde New-Theme to scaffold a previewable theme from the imported module' {
        $themeRoot = New-TestThemeDirectory -Name 'preview-theme'

        # Route through the top-level Hyde command to verify the command parser forwards to New-StaticTheme.
        {
            Hyde New-Theme $themeRoot -Quiet
        } | Should -Not -Throw

        Assert-BaseThemeScaffold -ThemeRoot $themeRoot

        # The default mode should produce a page that makes the scaffold immediately buildable.
        Test-Path -LiteralPath (Join-Path -Path $themeRoot -ChildPath 'index.md') | Should -BeTrue
    }

    It 'allows New-StaticTheme to scaffold a portable theme directly' {
        $themeRoot = New-TestThemeDirectory -Name 'portable-theme'

        # Call the cmdlet directly to verify the exported Verb-Noun surface independently of Hyde routing.
        $createdTheme = New-StaticTheme -Destination $themeRoot -Portable -Quiet

        $createdTheme | Should -BeOfType ([System.IO.DirectoryInfo])
        Assert-BaseThemeScaffold -ThemeRoot $themeRoot

        # Portable mode omits preview content so the result reads as a reusable package skeleton.
        Test-Path -LiteralPath (Join-Path -Path $themeRoot -ChildPath 'index.md') | Should -BeFalse
    }

    It 'rejects Hyde New-Theme when the destination already exists and is not empty' {
        $themeRoot = New-TestThemeDirectory -Name 'existing-theme'
        [void](New-Item -Path $themeRoot -ItemType Directory -Force)
        Set-Content -LiteralPath (Join-Path -Path $themeRoot -ChildPath 'keep.txt') -Encoding UTF8 -Value 'occupied'

        # Rejecting non-empty destinations keeps the theme scaffold semantics aligned with New-StaticSite.
        {
            Hyde New-Theme $themeRoot -Quiet
        } | Should -Throw -ExpectedMessage '*destination already exists and is not empty*'
    }
}