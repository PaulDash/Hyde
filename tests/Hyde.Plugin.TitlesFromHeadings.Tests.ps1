Describe 'Hyde titles-from-headings plugin' {
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

    It 'supports the plugin self-install contract as a no-op' {
        $pluginPath = Join-Path -Path $projectRoot -ChildPath 'src\Plugins\titles-from-headings.ps1'

        # titles-from-headings has no external dependencies, so -Install should succeed immediately.
        $installResult = & $pluginPath -Install
        $installVerboseRecords = @(& $pluginPath -Install -Verbose 4>&1)
        $verboseMessages = @($installVerboseRecords | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message })

        $installResult | Should -BeTrue
        $verboseMessages | Should -Contain "Plugin 'titles-from-headings' does not require installation."
    }

    It 'fills missing front matter title from the first markdown h1 heading' {
        $siteRoot = New-TestSiteDirectory -Name 'plugin-title-from-heading-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'plugin-title-from-heading-output'

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
plugins:
  - titles-from-headings
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
layout: default
---
# Heading Powered Title

Hello from Hyde.
'@

        [void](New-Item -Path (Join-Path -Path $siteRoot -ChildPath '_layouts') -ItemType Directory -Force)
        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_layouts\default.html') -Encoding UTF8 -Value @'
<!DOCTYPE html>
<html>
<head>
  <title>{{ page.title }}</title>
</head>
<body>
{{ content }}
</body>
</html>
'@

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw

        $indexOutput | Should -Match '<title>Heading Powered Title</title>'
        $context.LoadedPlugins.Name | Should -Contain 'titles-from-headings'
    }
}