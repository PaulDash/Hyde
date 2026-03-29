# Hyde ![Hyde](https://raw.githubusercontent.com/PaulDash/Hyde/main/res/Icon_32x32.png)

PowerShell static site generator. The ugly Mr. Hyde to the popular [Jekyll](https://jekyllrb.com/).

Hyde started as a teaching and personal-site project, but it now has enough functionality to build real static sites with pages, collections, posts, layouts, Liquid templates, plugins, and cleaning/validation workflows.

No infringment is meant on the wonderful project that is Jekyll and on the great team that develop and support it.

## Dependancies

- [powershell-yaml](https://github.com/cloudbase/powershell-yaml) module by cloudbase for YAML support
- my [PowerLiquid](https://github.com/PaulDash/PowerLiquid) module to parse and render Liquid templates

## Status

Hyde is usable today, but it is not trying to become a complete Jekyll clone.

Deliberate non-goals:

- `Serve` command
- File watching / auto-regeneration
- Gem-based themes
- Ruby plugin compatibility
- CoffeeScript conversion
- TOML config files

### Implemented Features

- Site scaffolding with `Hyde New`
- Site builds with `Hyde Build`
- Generated-file cleanup with `Hyde Clean`
- Site validation with `Hyde Doctor`
- `_config.yml` loading and merge with built-in defaults
- Pages, posts, collections, and static file discovery
- YAML Front Matter with defaults
- Liquid rendering through the standalone `PowerLiquid` module
- Markdown rendering
- Recursive YAML, JSON, CSV, and TSV `_data` loading with nested `site.data` paths and clear collision/parse error reporting, plus `_includes` and `_layouts` support with layout inheritance
- `include_relative` for post content, limited to files under the matching `_posts` directory
- Posts from `_posts` with draft and future-post handling
- Permalinks for pages, collections, and posts, including built-in post styles such as `date`, `pretty`, `ordinal`, `weekdate`, and `none`
- Post tags and categories exposed through `page.*`, `site.tags`, and `site.categories`
- Post categories derived from directories above `_posts`, plus front matter `tag` / `tags` and `category` / `categories`
- Draft support from `_drafts` when enabled
- Plugin loading from `_plugins` and built-in Hyde plugins such as `seo-tag` and `titles-from-headings`

### Current Gaps

- broader Jekyll [variable](https://jekyllrb.com/docs/variables/) coverage
- Sass conversion
- Themes
- Pagination
- Syntax highlighting
- lack of many Plugins,like [these](https://pages.github.com/versions.json) used by GitHub Pages

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

## Plugin Authoring

Plugin authoring guidance lives in [docs/PluginAuthoring.md](docs/PluginAuthoring.md).

## Testing

Run the Hyde test suite with:

```powershell
.\tests\Invoke-HydeTests.ps1
```

## Changelog

Version history is tracked in [CHANGELOG.md](CHANGELOG.md).
