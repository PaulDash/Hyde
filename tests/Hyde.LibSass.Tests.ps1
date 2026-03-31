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
        $isolatedManifestPath = Join-Path -Path $isolatedSrcRoot -ChildPath 'Hyde.psd1'

        # Create the parent folder first so Copy-Item always produces isolated-hyde\src rather than depending on destination semantics.
        [void](New-Item -Path $isolatedRoot -ItemType Directory -Force)

        # Copy the module source into an isolated folder so we can force plugin dependency absence.
        Copy-Item -LiteralPath (Join-Path -Path $projectRoot -ChildPath 'src') -Destination $isolatedRoot -Recurse -Force

        # Fail early with a useful assertion if the isolated module copy did not land where the test expects it.
        Test-Path -LiteralPath $isolatedManifestPath -PathType Leaf | Should -BeTrue

        $bundlePath = Join-Path -Path $isolatedSrcRoot -ChildPath 'Plugins\libsass-converter'
        if (Test-Path -LiteralPath $bundlePath -PathType Container) {
            Remove-Item -LiteralPath $bundlePath -Recurse -Force
        }

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

        $runnerScriptPath = Join-Path -Path $TestDrive -ChildPath 'invoke-libsass-missing-dll.ps1'
        $runnerScript = @(
            "`$ErrorActionPreference = 'Stop'"
            "Import-Module '$isolatedManifestPath' -Force"
            "Publish-StaticSite -Source '$siteRoot' -Destination '$destinationRoot' -Environment development | Out-Null"
        ) -join [Environment]::NewLine
        Set-Content -LiteralPath $runnerScriptPath -Encoding UTF8 -Value $runnerScript

        # Use a fresh PowerShell process so previously loaded LibSass assemblies in the current session do not mask the missing-bundle failure path.
        $powerShellExecutable = (Get-Process -Id $PID).Path
        $commandOutput = & $powerShellExecutable -NoProfile -File $runnerScriptPath 2>&1 | Out-String
        $exitCode = $LASTEXITCODE

        $exitCode | Should -Not -Be 0
        $commandOutput | Should -Match 'requires .*LibSassHost.*Run: .*Get-LibSassHost\.ps1'
        $commandOutput | Should -Match 'Get-LibSassHost.ps1'
    }
}
