function Test-StaticSite {
    [CmdletBinding()]
    param(
        [string]$Source,
        [string]$Destination,
        [string]$Environment = 'development',
        [switch]$Quiet,
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # Doctor follows the same quiet/information behavior as the build-oriented commands.
    if (-not $Quiet) {
        $InformationPreference = 'Continue'
    }

    $contextParameters = @{
        Environment = $Environment
        ScriptPath  = $ScriptPath
    }

    if ($PSBoundParameters.ContainsKey('Source')) {
        $contextParameters['Source'] = $Source
    }

    if ($PSBoundParameters.ContainsKey('Destination')) {
        $contextParameters['Destination'] = $Destination
    }

    try {
        $context = Initialize-HydeBuildContext @contextParameters
    } catch {
        throw "Doctor failed while initializing site context. $($_.Exception.Message)"
    }

    Write-Information "Running HYDE version $($context.Version)."
    Write-Verbose "Testing site at '$($context.SourcePath)'."
    Write-Verbose "Using environment '$($context.Environment)'."

    try {
        # Doctor uses normal source discovery so it validates the same item set that build would process.
        Get-HydeSourceItems -Context $context
    } catch {
        throw "Doctor failed while discovering source items in '$($context.SourcePath)'. $($_.Exception.Message)"
    }

    Write-Information "Checking $($context.Documents.Count) document(s) and $($context.StaticFiles.Count) static file(s)."

    $report = Test-HydeSiteContent -Context $context
    foreach ($issue in $report.Issues) {
        $issueLocation = if ([string]::IsNullOrWhiteSpace($issue.Path)) { '' } else { " [$($issue.Path)]" }
        Write-Warning "$($issue.Code)$issueLocation $($issue.Message)"
    }

    if ($report.Healthy) {
        Write-Information "Your static site looks healthy."
    } else {
        Write-Warning "Found $($report.Issues.Count) issue(s)."
    }

    return $report
}
