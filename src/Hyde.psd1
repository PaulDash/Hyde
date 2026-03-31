@{
    RootModule        = 'Hyde.psm1'
    ModuleVersion     = '0.5.2'
    GUID              = '42b2840d-8661-47ad-b051-9c3d868fc3d5'
    Author            = 'Paul Dash'
    CompanyName       = 'Paul Dash'
    Copyright         = '© 2024-2026 Paul Dash'
    Description       = 'PowerShell static site generator inspired by Jekyll.'
    PowerShellVersion = '7.0'

    FunctionsToExport = @(
        'Hyde',
        'New-StaticSite',
        'New-StaticSiteTheme',
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
        'Public\New-StaticSiteTheme.ps1',
        'Public\Publish-StaticSite.ps1',
        'Public\Clear-StaticSite.ps1',
        'Public\Test-StaticSite.ps1',
        'Private\Hyde.Config.ps1',
        'Private\Hyde.Discovery.ps1',
        'Private\Hyde.Plugins.ps1',
        'Private\Hyde.Render.ps1',
        'Private\Hyde.Variables.ps1',
        'Private\Hyde.Utility.ps1',
        'Private\Hyde.Validation.ps1',
        'Private\HydeTypes.ps1',
        'Plugins\seo-tag.ps1',
        'Plugins\titles-from-headings.ps1',
        'Plugins\libsass-converter.ps1'
    )

        PrivateData = @{
        PSData = @{
            Tags         = @('Website', 'StaticSite', 'StaticWebsite', 'Builder', 'Liquid', 'Template', 'TemplateEngine', 'PSEdition_Core')
            ProjectURI   = 'https://github.com/PaulDash/Hyde'
            LicenseURI   = 'https://github.com/PaulDash/Hyde/raw/main/LICENSE.md'
            IconURI      = 'https://github.com/PaulDash/Hyde/raw/main/res/Icon_85x85.png'
            ReleaseNotes = 'PowerShell static site generator. The ugly Mr. Hyde to the popular Jekyll (https://jekyllrb.com/).

# Implemented Features

- `_config.yml` loading and built-in defaults
- Pages, posts, collections, and static file handling
- YAML Front Matter parsing and integration with content objects
- Liquid rendering through the standalone `PowerLiquid` module
- Markdown rendering using built-in logic

# 0.5.1

- Added `Hyde New-Theme` and `New-StaticSiteTheme` for starter theme scaffolding.

# 0.5.0


'
        }
    }
}
