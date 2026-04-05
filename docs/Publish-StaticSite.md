---
external help file: Hyde-help.xml
Module Name: Hyde
online version:
schema: 2.0.0
---

# Publish-StaticSite

## SYNOPSIS
Builds and publishes a Hyde static site.

## SYNTAX

```
Publish-StaticSite [[-Source] <String>] [[-Destination] <String>] [-Environment] <String> [-Quiet]
 [[-ScriptPath] <String>] [[-ModuleRoot] <String>] [[-Version] <String>] [<CommonParameters>]
```

## DESCRIPTION
Publish-StaticSite performs a full Hyde build pipeline:

- initializes site context and configuration
- discovers documents and static files
- prepares document metadata/front matter
- synchronizes posts, pagination, and taxonomies
- renders published documents
- copies static assets

The command returns the full Hyde build context so callers can inspect build state,
discovered items, and output metadata.

## EXAMPLES

### EXAMPLE 1
```
Publish-StaticSite -Source .\site -Destination .\site\_site -Environment development
```

Builds a site from .\site into .\site\_site using the development environment.

### EXAMPLE 2
```
Publish-StaticSite -Source .\site -Environment production -Verbose
```

Builds using production context and emits detailed build phase tracing.

### EXAMPLE 3
```
Publish-StaticSite -Source .\site -Destination .\site\_site -Environment development -WhatIf
```

Shows file writes/copies that would occur without modifying output.

## PARAMETERS

### -Source
Optional source path for the site.
When omitted, Hyde uses default source discovery.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Destination
Optional destination path override for generated output.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Environment
Required environment name used for context initialization and environment-specific settings.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 3
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Quiet
Suppresses informational output and emits only warnings/errors unless verbose output is enabled.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -ScriptPath
Internal/back-compat parameter for wrapper invocation.
Not intended for normal use.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 4
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ModuleRoot
Internal override for Hyde module root resolution.
Not intended for normal use.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 5
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Version
Internal override for reported Hyde version.
Not intended for normal use.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 6
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

## OUTPUTS

### HydeBuildContext

Returns the populated build context for the completed run.

## NOTES

Supports `ShouldProcess`, so `-WhatIf` and `-Confirm` are honored.

Configuration is merged in this order: Hyde global defaults, theme `_config.yml`, then site
`_config.yml`. Later values replace earlier values. For array settings such as `plugins`, the
later configuration replaces the entire earlier list rather than appending to it.

Themes act as a fallback layer. Theme layouts, includes, static assets, and configuration are used
when the site does not provide a matching file or setting. Site layouts, includes, static assets,
and configuration override matching theme content.

Plugin names are read from the final merged configuration, so site plugin settings override theme
plugin settings, and theme plugin settings override global defaults. Plugin scripts are resolved
from the site's configured plugin directory and Hyde's built-in `Plugins` directory. Theme
directories are not searched for plugin script files.
