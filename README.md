# Hyde

![Hyde](/res/Icon_85x85.png)

PowerShell static site generator. The ugly Mr. Hyde to the popular [Jekyll](https://jekyllrb.com/).

Hyde started as a teaching and personal-site project, but it now has enough functionality to build real static sites with pages, collections, posts, layouts, Liquid templates, plugins, and cleaning/validation workflows.

No infringment is meant on the wonderful project that is Jekyll and on the great team that develop and support it.

## Dependancies

- [powershell-yaml](https://github.com/cloudbase/powershell-yaml) module by cloudbase for YAML support
- my [PowerLiquid](https://github.com/PaulDash/PowerLiquid) module to parse and render Liquid templates

## Status

Hyde is usable today, but it is not trying to become a complete Jekyll clone.

### Core Commands

- Site scaffolding with `Hyde New`
- Site builds with `Hyde Build`
- Generated-file cleanup with `Hyde Clean`
- Site validation with `Hyde Doctor`

All functionality is also exposed as PowerShell-friendly Verb-Noun syntax!

### Implemented Features

#### Configuration & Content Discovery

- `_config.yml` loading and merge with built-in defaults
- Pages, posts, collections, and static file discovery
- YAML Front Matter with defaults

#### Templating & Rendering

- Liquid rendering through my standalone **PowerLiquid** module
- Markdown rendering using built-in logic
- Jekyll-style Liquid global variables: `site`, `page`, `page.previous`, `page.next`, `paginator`, and `site.data`
- `_includes` and `_layouts` with layout inheritance
- `include_relative` for post content (limited to `_posts` directory)
- Optional Sass conversion for `.scss` and `.sass` files through the `libsass-converter` plugin

#### Content Management

- Posts from `_posts` with draft and future-post handling
- Draft support from `_drafts`, when enabled
- Permalinks for pages, collections, and posts (`date`, `pretty`, `ordinal`, `weekdate`, `none`)
- Post tags and categories via front matter and directory structure

#### Data & Extensibility

- Recursive YAML, JSON, CSV, and TSV `_data` loading with nested paths
- Clear collision and parse error reporting
- Plugin loading from `_plugins` with these included:
  - seo-tag
  - titles-from-headings
  - libsass-converter (requires bundled LibSassHost DLLs)

### Under Consideration

- Core command `Hyde New-Theme`
- Themes
- Syntax highlighting
- Plugins: sitemap, relative-links, optional-front-matter, gallery-generator, redirect-from, responsive-image, remote-theme, minifier, github-metadata, readme-index

### Deliberate NON-goals

- `Serve` command, file watching, auto-regeneration
- Ruby plugins including Gem-based themes
- incremental regeneration
- CoffeeScript conversion
- TOML config files

## Quick Start

### Usage

Create a new site:

```powershell
Import-Module .\src\Hyde.psd1
Hyde New .\mysite
```

Create a new site with the cmdlet directly:

```powershell
Import-Module .\src\Hyde.psd1
New-StaticSite -Destination .\mysite
```

Build a site:

```powershell
Hyde Build -Source .\mysite -Destination .\mysite\_site
```

Build a site with the cmdlet directly:

```powershell
Publish-StaticSite -Source .\mysite -Destination .\mysite\_site -Environment development
```

Clean generated output using the current site's config:

```powershell
Hyde Clean -SourcePath .\mysite
```

Clean generated output with the cmdlet directly:

```powershell
Clear-StaticSite -SourcePath .\mysite
```

### Basic Site Structure

```text
site/
  _config.yml
  _layouts/
  _includes/
  _data/
  _posts/
  _drafts/
  index.md
```

### Example Configuration

```yaml
title: Example Site
description: Demo site built with Hyde
url: https://example.com
baseurl: ""
destination: _site

collections:
  notes:
    output: true
    permalink: /notes/:title/

plugins:
  - seo-tag
  - titles-from-headings

defaults:
  - scope:
      path: ""
      type: pages
    values:
      layout: default
```

### libsass-converter Documentation

See [docs/about_Hyde_libsass_converter.md](docs/about_Hyde_libsass_converter.md) for:

- plugin configuration and behavior
- helper tool usage (`tools/Get-LibSassHost.ps1`)
- manual DLL bundling steps
- failure behavior and current limitations

## Plugin Authoring

Plugin authoring guidance lives in [docs/PluginAuthoring.md](docs/PluginAuthoring.md).

## Testing

Run the Hyde test suite with:

```powershell
.\tests\Invoke-HydeTests.ps1
```

## Changelog

Version history is tracked in [CHANGELOG.md](CHANGELOG.md).
