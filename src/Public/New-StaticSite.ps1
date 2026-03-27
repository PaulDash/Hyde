function New-StaticSite {
    [CmdletBinding()]
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
        [void](New-Item -Path $destinationPath -ItemType Directory -Force)
    }

    Write-Information "Creating a new Hyde site at '$destinationPath'."

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
# Hello World
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

Your new PowerShell static site is ready.
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
