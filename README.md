# Hyde ![Hyde](https://raw.githubusercontent.com/PaulDash/Hyde/main/res/Icon_32x32.png)

PowerShell static site generator. The ugly Mr. Hyde to the popular [Jekyll](https://jekyllrb.com/).

Hyde started as a teaching and personal-site project, but it now has enough functionality to build real static sites with pages, collections, posts, layouts, Liquid templates, plugins, and cleaning/validation workflows.

No infringment is meant on the wonderful project that is Jekyll and on the great team that develop and support it.

## Status

Hyde is usable today, but it is not trying to become a complete Jekyll clone.

Deliberate non-goals:
- `Serve` command
- file watching / auto-regeneration
- gem-based themes
- Ruby plugin compatibility

### Implemented Features

- Site scaffolding with `Hyde New`
- Site builds with `Hyde Build`
- Generated-file cleanup with `Hyde Clean`
- Site validation with `Hyde Doctor`
- `_config.yml` loading and merge with built-in defaults
- Pages and static file discovery
- YAML Front Matter with defaults
- Liquid rendering through the standalone `PowerLiquid` module
- Markdown rendering
- `_data` YAML loading, `_layouts` support with inheritance
- Posts from `_posts`, Permalinks
- Collections
- Draft support from `_drafts` when enabled
- Plugin loading from `_plugins` and built-in Hyde plugins

### Current Gaps

- richer post features such as excerpts, archives, and category pages
- Pagination
- Sass conversion
- JSON / CSV / TSV data files
- `_config.toml`
- broader Jekyll variable coverage

## Quick Start

### Usage

Create a new site:

```powershell
Import-Module .\src\Hyde.psd1
Hyde New .\mysite
```

Build a site:

```powershell
Hyde Build -Source .\mysite -Destination .\mysite\_site
```

Clean generated output using the current site's config:

```powershell
Hyde Clean -SourcePath .\mysite
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
  _plugins/
  index.md
```

### Example Configuration

```yaml
title: Example Site
description: Demo site built with Hyde
url: https://example.com
baseurl: ""
destination: _site
markdown: kramdown

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

## Related Projects

- Hyde uses the standalone `PowerLiquid` module to parse and render Liquid templates.
