---
external help file: Hyde-help.xml
Module Name: Hyde
online version:
schema: 2.0.0
---

# Hyde

## SYNOPSIS
PowerShell static site generator. This is a wrapper script to replicate core commands of Jekyll.

## SYNTAX

```
Hyde [[-Command] <String>] [<CommonParameters>]
```

## DESCRIPTION
Hyde is a PowerShell static site generator inspired by Jekyll.
Created as a fun project to only generate a private webpage, but useful as an example when teaching about PowerShell.

The current implementation supports:
- loading Hyde defaults from \`globalConfig.yaml\`
- loading site settings from \`_config.yml\`
- loading site and built-in plugins
- discovering documents and static files
- copying HTML and static files to the destination site
- loading recursive YAML, JSON, CSV, and TSV files from \`_data\` into nested \`site.data\` paths
- parsing YAML front matter
- rendering Markdown documents to HTML
- rendering single-level layouts through the Liquid module
- rendering plugin-provided Liquid tags and filters
- rendering Jekyll-style \`include_relative\` from post content under \`_posts\`
- collections
- Jekyll-style permalinks for pages, collections, and posts
- cleaning generated output and cache directories
- basic doctor-style site validation

We may never support:
- all plugins
- syntax highlighting
- theme installation workflows

Due to the nature of PowerShell, there is no intention to support:
- serve command
- file watch mode

## EXAMPLES

### EXAMPLE 1
```
Hyde Build
```

Builds the site using paths from configuration.

### EXAMPLE 2
```
Hyde Build -Source . -Destination .\_site
```

Builds the site from the current directory into \`.\_site\`.

### EXAMPLE 3
```
Hyde Clean
```

Removes the generated destination folder, metadata file, and cache directories for the site.

### EXAMPLE 4
```
Hyde Clean -SourcePath .\site
```

Reads \`.\site\_config.yml\` to determine the generated destination path to clean.

### EXAMPLE 5
```
Hyde New mysite
```

Creates a new Hyde site scaffold at \`.\mysite\`.

### EXAMPLE 6
```
Hyde New mysite -Blank
```

Creates a minimal new Hyde site scaffold at \`.\mysite\`.

### EXAMPLE 7
```
Hyde New-Theme mytheme
```

Creates a previewable Hyde theme scaffold at \`./mytheme\`.

### EXAMPLE 8
```
Hyde New-Theme mytheme -Portable
```

Creates a reusable Hyde theme scaffold at \`./mytheme\` without preview content pages.

### EXAMPLE 9
```
Hyde Doctor
```

Checks the site for common problems such as invalid front matter, missing layouts, and output-path conflicts.


## PARAMETERS

### -Command
Chooses which top-level Hyde action to run.

Available options are:
- \`New\`
- \`New-Theme\`
- \`Build\`
- \`Clean\`
- \`Doctor\`
- \`Help\`

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

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## RELATED LINKS

[Hyde GitHub repo](https://github.com/PaulDash/Hyde)
