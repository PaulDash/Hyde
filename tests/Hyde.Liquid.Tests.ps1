Describe 'Hyde Liquid integration' {
    BeforeAll {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $moduleManifestPath = Join-Path -Path $projectRoot -ChildPath 'src\Hyde.psd1'
        $workspaceRoot = Split-Path -Parent $projectRoot
        $powerLiquidManifestPath = Join-Path -Path $workspaceRoot -ChildPath 'PowerLiquid\PowerLiquid.psd1'

        Import-Module $moduleManifestPath -Force
    }

    It 'imports Hyde without failing to load the PowerLiquid dependency' {
        { Import-Module $moduleManifestPath -Force } | Should -Not -Throw
    }

    It 'loads PowerLiquid from either the sibling repo or an installed module' {
        $powerLiquidModule = Get-Module PowerLiquid

        $powerLiquidModule | Should -Not -BeNullOrEmpty

        if (Test-Path -LiteralPath $powerLiquidManifestPath -PathType Leaf) {
            $powerLiquidModule.Path | Should -BeExactly $powerLiquidManifestPath
        } else {
            $powerLiquidModule.Name | Should -BeExactly 'PowerLiquid'
        }
    }

    It 'can submit a minimal template render request to the external Liquid module' {
        $result = Invoke-LiquidTemplate -Template 'Hello {{ page.title }}' -Context @{
            page = @{
                title = 'Hyde'
            }
        }

        $result | Should -BeExactly 'Hello Hyde'
    }
}
