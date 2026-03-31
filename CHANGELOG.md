# Changelog

All notable changes to Hyde will be documented in this file.

The format is loosely based on Keep a Changelog, but entries are kept short and practical for this project.

## [0.5.1] - 2026-03-31

### Added

- Added `Hyde New-Theme` and `New-StaticSiteTheme` for starter theme scaffolding.
- Added theme scaffold documentation covering previewable and portable layouts.

### Changed

- Plugin documentation is now within the plugin.

## [0.5.0] - 2026-03-31

### Added

- Added built-in `libsass-converter` plugin support for SCSS/Sass static-file transforms.
- Added dedicated `about_Hyde_libsass_converter` documentation.
- Added deterministic Pester coverage for missing LibSassHost DLL failure guidance.

### Changed

- Added static-file copy cancellation support for transform plugins via `BeforeCopyStaticFile` invocation state.
- Expanded `tools/Get-LibSassHost.ps1` with usage guidance and inline operational comments.
- Moved detailed libsass-converter setup content out of README into dedicated docs.

### Fixed

- Fixed plugin/value-hook usage examples to match Hyde's value-hook signature contract.

## [0.4.14] - 2026-03-30

### Added

- Added Jekyll-style pagination for HTML `index.html` pages, including the Liquid `paginator` object and `paginate_path` support.
- Added dedicated manifest and configuration Pester coverage, plus build tests for pagination scenarios.

### Changed

- Updated Hyde to rely on the module-first entry point after moving the wrapper script out of the main execution path.
- Reordered the Pester suite to fail faster, running manifest and configuration checks before broader integration tests.
- Reduced Liquid integration tests so Hyde only verifies dependency loading and a minimal render call against the external PowerLiquid module.
- Updated project metadata, including package icon metadata.

### Fixed

- Fixed module manifest and command metadata resolution after the wrapper restructuring.
- Fixed Hyde public commands and tests so they no longer depend on the old wrapper script location.

## [0.4.11] - 2026-03-29

### Added

- Added recursive YAML `_data` loading.
- Added nested `site.data` paths for `_data` subfolders, such as `_data/team/people.yml -> site.data.team.people`.
- Added JSON, CSV, and TSV support for `_data` files.

### Changed

- Added collision handling for conflicting `_data` keys and namespaces.
- Improved `_data` error handling for directory enumeration and invalid YAML with clearer file-specific messages.

## [0.4.10] - 2026-03-29

### Added

- Added recursive YAML `_data` loading.
- Added nested `site.data` paths for `_data` subfolders, such as `_data/team/people.yml -> site.data.team.people`.

### Changed

- Added collision handling for conflicting `_data` keys and namespaces.
- Improved `_data` error handling for directory enumeration and invalid YAML with clearer file-specific messages.

## [0.4.9] - 2026-03-29

### Added

- Added recursive YAML `_data` loading.
- Added nested `site.data` paths for `_data` subfolders, such as `_data/team/people.yml -> site.data.team.people`.

### Changed

- Added collision handling for conflicting `_data` keys and namespaces.

## [0.4.8] - 2026-03-29

### Changed

- Revisited permalink handling to align Hyde more closely with current Jekyll behavior.
- Added built-in post permalink styles `ordinal`, `weekdate`, and `none`.
- Expanded permalink placeholder support for posts and collections, including week-based and date-name tokens.
- Applied the global permalink setting to pages and collections while ignoring placeholders those content types do not support.
- Ignored page `permalink` values supplied through front matter defaults, matching Jekyll behavior.

## [0.4.7] - 2026-03-29

### Added

- Added Jekyll-style `include_relative` support for post content.

### Changed

- Limited `include_relative` resolution to files within the matching `_posts` directory or one of its subdirectories.
- Added error handling for unsupported `include_relative` usage outside post content and for paths that resolve outside the allowed post root.

## [0.4.6] - 2026-03-29

### Changed

- Aligned Hyde's tag and category behavior more closely with current Jekyll behavior.
- Limited `site.tags` and `site.categories` to published posts.
- Added support for post categories derived from directories above `_posts`.
- Matched Jekyll-style singular versus plural front matter behavior for `tag` / `tags` and `category` / `categories`.

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
