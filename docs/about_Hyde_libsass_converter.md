# about_Hyde_libsass_converter

The built-in `libsass-converter` plugin compiles `.scss` and `.sass` files to `.css` during `Hyde Build` / `Publish-StaticSite`.

## What It Does

- Compiles `.scss` and `.sass` files to `.css`
- Preserves folder structure while switching the output extension
- Treats underscore-prefixed files (for example `_variables.scss`) as Sass partials
- Skips emitting raw partial files to destination output
- Uses Hyde's static copy cancellation hook so transformed output replaces raw-source copying

## Enable Plugin

In your site's `_config.yml`:

```yaml
plugins:
  - libsass-converter
```

## Configuration

Optional settings:

```yaml
libsass:
  style: expanded       # expanded or compressed
  include_paths:
    - assets/styles
```

Optional top-level fallback:

```yaml
sass_style: compressed
```

Behavior notes:

- Default style is `expanded` in `development`, `compressed` otherwise.
- `libsass.style` overrides the environment default.
- Top-level `sass_style` is supported as a compatibility fallback.

## Bundling LibSassHost DLLs

The plugin expects bundled LibSassHost assets under:

- `src/Plugins/libsass-converter/lib`

### Recommended: Helper Script

Run from repository root:

```powershell
.\tools\Get-LibSassHost.ps1
```

Useful options:

```powershell
.\tools\Get-LibSassHost.ps1 -Version 2.2.0
.\tools\Get-LibSassHost.ps1 -Force
.\tools\Get-LibSassHost.ps1 -DestinationRoot .\scratch\libsass
```

### Manual Bundling

1. Download the `LibSassHost` NuGet package (`.nupkg`).
2. Extract the package.
3. Copy `LibSassHost.dll` from `lib/netstandard2.0/` (or another available framework folder) to `src/Plugins/libsass-converter/lib/lib/netstandard2.0/`.
4. Copy native runtime assets from `runtimes/win-x64/native/` (and optionally `runtimes/win-x86/native/`) to matching paths under `src/Plugins/libsass-converter/lib/runtimes/`.

## Missing DLL Behavior

When LibSassHost assets are not present, `libsass-converter` fails fast with an actionable error that instructs users to:

- run `.\tools\Get-LibSassHost.ps1`, or
- manually place assets in the expected plugin bundle path

## Limitations

- `libsass-converter` is based on LibSassHost (LibSass) and does not support the full modern Dart Sass module system (`@use` and `@forward`).
- A future `dartsass-converter` plugin can coexist as a separate option; configure only one Sass converter plugin per site.
