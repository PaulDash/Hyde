# Hyde

![Hyde](/res/Icon_85x85.png)

PowerShell static site generator. The ugly Mr. Hyde to the popular [Jekyll](https://jekyllrb.com/).

Hyde started as a teaching and personal-site project, but it now has enough functionality to build real static sites with pages, collections, posts, layouts, Liquid templates, plugins, and cleaning/validation workflows.

> No infringment is meant on the wonderful project that is Jekyll and on the great team that develops and supports it.

## Dependencies

- [powershell-yaml](https://github.com/cloudbase/powershell-yaml) module by cloudbase for YAML support
- my [PowerLiquid](https://github.com/PaulDash/PowerLiquid) module to parse and render Liquid templates
- some plugins MAY have dependencies of their own

## Status

Hyde is usable today, but it is not trying to become a complete Jekyll clone.

### Core Commands

| Command        | Cmdlet              |                            |
| -------------- | ------------------- | -------------------------- |
| Hyde New       | New-StaticSite      | Create site scaffolding    |
| Hyde New-Theme | New-StaticSiteTheme | Create theme scaffolding   |
| Hyde Build     | Publish-StaticSite  | Build or rebuild a site    |
| Hyde Clean     | Clear-StaticSite    | Clean up generated site    |
| Hyde Doctor    | Test-StaticSite     | Validate site before build |

### Implemented Features

#### Configuration & Content Discovery

- `_config.yml` loading and merge with built-in defaults
- File-based theme support through `theme_dir` with fallback discovery for layouts, includes, and static assets
- Pages, posts, collections, and static file discovery
- YAML Front Matter with defaults

#### Templating & Rendering

- Liquid rendering through my standalone **PowerLiquid** module
- Markdown rendering using built-in logic
- Jekyll-style Liquid global variables: `site`, `page`, `page.previous`, `page.next`, `paginator`, and `site.data`
- `_includes` and `_layouts` with layout inheritance
- Theme include/layout fallback with site-first override precedence
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
- Plugin setup in plugin scripts via `-Install`.

#### Themes

- Theme scaffolding
- Build-time file-based themes via `theme_dir` in `_config.yml`
- Theme `_config.yml` values act as defaults that site `_config.yml` can override
- Theme `_sass` is added as an import path for the `libsass-converter` plugin when present

### Under Consideration

- Syntax highlighting
- Plugins: sitemap, relative-links, optional-front-matter, gallery-generator, redirect-from, responsive-image, remote-theme, minifier, github-metadata, readme-index
- incremental regeneration

### Deliberate NON-goals

- `Serve` command, file watching, auto-regeneration
- Ruby plugins including Gem-based themes
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

Create a previewable theme scaffold:

```powershell
Import-Module .\src\Hyde.psd1
Hyde New-Theme .\mytheme
```

Create a portable theme scaffold with the cmdlet directly:

```powershell
Import-Module .\src\Hyde.psd1
New-StaticSiteTheme -Destination .\mytheme -Portable
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

### File-Based Theme Configuration

Use `theme_dir` to point at a local reusable theme folder (relative to the site root or absolute):

```yaml
title: Example Site
theme_dir: ../mytheme

# Site values override theme _config.yml values
brand: Site Brand
```

Expected theme structure:

```text
mytheme/
  _config.yml
  _layouts/
  _includes/
  _sass/
  assets/
```

When a path exists in both site and theme, the site version wins for layouts, includes, and static assets.

## Plugin Authoring

Plugin authoring guidance lives in [docs/PluginAuthoring.md](docs/PluginAuthoring.md).

For built-in plugins that have dependencies to install, run installation/setup directly from the plugin script:

```powershell
.\src\Plugins\libsass-converter.ps1 -Install
```

## Testing

Run the Hyde test suite with:

```powershell
.\tests\Invoke-HydeTests.ps1
```

## Changelog

Version history is tracked in [CHANGELOG.md](CHANGELOG.md).
