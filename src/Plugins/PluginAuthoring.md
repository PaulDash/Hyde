# Plugin Authoring

Hyde plugins are PowerShell scripts that return a descriptor hashtable.

They can:

- register Hyde lifecycle hooks
- register Liquid tags and filters through PowerLiquid's extension registry
- influence output paths
- enrich document metadata before rendering

Hyde loads plugins from the configured `plugins_dir`, which defaults to `_plugins`. It also ships with built-in plugins under `src/Plugins`.

## Plugin File Shape

A plugin should be documented with a comment-based help block near the top of the file.

Every plugin should expose an `-Install` switch so installation/setup behavior is
self-contained in the plugin script.

A plugin script should return a hashtable:

```powershell
[CmdletBinding()]
param(
    $Context,
    [switch]$Install
)

if ($Install) {
    Write-Verbose "No installation is required for this plugin."
    return $true
}

@{
    Name = 'my-plugin'
    Hooks = @{
        BeforeRenderDocument = {
            param($Invocation)

            $document = $Invocation.Document
            if ($null -eq $document) {
                return
            }

            $document.FrontMatter['example'] = 'value'
        }
    }
    Liquid = @{
        Tags = @{
            hello = {
                param($Invocation)
                return 'Hello from a Hyde plugin'
            }
        }
        Filters = @{
            reverse_words = {
                param($Value, $Arguments, $Invocation)

                if ($null -eq $Value) {
                    return ''
                }

                $words = @(([string]$Value) -split '\s+')
                [array]::Reverse($words)
                return ($words -join ' ')
            }
        }
    }
}
```

## Context Parameter

The top-level `param($Context)` receives the active `HydeBuildContext`.

Use it to inspect:

- site settings
- source and destination paths
- the Hyde version
- the shared Liquid extension registry

Most plugins will only need `$Context` for setup-time decisions. Hook handlers receive their own invocation object later.

## Install Contract

Hyde plugin scripts should implement an install path using `-Install`.

- When a plugin has no setup dependencies, `-Install` should return `True`.
- If `-Verbose` is supplied, `-Install` should state installation is not needed.
- When a plugin has dependencies (for example external binaries), `-Install`
    should fetch or prepare those dependencies from inside the plugin script.

This keeps plugin setup and plugin behavior in one place.

## Hook Names

Current Hyde hook points:

- `AfterInitialize`
- `AfterDiscoverDocument`
- `AfterDiscoverStaticFile`
- `BeforeRenderDocument`
- `AfterRenderDocument`
- `BeforeWriteDocument`
- `AfterWriteDocument`
- `BeforeCopyStaticFile`
- `AfterCopyStaticFile`
- `ResolveDocumentOutputPath`
- `ResolveStaticFileOutputPath`

These names match the registry in [src/Private/Hyde.Plugins.ps1](../src/Private/Hyde.Plugins.ps1).

## Hook Invocation Shape

Hook handlers receive a single `$Invocation` object. Depending on the hook, it may contain:

- `Context`
- `Document`
- `StaticFile`
- `OutputPath`
- `DestinationPath`
- `CancelCopy` (mutable flag for static-file transform hooks)

Value resolver hooks (`ResolveDocumentOutputPath`, `ResolveStaticFileOutputPath`) receive two parameters:

```powershell
param($CurrentValue, $Invocation)
```

For `BeforeCopyStaticFile`, handlers can set:

```powershell
$Invocation.CancelCopy = $true
```

When `CancelCopy` is true, Hyde skips the default `Copy-Item` step. This is useful when your plugin writes transformed output itself (for example, SCSS -> CSS).

For document-centric hooks, you should expect `Document` to be a `HydeDocument` object with semantic properties such as:

- `Title`
- `Url`
- `OutputPath`
- `FrontMatter`
- `RawContent`
- `RenderedContent`
- `Collection`
- `PostDate`

## Liquid Extensions

Hyde plugins do not ask PowerLiquid to load plugins directly.

Instead, Hyde:

1. discovers plugin scripts
2. reads their descriptor
3. registers any declared Liquid tags and filters into the current PowerLiquid registry
4. passes that registry into `Invoke-LiquidTemplate`

That separation keeps PowerLiquid reusable in other hosts while still letting Hyde plugins extend Liquid behavior.

### Simple Custom Tag

```powershell
param($Context)

@{
    Name = 'hello-tag'
    Liquid = @{
        Tags = @{
            hello = {
                param($Invocation)
                return 'Hello from Paul'
            }
        }
    }
}
```

Usage:

```liquid
{% hello %}
```

Should return `Hello from Paul`

### Simple Custom Filter

```powershell
param($Context)

@{
    Name = 'shout-filter'
    Liquid = @{
        Filters = @{
            shout = {
                param($Value, $Arguments, $Invocation)
                return ([string]$Value).ToUpperInvariant() + '!'
            }
        }
    }
}
```

Usage:

```liquid
{{ page.title | shout }}
```

Running against a page with title 'Hello' should return `HELLO!`

## Built-In Plugin Examples

Use these as reference implementations:

- [src/Plugins/seo-tag.ps1](../src/Plugins/seo-tag.ps1)
- [src/Plugins/titles-from-headings.ps1](../src/Plugins/titles-from-headings.ps1)

`seo-tag` shows a custom Liquid tag

`titles-from-headings` shows a document lifecycle hook that enriches semantic document metadata

## Plugin Discovery Rules

If a configured name starts with `jekyll-`, Hyde also tries:

- the original name
- the name with `jekyll-` removed
- the stripped name prefixed with `hyde-`

That makes names like `jekyll-seo-tag` resolve cleanly to Hyde-friendly implementations.

## Safe Mode

When `safe: true` is enabled in site configuration, Hyde restricts plugin loading to the explicit `whitelist` set. This is useful for locked-down environments, CI builds, or untrusted content where arbitrary plugin execution is a risk.

- `safe: true` means other plugin IDs are ignored, whether configured in `_config.yml` `plugins:` or present in `_plugins`/`src/Plugins`.
- `whitelist` should be an array of identifiers that correspond to plugin `Name` values (e.g. `seo-tag`, `titles-from-headings`).
- If `whitelist` is empty or missing, no plugins are loaded while safe mode is active.
- Mixed-mode behavior: safe mode only affects plugin whitelist filtering; non-plugin features (e.g., core rendering and file discovery) still run.

Example:

```yaml
safe: true
plugins:
  - seo-tag
  - custom-plugin
whitelist:
  - seo-tag
```

In this config, `custom-plugin` is ignored because it is not whitelisted.

## Recommendations

- Prefer mutating semantic document properties such as `document.title` instead of only changing rendered HTML.
- Keep hooks narrowly scoped and idempotent.
- Use Liquid tags and filters for presentation behavior.
- Use Hyde hooks for discovery, metadata enrichment, or output-path changes.
- Avoid directly reading or writing arbitrary files unless the plugin truly owns that behavior.
- Document your code.

## Example: Transform Static Assets

This pattern remaps `.scss` output to `.css`, writes transformed output, then cancels the raw source copy.

```powershell
param($Context)

@{
    Name = 'example-transform'
    Hooks = @{
        ResolveStaticFileOutputPath = {
            param($CurrentValue, $Invocation)

            if ($Invocation.StaticFile.Extension -eq '.scss') {
                return ([System.IO.Path]::ChangeExtension($CurrentValue, '.css').Replace('\\', '/'))
            }

            return $CurrentValue
        }

        BeforeCopyStaticFile = {
            param($Invocation)

            if ($Invocation.StaticFile.Extension -ne '.scss') {
                return
            }

            $destinationPath = Join-Path -Path $Invocation.Context.DestinationPath -ChildPath $Invocation.StaticFile.OutputRelativePath
            $destinationDirectory = Split-Path -Path $destinationPath -Parent
            if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
                [void](New-Item -Path $destinationDirectory -ItemType Directory -Force)
            }

            Set-Content -LiteralPath $destinationPath -Encoding UTF8 -Value '/* transformed css */'
            $Invocation.CancelCopy = $true
        }
    }
}
```
