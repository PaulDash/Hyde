function New-StaticTheme {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.IO.DirectoryInfo])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [switch]$Portable,

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
            throw "Could not create a new theme at '$destinationPath' because the destination already exists and is not empty."
        }
    } else {
        if ($PSCmdlet.ShouldProcess($destinationPath, 'Create destination directory')) {
            [void](New-Item -Path $destinationPath -ItemType Directory -Force)
        }
    }

    Write-Information "Creating a new Hyde theme at '$destinationPath'."

    if (-not $PSCmdlet.ShouldProcess($destinationPath, 'Create Hyde theme scaffolding')) {
        if (Test-Path -LiteralPath $destinationPath) {
            return (Get-Item -LiteralPath $destinationPath)
        }

        return [System.IO.DirectoryInfo]::new($destinationPath)
    }

    $themeFiles = @(
        @{
            Path = '_config.yml'
            Content = @'
title: My Hyde Theme Preview
description: Starter preview for a reusable Hyde theme.
baseurl: ""
'@
        },
        @{
            Path = '_layouts/default.html'
            Content = @'
<!DOCTYPE html>
<html lang="en">
<head>
  {% include head.html %}
</head>
<body>
  {% include site-header.html %}
  <main class="site-shell">
    {{ content }}
  </main>
</body>
</html>
'@
        },
        @{
            Path = '_includes/head.html'
            Content = @'
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{% if page.title %}{{ page.title }} | {% endif %}{{ site.title }}</title>
<link rel="stylesheet" href="{{ site.baseurl }}/assets/css/site.css">
'@
        },
        @{
            Path = '_includes/site-header.html'
            Content = @'
<header class="site-header">
  <div class="site-shell">
    <a class="site-title" href="{{ site.baseurl }}/">{{ site.title }}</a>
    {% if site.description %}
    <p class="site-tagline">{{ site.description }}</p>
    {% endif %}
  </div>
</header>
'@
        },
        @{
            # Keep the emitted stylesheet under assets and the shared variables in _sass.
            Path = 'assets/css/site.scss'
            Content = @'
@import "../../_sass/theme";
'@
        },
        @{
            Path = '_sass/_theme.scss'
            Content = @'
$page-width: 56rem;
$surface-color: #f6f3ea;
$text-color: #1f1f1f;
$accent-color: #945d00;

body {
  margin: 0;
  background: linear-gradient(180deg, #fdfaf3 0%, $surface-color 100%);
  color: $text-color;
  font-family: Georgia, "Times New Roman", serif;
  line-height: 1.6;
}

.site-shell {
  width: min(100% - 2rem, $page-width);
  margin: 0 auto;
}

.site-header {
  padding: 2rem 0 1rem;
  border-bottom: 1px solid rgba(0, 0, 0, 0.08);
}

.site-title {
  color: $text-color;
  font-size: 2rem;
  font-weight: 700;
  text-decoration: none;
}

.site-tagline {
  margin: 0.5rem 0 0;
  color: rgba(31, 31, 31, 0.75);
}

main {
  padding: 2rem 0 4rem;
}

a {
  color: $accent-color;
}
'@
        }
    )

    if (-not $Portable) {
        # The default scaffold doubles as a tiny preview site so the theme has an immediate build target.
        $themeFiles += @{
            Path = 'index.md'
            Content = @'
---
title: Theme Preview
layout: default
---
# Hyde Theme Preview

This starter theme scaffold gives you layouts, includes, and Sass structure you can evolve into a reusable Hyde theme.
'@
        }
    }

    foreach ($themeFile in $themeFiles) {
        $filePath = Join-Path -Path $destinationPath -ChildPath $themeFile.Path
        $parentPath = Split-Path -Path $filePath -Parent

        if (-not (Test-Path -LiteralPath $parentPath)) {
            [void](New-Item -Path $parentPath -ItemType Directory -Force)
        }

        Set-Content -LiteralPath $filePath -Encoding UTF8 -Value $themeFile.Content
    }

    Write-Information "Created new Hyde theme at '$destinationPath'."
    return (Get-Item -LiteralPath $destinationPath)
}