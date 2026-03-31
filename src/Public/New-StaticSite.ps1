<#
.SYNOPSIS
Creates a new Hyde site scaffold.

.DESCRIPTION
New-StaticSite creates a new static site folder with Hyde-compatible structure and starter files.

By default, the command creates a richer starter scaffold that includes a default layout,
starter pages, and a basic stylesheet. Use -Blank to create a minimal scaffold.

If the destination already exists and is non-empty, the command fails to avoid overwriting
existing content.

.PARAMETER Destination
Required destination path where the new site scaffold will be created.

.PARAMETER Blank
Creates a minimal scaffold instead of the default starter layout/content files.

.PARAMETER Quiet
Suppresses informational output and emits only warnings/errors unless verbose output is enabled.

.EXAMPLE
New-StaticSite -Destination .\mysite

Creates a new Hyde site with starter layouts, pages, and CSS.

.EXAMPLE
New-StaticSite -Destination .\mysite -Blank

Creates a minimal Hyde scaffold with only essential files.

.EXAMPLE
New-StaticSite -Destination .\mysite -WhatIf

Shows the scaffold creation operations without writing files.

.OUTPUTS
System.IO.DirectoryInfo
Returns the destination directory object.

.NOTES
Supports ShouldProcess, so -WhatIf and -Confirm are honored.
#>
function New-StaticSite {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.IO.DirectoryInfo])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [switch]$Blank,

        [switch]$Quiet
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not $Quiet) {
        $InformationPreference = 'Continue'
    }

    $destinationPath = resolveHydePath -Location $Destination -MayNotExist

    if (Test-Path -LiteralPath $destinationPath) {
        $existingItems = @(Get-ChildItem -LiteralPath $destinationPath -Force)
        if ($existingItems.Count -gt 0) {
            throw "Could not create a new site at '$destinationPath' because the destination already exists and is not empty."
        }
    } else {
        if ($PSCmdlet.ShouldProcess($destinationPath, 'Create destination directory')) {
            [void](New-Item -Path $destinationPath -ItemType Directory -Force)
        }
    }

    Write-Information "Creating a new Hyde site at '$destinationPath'."
    if (-not $PSCmdlet.ShouldProcess($destinationPath, 'Create Hyde site scaffolding')) {
        return (Get-Item -LiteralPath $destinationPath)
    }

    # Every new site starts with a configuration file that points Hyde at the current directory.
    Set-Content -LiteralPath (Join-Path -Path $destinationPath -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: My Hyde Site
description: My new Hyde site.
baseurl: ""
'@

    if ($Blank) {
        # A blank scaffold keeps only the minimum viable Hyde site structure.
        Set-Content -LiteralPath (Join-Path -Path $destinationPath -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
title: Home
---
# Welcome to Hyde
'@
    } else {
        $layoutsPath = Join-Path -Path $destinationPath -ChildPath '_layouts'
        $assetsPath = Join-Path -Path $destinationPath -ChildPath 'assets'
        $stylesPath = Join-Path -Path $assetsPath -ChildPath 'css'

        [void](New-Item -Path $layoutsPath -ItemType Directory -Force)
        [void](New-Item -Path $stylesPath -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $layoutsPath -ChildPath 'default.html') -Encoding UTF8 -Value @'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{{ page.title }}</title>
  <link rel="stylesheet" href="/assets/css/site.css">
</head>
<body>
  <main>
    {{ content }}
  </main>
</body>
</html>
'@

        Set-Content -LiteralPath (Join-Path -Path $destinationPath -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
title: Home
layout: default
---
# Welcome to Hyde

Your new PowerShell-generate static site is ready!
Check out the [Hyde documentation](https://github.com/PaulDash/Hyde/) to learn how to customize your site and add new content.
'@

        Set-Content -LiteralPath (Join-Path -Path $destinationPath -ChildPath 'about.md') -Encoding UTF8 -Value @'
---
title: About
layout: default
---
# About

This site was created with Hyde.
'@

        Set-Content -LiteralPath (Join-Path -Path $stylesPath -ChildPath 'site.css') -Encoding UTF8 -Value @'
body {
  font-family: Segoe UI, sans-serif;
  margin: 0;
  padding: 2rem;
  line-height: 1.5;
}

main {
  max-width: 48rem;
  margin: 0 auto;
}
'@
    }

    Write-Information "Created new Hyde site at '$destinationPath'."
    return (Get-Item -LiteralPath $destinationPath)
}
