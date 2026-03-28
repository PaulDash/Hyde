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

    # Doctor validates front matter and layout references without rendering the document body.
    $strictFrontMatter = $false
    if ($Context.Settings.ContainsKey('strict_front_matter')) {
        $strictFrontMatter = [bool]$Context.Settings.strict_front_matter
    }

    try {
        initializeHydeDocument -Document $Document -Context $Context
    } catch {
        addHydeValidationIssue -Report $Report -Code 'InvalidFrontMatter' -Path $Document.RelativePath -Message $_.Exception.Message
        return
    }

    testHydeLayoutForIssues -Document $Document -Context $Context -Report $Report
}

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

function testHydeSiteContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    $report = newHydeValidationReport -Context $Context

    foreach ($document in $Context.Documents) {
        Write-Verbose "Validating document '$($document.RelativePath)'."
        testHydeDocumentForIssues -Document $document -Context $Context -Report $report
    }

    testHydeOutputConflicts -Context $Context -Report $report
    return $report
}
