---
external help file: Hyde-help.xml
Module Name: Hyde
online version:
schema: 2.0.0
---

# Clear-StaticSite

## SYNOPSIS
Removes generated Hyde output and cache artifacts.

## SYNTAX

```
Clear-StaticSite [[-SourcePath] <String>] [[-Destination] <String>] [-Quiet] [[-ScriptPath] <String>]
 [[-ModuleRoot] <String>] [[-Version] <String>] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

## DESCRIPTION
Clear-StaticSite removes generated content for a Hyde site, including the destination
folder and common build artifact paths used by Hyde/Jekyll-compatible workflows.

The command initializes a normal Hyde build context so destination resolution follows
the same rules as build commands (site config, source location, and optional override).

Safety checks prevent destructive cleanup scenarios such as deleting drive roots,
site source roots, or parent paths of the source tree.

## EXAMPLES

### EXAMPLE 1
```
Clear-StaticSite -SourcePath .\site
```

Resolves site config from .\site and removes generated output and cache targets.

### EXAMPLE 2
```
Clear-StaticSite -SourcePath .\site -Destination .\site\_dist
```

Uses .\site for config lookup but removes generated output from the explicit destination override.

### EXAMPLE 3
```
Clear-StaticSite -SourcePath .\site -WhatIf
```

Shows what clean targets would be removed without deleting anything.

## PARAMETERS

### -SourcePath
Optional site source path used to resolve the site configuration and configured destination.
When omitted, Hyde uses its default source discovery behavior.

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
Optional destination override.
When provided, it takes precedence over destination values
from site configuration.

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
Position: 3
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
Position: 4
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
Position: 5
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## RELATED LINKS
