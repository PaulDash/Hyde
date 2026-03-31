---
external help file: Hyde-help.xml
Module Name: Hyde
online version:
schema: 2.0.0
---

# Test-StaticSite

## SYNOPSIS
Validates Hyde site health before build.

## SYNTAX

```
Test-StaticSite [[-Source] <String>] [[-Destination] <String>] [[-Environment] <String>] [-Quiet]
 [[-ScriptPath] <String>] [[-ModuleRoot] <String>] [[-Version] <String>] [<CommonParameters>]
```

## DESCRIPTION
Test-StaticSite runs Hyde "doctor" validation checks against the current site context.

The command initializes context, discovers documents/static files, and runs content
validation checks to report issues before a publish run.
Results include a health flag
and issue list that can be used in CI or local preflight checks.

## EXAMPLES

### EXAMPLE 1
```
Test-StaticSite -Source .\site
```

Runs doctor checks for the site rooted at .\site.

### EXAMPLE 2
```
Test-StaticSite -Source .\site -Environment production -Verbose
```

Runs validation with production context and detailed trace output.

### EXAMPLE 3
```
$report = Test-StaticSite -Source .\site -Quiet
if (-not $report.Healthy) { $report.Issues }
```

Captures validation report for scripting/automation.

## PARAMETERS

### -Source
Optional source path for the site under test.

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
Optional destination override used while preparing test context.

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
Environment name used for context initialization.
Defaults to \`development\`.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: Development
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

### System.Collections.Hashtable
Returns a report with `Healthy` and `Issues` entries.
