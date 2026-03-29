# Changelog

All notable changes to Hyde will be documented in this file.

The format is loosely based on Keep a Changelog, but entries are kept short and practical for this project.

## [0.4.5] - 2026-03-29

### Added
- Added semantic tag and category support on Hyde document objects.
- Added `site.tags` and `site.categories` buckets for Liquid templates.
- Exposed `page.tags` and `page.categories` to layouts and document rendering.

### Changed
- Built taxonomy maps from the final published document set before page rendering starts.

## [0.4.4] - 2026-03-29

### Changed
- Updated Hyde to detect PowerLiquid as an external published dependency.
- Added fallback behavior to load PowerLiquid from a sibling repo, an installed module, or PowerShell Gallery.

## [0.4.3] - 2026-03-28

### Changed
- Changed `Hyde Clean` to use `-SourcePath` for configuration lookup while still allowing `-Destination` to override it.
- Tightened clean behavior around configuration-driven destination resolution.

## [0.4.2] - 2026-03-28

### Added
- Added layout inheritance support.

### Changed
- Pre-parsed files in `_layouts` and cached layout chains before document rendering.
- Updated doctor validation to understand inherited layout chains.

## [0.4.0] - 2026-03-28

### Changed
- Spun Liquid processing out into the standalone PowerLiquid module.
- Updated Hyde to consume PowerLiquid as its template engine.

## [0.3.0] - 2026-03-28

### Added
- Implemented the `New` command for site scaffolding.
- Added default and blank starter site generation paths.

## [0.2.0] - 2026-03-28

### Changed
- Moved Hyde’s main command routing into the module.
- Added the `Hyde` module command surface so Hyde can be used without calling the wrapper script directly.
- Added a module manifest and established the module-first entry point.
