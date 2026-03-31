---
external help file: Hyde-help.xml
Module Name: Hyde
online version:
schema: 2.0.0
---

# New-StaticSite

## SYNOPSIS
Creates a new Hyde site scaffold.

## SYNTAX

```
New-StaticSite [-Destination] <String> [-Blank] [-Quiet] [<CommonParameters>]
```

## DESCRIPTION
New-StaticSite creates a new static site folder with Hyde-compatible structure and starter files.

By default, the command creates a richer starter scaffold that includes a default layout,
starter pages, and a basic stylesheet.
Use -Blank to create a minimal scaffold.

If the destination already exists and is non-empty, the command fails to avoid overwriting
existing content.

## EXAMPLES

### EXAMPLE 1
```
New-StaticSite -Destination .\mysite
```

Creates a new Hyde site with starter layouts, pages, and CSS.

### EXAMPLE 2
```
New-StaticSite -Destination .\mysite -Blank
```

Creates a minimal Hyde scaffold with only essential files.

### EXAMPLE 3
```
New-StaticSite -Destination .\mysite -WhatIf
```

Shows the scaffold creation operations without writing files.

## PARAMETERS

### -Destination
Required destination path where the new site scaffold will be created.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Blank
Creates a minimal scaffold instead of the default starter layout/content files.

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

## OUTPUTS

### System.IO.DirectoryInfo
Returns the destination directory object.
