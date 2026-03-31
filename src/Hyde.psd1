@{
    RootModule        = 'Hyde.psm1'
    ModuleVersion     = '0.6.7'
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
        'Private\Hyde.Markdown.ps1',
        'Private\Hyde.Plugins.ps1',
        'Private\Hyde.Render.ps1',
        'Private\Hyde.Variables.ps1',
        'Private\Hyde.Utility.ps1',
        'Private\Hyde.Validation.ps1',
        'Private\HydeTypes.ps1',
        'Plugins\seo-tag.ps1',
        'Plugins\titles-from-headings.ps1',
        'Plugins\libsass-converter.ps1',
        'en-US\Hyde-help.xml',
        'en-US\about_Hyde_Plugin_Authoring.help.txt'
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

# 0.6.7

- Added a dedicated help generation script at `tools/generateHelp.ps1` for Hyde docs and external help XML output.
- Added generation of `about_Hyde_Plugin_Authoring` from `src/Plugins/PluginAuthoring.md` as part of help build flow.
- Updated test-runner discovery in `tools/Invoke-HydeTests.ps1` to locate all `*.Tests.ps1` files dynamically from `/tests`.
- Updated markdown and discovery internals to satisfy BPA `PSUseOutputTypeCorrectly` informational findings.

# 0.6.6

- Added destination-root write containment checks so document and static output paths cannot escape configured destination.
- Added build tests for permalink and plugin output path traversal protections.
- Added installer warnings and interactive confirmation for `libsass-converter -Install` network downloads.

# 0.6.5

- Expanded markdown support with heading IDs, strikethrough, URL autolinks, task lists, aligned tables, footnotes, abbreviations, subscript, superscript, definition lists, and table captions.
- Improved markdown paragraph handling so soft line breaks normalize to spaces while hard breaks still render as `<br />`.

# 0.6.2

- Added markdown heading IDs with deterministic slug generation and duplicate-suffix handling.
- Added markdown support for strikethrough (`~~text~~`), plain URL autolinks, task list items, and basic pipe-table rendering with alignment markers.
- Fixed post `include_relative` rendering in paragraph content so included text no longer keeps unintended literal newlines.

# 0.6.1

- Added dedicated private markdown module script (`Private/Hyde.Markdown.ps1`) and extracted markdown conversion logic from `Hyde.Render.ps1`.

# 0.5.3

- Added built-in plugin `-Install` support, including self-contained LibSassHost setup in `libsass-converter`.

# 0.5.1

- Added `Hyde New-Theme` and `New-StaticSiteTheme` for starter theme scaffolding.
'
        }
    }
}
