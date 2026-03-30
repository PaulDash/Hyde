Describe 'Hyde module manifest' {
    BeforeAll {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $moduleRoot = Join-Path -Path $projectRoot -ChildPath 'src'
        $moduleManifestPath = Join-Path -Path $moduleRoot -ChildPath 'Hyde.psd1'
    }

    It 'loads successfully through Test-ModuleManifest' {
        {
            Test-ModuleManifest -Path $moduleManifestPath | Out-Null
        } | Should -Not -Throw

        $manifestData = Import-PowerShellDataFile -Path $moduleManifestPath
        $manifestData.RootModule | Should -BeExactly 'Hyde.psm1'
    }

    It 'imports and exports the expected public functions' {
        Import-Module $moduleManifestPath -Force

        $module = Get-Module Hyde
        $exportedFunctions = @($module.ExportedFunctions.Keys | Sort-Object)

        ($exportedFunctions -join ',') | Should -BeExactly 'Clear-StaticSite,Hyde,New-StaticSite,Publish-StaticSite,Test-StaticSite'
    }

    It 'declares the expected required modules' {
        $manifest = Test-ModuleManifest -Path $moduleManifestPath
        $requiredModules = @($manifest.RequiredModules | ForEach-Object { $_.Name } | Sort-Object)

        ($requiredModules -join ',') | Should -BeExactly 'PowerLiquid,powershell-yaml'
    }

    It 'lists only existing files in FileList' {
        $manifestData = Import-PowerShellDataFile -Path $moduleManifestPath

        foreach ($relativePath in $manifestData.FileList) {
            Test-Path -LiteralPath (Join-Path -Path $moduleRoot -ChildPath $relativePath) -PathType Leaf | Should -BeTrue
        }
    }
}
