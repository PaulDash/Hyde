Describe 'Hyde file-based themes' {
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

        function New-TestThemeDirectory {
            param(
                [Parameter(Mandatory = $true)]
                [string]$Name
            )

            $path = Join-Path -Path $TestDrive -ChildPath $Name
            [void](New-Item -Path $path -ItemType Directory -Force)
            return $path
        }
    }

    It 'uses theme layouts, includes, assets, and config as fallbacks during build' {
        $themeRoot = New-TestThemeDirectory -Name 'fallback-theme'
        $siteRoot = New-TestSiteDirectory -Name 'fallback-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'fallback-output'

        [void](New-Item -Path (Join-Path -Path $themeRoot -ChildPath '_layouts') -ItemType Directory -Force)
        [void](New-Item -Path (Join-Path -Path $themeRoot -ChildPath '_includes') -ItemType Directory -Force)
        [void](New-Item -Path (Join-Path -Path $themeRoot -ChildPath 'assets') -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $themeRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
brand: Theme Brand
'@

        Set-Content -LiteralPath (Join-Path -Path $themeRoot -ChildPath '_layouts\default.html') -Encoding UTF8 -Value @'
<!DOCTYPE html>
<html>
<body>
  <header>{% include banner.html %}</header>
  <main data-brand="{{ site.brand }}">{{ content }}</main>
</body>
</html>
'@

        Set-Content -LiteralPath (Join-Path -Path $themeRoot -ChildPath '_includes\banner.html') -Encoding UTF8 -Value 'Theme Banner'
        Set-Content -LiteralPath (Join-Path -Path $themeRoot -ChildPath 'assets\site.css') -Encoding UTF8 -Value 'body { color: #123456; }'

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
theme_dir: ../fallback-theme
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
layout: default
---
# Theme Fallback
'@

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw
        $assetOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'assets\site.css') -Raw

        $context.ThemePath | Should -BeExactly $themeRoot
        $indexOutput | Should -Match 'Theme Banner'
        $indexOutput | Should -Match 'data-brand="Theme Brand"'
        $indexOutput | Should -Match '<h1>Theme Fallback</h1>'
        $assetOutput.Trim() | Should -BeExactly 'body { color: #123456; }'
    }

    It 'lets site layouts, includes, assets, and config override matching theme files' {
        $themeRoot = New-TestThemeDirectory -Name 'override-theme'
        $siteRoot = New-TestSiteDirectory -Name 'override-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'override-output'

        [void](New-Item -Path (Join-Path -Path $themeRoot -ChildPath '_layouts') -ItemType Directory -Force)
        [void](New-Item -Path (Join-Path -Path $themeRoot -ChildPath '_includes') -ItemType Directory -Force)
        [void](New-Item -Path (Join-Path -Path $themeRoot -ChildPath 'assets') -ItemType Directory -Force)
        [void](New-Item -Path (Join-Path -Path $siteRoot -ChildPath '_layouts') -ItemType Directory -Force)
        [void](New-Item -Path (Join-Path -Path $siteRoot -ChildPath '_includes') -ItemType Directory -Force)
        [void](New-Item -Path (Join-Path -Path $siteRoot -ChildPath 'assets') -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $themeRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
brand: Theme Brand
'@

        Set-Content -LiteralPath (Join-Path -Path $themeRoot -ChildPath '_layouts\default.html') -Encoding UTF8 -Value @'
<body class="theme-layout">{% include banner.html %}<main>{{ site.brand }} {{ content }}</main></body>
'@

        Set-Content -LiteralPath (Join-Path -Path $themeRoot -ChildPath '_includes\banner.html') -Encoding UTF8 -Value 'Theme Banner'
        Set-Content -LiteralPath (Join-Path -Path $themeRoot -ChildPath 'assets\site.css') -Encoding UTF8 -Value 'body { color: red; }'

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
theme_dir: ../override-theme
brand: Site Brand
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_layouts\default.html') -Encoding UTF8 -Value @'
<body class="site-layout">{% include banner.html %}<main>{{ site.brand }} {{ content }}</main></body>
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_includes\banner.html') -Encoding UTF8 -Value 'Site Banner'
        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'assets\site.css') -Encoding UTF8 -Value 'body { color: blue; }'

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
layout: default
---
# Local Override
'@

        Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development | Out-Null
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw
        $assetOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'assets\site.css') -Raw

        $indexOutput | Should -Match 'site-layout'
        $indexOutput | Should -Match 'Site Banner'
        $indexOutput | Should -Match 'Site Brand'
        $indexOutput | Should -Not -Match 'theme-layout'
        $assetOutput.Trim() | Should -BeExactly 'body { color: blue; }'
    }

    It 'rejects a configured theme path that does not exist' {
        $siteRoot = New-TestSiteDirectory -Name 'missing-theme-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'missing-theme-output'

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
theme_dir: ../does-not-exist
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
title: Broken Theme
---
# Broken Theme
'@

        {
            Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development
        } | Should -Throw -ExpectedMessage '*Could not find configured theme directory*'
    }
}