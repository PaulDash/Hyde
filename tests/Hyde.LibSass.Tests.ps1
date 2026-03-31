Describe 'Hyde libsass-converter behavior' {
    BeforeAll {
        $projectRoot = Split-Path -Parent $PSScriptRoot

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

    It 'fails with actionable guidance when libsass DLLs are missing' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $isolatedRoot = Join-Path -Path $TestDrive -ChildPath 'isolated-hyde'
        $isolatedSrcRoot = Join-Path -Path $isolatedRoot -ChildPath 'src'

        # Copy the module source into an isolated folder so we can force plugin dependency absence.
        Copy-Item -LiteralPath (Join-Path -Path $projectRoot -ChildPath 'src') -Destination $isolatedRoot -Recurse -Force

        $bundlePath = Join-Path -Path $isolatedSrcRoot -ChildPath 'Plugins\libsass-converter\lib'
        if (Test-Path -LiteralPath $bundlePath -PathType Container) {
            Remove-Item -LiteralPath $bundlePath -Recurse -Force
        }

        Import-Module (Join-Path -Path $isolatedSrcRoot -ChildPath 'Hyde.psd1') -Force

        $siteRoot = New-TestSiteDirectory -Name 'libsass-missing-dll-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'libsass-missing-dll-output'
        $assetsDirectory = Join-Path -Path $siteRoot -ChildPath 'assets'

        [void](New-Item -Path $assetsDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
plugins:
  - libsass-converter
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
title: Home
---
# Hello
'@

        Set-Content -LiteralPath (Join-Path -Path $assetsDirectory -ChildPath 'main.scss') -Encoding UTF8 -Value @'
$color: #333;
body { color: $color; }
'@

        {
            Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development | Out-Null
        } | Should -Throw -ExpectedMessage "*requires bundled LibSassHost DLLs*Get-LibSassHost.ps1*"
    }
}
