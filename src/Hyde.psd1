@{
    RootModule        = 'Hyde.psm1'
    ModuleVersion     = '0.4.13'
    GUID              = '42b2840d-8661-47ad-b051-9c3d868fc3d5'
    Author            = 'Paul Wojcicki-Jarocki'
    CompanyName       = 'Paul Dash'
    Copyright         = '© 2026 Paul Dash'
    Description       = 'PowerShell static site generator inspired by Jekyll.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Hyde',
        'New-StaticSite',
        'Publish-StaticSite',
        'Clear-StaticSite',
        'Test-StaticSite'
    )

    AliasesToExport   = @()
    CmdletsToExport   = @()
    VariablesToExport = @()

    RequiredModules   = @('powershell-yaml','PowerLiquid')

    FileList          = @(
        'Hyde.psd1',
        'Hyde.psm1',
        'globalConfig.yaml',
        'Public\Hyde.ps1',
        'Public\New-StaticSite.ps1',
        'Public\Publish-StaticSite.ps1',
        'Public\Clear-StaticSite.ps1',
        'Public\Test-StaticSite.ps1',
        'Private\Hyde.Config.ps1',
        'Private\Hyde.Discovery.ps1',
        'Private\Hyde.Plugins.ps1',
        'Private\Hyde.Render.ps1',
        'Private\Hyde.Utility.ps1',
        'Private\Hyde.Validation.ps1',
        'Private\HydeTypes.ps1',
        'Plugins\seo-tag.ps1',
        'Plugins\titles-from-headings.ps1'
    )
}
