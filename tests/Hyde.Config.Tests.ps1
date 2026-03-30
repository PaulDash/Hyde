Describe 'Hyde configuration and context initialization' {
    BeforeAll {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $moduleRoot = Join-Path -Path $projectRoot -ChildPath 'src'
        $moduleManifestPath = Join-Path -Path $moduleRoot -ChildPath 'Hyde.psd1'
        $globalConfigPath = Join-Path -Path $moduleRoot -ChildPath 'globalConfig.yaml'

        Import-Module $moduleManifestPath -Force
        $hydeModule = Get-Module Hyde

        function Invoke-InHydeModule {
            param(
                [Parameter(Mandatory = $true)]
                [scriptblock]$ScriptBlock,

                [object[]]$ArgumentList = @()
            )

            & $hydeModule $ScriptBlock @ArgumentList
        }

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

    It 'reads the bundled global configuration file' {
        $config = Invoke-InHydeModule -ScriptBlock {
            param($path)
            readHydeConfigFile -Path $path
        } -ArgumentList $globalConfigPath

        $config.source | Should -BeExactly '.'
        $config.destination | Should -BeExactly './_site'
        $config.collections.posts.output | Should -BeTrue
        $config.ContainsKey('plugins') | Should -BeTrue
    }

    It 'returns an empty hashtable for an empty configuration file' {
        $configPath = Join-Path -Path $TestDrive -ChildPath 'empty.yml'
        Set-Content -LiteralPath $configPath -Encoding UTF8 -Value ''

        $config = Invoke-InHydeModule -ScriptBlock {
            param($path)
            readHydeConfigFile -Path $path
        } -ArgumentList $configPath

        $config.Count | Should -Be 0
    }

    It 'rejects a missing configuration file with context' {
        $missingPath = Join-Path -Path $TestDrive -ChildPath 'missing.yml'

        {
            Invoke-InHydeModule -ScriptBlock {
                param($path)
                readHydeConfigFile -Path $path
            } -ArgumentList $missingPath
        } | Should -Throw -ExpectedMessage "*Could not validate location of configuration file*missing.yml*"
    }

    It 'merges nested site configuration values while preserving siblings' {
        $existing = @{
            liquid = @{
                error_mode = 'warn'
                strict_filters = $false
            }
            permalink = 'date'
        }
        $difference = @{
            liquid = @{
                strict_filters = $true
            }
            destination = 'public'
        }

        $merged = Invoke-InHydeModule -ScriptBlock {
            param($current, $incoming)
            mergeHydeConfig -Existing $current -Difference $incoming
            return $current
        } -ArgumentList $existing, $difference

        $merged.liquid.error_mode | Should -BeExactly 'warn'
        $merged.liquid.strict_filters | Should -BeTrue
        $merged.permalink | Should -BeExactly 'date'
        $merged.destination | Should -BeExactly 'public'
    }

    It 'resolves relative paths against the provided base path when the target may not exist' {
        $basePath = New-TestSiteDirectory -Name 'path-root'

        $resolvedPath = Invoke-InHydeModule -ScriptBlock {
            param($pathBase)
            resolveHydePath -Location '.\content' -BasePath $pathBase -MayNotExist
        } -ArgumentList $basePath

        $resolvedPath | Should -BeExactly (Join-Path -Path $basePath -ChildPath 'content')
    }

    It 'preserves rooted absolute paths when resolving destinations' {
        $absolutePath = Join-Path -Path $TestDrive -ChildPath 'absolute-output'

        $resolvedPath = Invoke-InHydeModule -ScriptBlock {
            param($pathValue)
            resolveHydePath -Location $pathValue -MayNotExist
        } -ArgumentList $absolutePath

        $resolvedPath | Should -BeExactly $absolutePath
    }

    It 'rejects MayNotExist targets whose parent directory cannot be resolved' {
        $basePath = New-TestSiteDirectory -Name 'missing-parent-root'

        {
            Invoke-InHydeModule -ScriptBlock {
                param($pathBase)
                resolveHydePath -Location '.\missing\child\output' -BasePath $pathBase -MayNotExist
            } -ArgumentList $basePath
        } | Should -Throw -ExpectedMessage '*Could not resolve target path*'
    }

    It 'initializes build context from Hyde defaults when the site has no _config.yml' {
        $siteRoot = New-TestSiteDirectory -Name 'default-context-site'

        $context = Invoke-InHydeModule -ScriptBlock {
            param($sourcePath, $rootPath)
            initializeHydeBuildContext -Source $sourcePath -Environment 'development' -ModuleRoot $rootPath -Version '0.4.13'
        } -ArgumentList $siteRoot, $moduleRoot

        $context.SourcePath | Should -BeExactly $siteRoot
        $context.DestinationPath | Should -BeExactly (Join-Path -Path $siteRoot -ChildPath '_site')
        $context.Settings.destination | Should -BeExactly './_site'
        $context.Site.collections.posts.output | Should -BeTrue
    }

    It 'lets site configuration override defaults and CLI destination win last' {
        $siteRoot = New-TestSiteDirectory -Name 'override-context-site'
        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Override Test
destination: configured-output
baseurl: /docs
'@

        $context = Invoke-InHydeModule -ScriptBlock {
            param($sourcePath, $destinationPath, $rootPath)
            initializeHydeBuildContext -Source $sourcePath -Destination $destinationPath -Environment 'production' -ModuleRoot $rootPath -Version '0.4.13'
        } -ArgumentList $siteRoot, 'cli-output', $moduleRoot

        $context.Environment | Should -BeExactly 'production'
        $context.Site.baseurl | Should -BeExactly '/docs'
        $context.Settings.destination | Should -BeExactly 'cli-output'
        $context.DestinationPath | Should -BeExactly (Join-Path -Path $siteRoot -ChildPath 'cli-output')
    }

    It 'initializes configured collections into both site.collections and top-level site arrays' {
        $siteRoot = New-TestSiteDirectory -Name 'collections-context-site'
        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Collections Test
collections:
  books:
    output: true
  notes:
    output: false
'@

        $context = Invoke-InHydeModule -ScriptBlock {
            param($sourcePath, $rootPath)
            initializeHydeBuildContext -Source $sourcePath -Environment 'development' -ModuleRoot $rootPath -Version '0.4.13'
        } -ArgumentList $siteRoot, $moduleRoot

        $context.Site.collections.ContainsKey('books') | Should -BeTrue
        $context.Site.collections.books.output | Should -BeTrue
        $context.Site.collections.ContainsKey('notes') | Should -BeTrue
        $context.Site.collections.notes.output | Should -BeFalse
        $context.Site.ContainsKey('books') | Should -BeTrue
        $context.Site.ContainsKey('notes') | Should -BeTrue
    }
}
