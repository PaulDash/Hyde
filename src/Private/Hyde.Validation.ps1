# Initialize a validation report structure for doctor checks.
function newHydeValidationReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    # Doctor collects issues into a single report so callers can inspect the full set at once.
    return [pscustomobject]@{
        Context = $Context
        Healthy = $true
        Issues  = New-Object System.Collections.ArrayList
    }
}

# Add a validation issue to the report with context.
function addHydeValidationIssue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Report,

        [Parameter(Mandatory = $true)]
        [string]$Code,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [string]$Path,

        [ValidateSet('Warning', 'Error')]
        [string]$Severity = 'Error'
    )

    # Every issue carries a stable code so tests and future callers can reason about the result.
    [void]$Report.Issues.Add([pscustomobject]@{
        Severity = $Severity
        Code     = $Code
        Path     = $Path
        Message  = $Message
    })

    $Report.Healthy = $false
}

# Check a layout for missing parents or parse errors.
function testHydeLayoutForIssues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document,

        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context,

        [Parameter(Mandatory = $true)]
        $Report
    )

    if (-not $Document.FrontMatter.ContainsKey('layout')) {
        return
    }

    $layoutName = [string]$Document.FrontMatter.layout
    if ([string]::IsNullOrWhiteSpace($layoutName) -or $layoutName -in @('none', 'null')) {
        return
    }

    try {
        [void](getHydeLayoutChain -LayoutName $layoutName -Context $Context)
    } catch {
        addHydeValidationIssue -Report $Report -Code 'MissingLayout' -Path $Document.RelativePath -Message $_.Exception.Message
        return
    }
}

# Validate a document for front matter and rendering issues.
function testHydeDocumentForIssues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document,

        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context,

        [Parameter(Mandatory = $true)]
        $Report
    )

    try {
        initializeHydeDocument -Document $Document -Context $Context
    } catch {
        addHydeValidationIssue -Report $Report -Code 'InvalidFrontMatter' -Path $Document.RelativePath -Message $_.Exception.Message
        return
    }

    testHydeLayoutForIssues -Document $Document -Context $Context -Report $Report
}

# Detect duplicate output paths among documents.
function testHydeOutputConflicts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context,

        [Parameter(Mandatory = $true)]
        $Report
    )

    # Track generated output paths so doctor can report collisions before build time.
    $seenOutputs = @{}

    foreach ($document in $Context.Documents) {
        if (-not $document.Published -or -not $document.WriteOutput) {
            continue
        }

        $outputPath = $document.OutputRelativePath.Replace('\', '/')
        if ($seenOutputs.ContainsKey($outputPath)) {
            addHydeValidationIssue -Report $Report -Code 'DuplicateOutputPath' -Path $document.RelativePath -Message "Output path '$outputPath' conflicts with '$($seenOutputs[$outputPath])'."
            continue
        }

        $seenOutputs[$outputPath] = $document.RelativePath
    }

    foreach ($staticFile in $Context.StaticFiles) {
        $outputPath = $staticFile.OutputRelativePath.Replace('\', '/')
        if ($seenOutputs.ContainsKey($outputPath)) {
            addHydeValidationIssue -Report $Report -Code 'DuplicateOutputPath' -Path $staticFile.RelativePath -Message "Output path '$outputPath' conflicts with '$($seenOutputs[$outputPath])'."
            continue
        }

        $seenOutputs[$outputPath] = $staticFile.RelativePath
    }
}

# Validate the configured theme directory before content-level checks run.
function testHydeThemeConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context,

        [Parameter(Mandatory = $true)]
        $Report
    )

    if ([string]::IsNullOrWhiteSpace($Context.ThemePath)) {
        return
    }

    if (-not (Test-Path -LiteralPath $Context.ThemePath -PathType Container)) {
        addHydeValidationIssue -Report $Report -Code 'MissingThemeDirectory' -Path $Context.ThemePath -Message "Configured theme directory '$($Context.ThemePath)' does not exist."
        return
    }

    $layoutsDirectoryName = if ($Context.Settings.ContainsKey('layouts_dir') -and -not [string]::IsNullOrWhiteSpace([string]$Context.Settings.layouts_dir)) {
        [string]$Context.Settings.layouts_dir
    } else {
        '_layouts'
    }

    $includesDirectoryName = if ($Context.Settings.ContainsKey('includes_dir') -and -not [string]::IsNullOrWhiteSpace([string]$Context.Settings.includes_dir)) {
        [string]$Context.Settings.includes_dir
    } else {
        '_includes'
    }

    $themeSupportPaths = @(
        [System.IO.Path]::Combine($Context.ThemePath, $layoutsDirectoryName),
        [System.IO.Path]::Combine($Context.ThemePath, $includesDirectoryName),
        [System.IO.Path]::Combine($Context.ThemePath, 'assets')
    )

    if (-not ($themeSupportPaths | Where-Object { Test-Path -LiteralPath $_ })) {
        addHydeValidationIssue -Report $Report -Code 'InvalidThemeDirectory' -Path $Context.ThemePath -Message "Configured theme directory '$($Context.ThemePath)' does not contain layouts, includes, or assets."
    }

    $themeLayoutsPath = [System.IO.Path]::Combine($Context.ThemePath, $layoutsDirectoryName)
    if (-not (Test-Path -LiteralPath $themeLayoutsPath -PathType Container)) {
        addHydeValidationIssue -Report $Report -Code 'ThemeMissingLayouts' -Path $Context.ThemePath -Severity 'Warning' -Message "Theme directory '$($Context.ThemePath)' does not contain a layouts directory."
    }
}

# Run all validation checks across the site content.
function testHydeSiteContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    $report = newHydeValidationReport -Context $Context
    testHydeThemeConfiguration -Context $Context -Report $report

    foreach ($document in $Context.Documents) {
        Write-Verbose "Validating document '$($document.RelativePath)'."
        testHydeDocumentForIssues -Document $document -Context $Context -Report $report
    }

    testHydeOutputConflicts -Context $Context -Report $report
    return $report
}
