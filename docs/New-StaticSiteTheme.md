---
external help file: Hyde-help.xml
Module Name: Hyde
online version:
schema: 2.0.0
---

# New-StaticSiteTheme

## SYNOPSIS
Creates a new Hyde theme scaffold.

## SYNTAX

```
New-StaticSiteTheme [-Destination] <String> [-Portable] [-Quiet] [<CommonParameters>]
```

## DESCRIPTION
\`New-StaticSiteTheme\` scaffolds a starter Hyde theme at the target destination.

By default, it creates a previewable scaffold that includes an \`index.md\` page
so the generated structure can be built immediately.

When \`-Portable\` is used, it creates a reusable package-style scaffold without
preview content pages.

## EXAMPLES

### EXAMPLE 1
```
New-StaticSiteTheme -Destination .\mytheme
```

Creates a previewable theme scaffold in \`./mytheme\`.

### EXAMPLE 2
```
New-StaticSiteTheme -Destination .\mytheme -Portable
```

Creates a portable theme scaffold in \`./mytheme\`.

### EXAMPLE 3
```
Hyde New-Theme .\mytheme
```

Runs the same scaffold flow through the top-level Hyde command.

## PARAMETERS

### -Destination
Path where the theme scaffold should be created.

If the destination exists, it must be empty.

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

### -Portable
Creates a reusable package-style scaffold without preview content pages.

Portable mode omits \`index.md\` and keeps only shared theme structure.

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

## NOTES

Theme scaffolding in Hyde is intentionally file-generation only.

This command does not install, apply, or distribute themes.

The default previewable mode favors quick iteration by including a build target.

Portable mode favors reuse by producing only layout/include/style assets.

The scaffold uses \`_sass\` plus \`assets/css/site.scss\` on purpose:
- Hyde defaults \`sass.sass_dir\` to \`_sass\`.
- The current built-in Sass path is LibSass-based.
- Generated Sass uses classic \`@import\` intentionally for current compatibility.
