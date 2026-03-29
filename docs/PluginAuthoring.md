# Plugin Authoring

Hyde plugins are PowerShell scripts that return a descriptor hashtable.

They can:

- register Hyde lifecycle hooks
- register Liquid tags and filters through PowerLiquid's extension registry
- influence output paths
- enrich document metadata before rendering

Hyde loads plugins from the configured `plugins_dir`, which defaults to `_plugins`. It also ships with built-in plugins under `src/Plugins`.

## Plugin File Shape

A plugin script should return a hashtable:

```powershell
param($Context)

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

When `safe: true` is enabled, only plugins listed in `whitelist` are allowed.

## Recommendations

- Prefer mutating semantic document properties such as `document.title` instead of only changing rendered HTML.
- Keep hooks narrowly scoped and idempotent.
- Use Liquid tags and filters for presentation behavior.
- Use Hyde hooks for discovery, metadata enrichment, or output-path changes.
- Avoid directly reading or writing arbitrary files unless the plugin truly owns that behavior.

## Future Opportunities

Likely future plugin surfaces include:

- post-processing generated HTML
- richer collection registration
- command-level extensions
- more Liquid dialect-specific extension points
