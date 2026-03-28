@{
    RootModule        = 'Hyde.psm1'
    ModuleVersion     = '0.4.2'
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

    RequiredModules   = @('powershell-yaml')

    FileList          = @(
        'Hyde.psd1',
        'Hyde.psm1',
        'Hyde.ps1',
        'globalConfig.yaml'
    )
}
