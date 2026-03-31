<#
.SYNOPSIS
Validates Hyde site health before build.

.DESCRIPTION
Test-StaticSite runs Hyde "doctor" validation checks against the current site context.

The command initializes context, discovers documents/static files, and runs content
validation checks to report issues before a publish run. Results include a health flag
and issue list that can be used in CI or local preflight checks.

.PARAMETER Source
Optional source path for the site under test.

.PARAMETER Destination
Optional destination override used while preparing test context.

.PARAMETER Environment
Environment name used for context initialization. Defaults to `development`.

.PARAMETER Quiet
Suppresses informational output and emits only warnings/errors unless verbose output is enabled.

.PARAMETER ScriptPath
Internal/back-compat parameter for wrapper invocation. Not intended for normal use.

.PARAMETER ModuleRoot
Internal override for Hyde module root resolution. Not intended for normal use.

.PARAMETER Version
Internal override for reported Hyde version. Not intended for normal use.

.EXAMPLE
Test-StaticSite -Source .\site

Runs doctor checks for the site rooted at .\site.

.EXAMPLE
Test-StaticSite -Source .\site -Environment production -Verbose

Runs validation with production context and detailed trace output.

.EXAMPLE
$report = Test-StaticSite -Source .\site -Quiet
if (-not $report.Healthy) { $report.Issues }

Captures validation report for scripting/automation.

.OUTPUTS
System.Collections.Hashtable
Returns a report with `Healthy` and `Issues` entries.
#>
function Test-StaticSite {
    [CmdletBinding()]
    param(
        [string]$Source,
        [string]$Destination,
        [string]$Environment = 'development',
        [switch]$Quiet,
        [string]$ScriptPath,
        [string]$ModuleRoot,
        [string]$Version
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $commandInfo = Get-Command -Name $MyInvocation.MyCommand.Name -ErrorAction SilentlyContinue

    if ([string]::IsNullOrWhiteSpace($ModuleRoot)) {
        $ModuleRoot = $ExecutionContext.SessionState.Module.ModuleBase
    }

    if ([string]::IsNullOrWhiteSpace($ModuleRoot) -and $commandInfo -and $commandInfo.Module) {
        $ModuleRoot = $commandInfo.Module.ModuleBase
    }

    if ([string]::IsNullOrWhiteSpace($ModuleRoot)) {
        $ModuleRoot = Split-Path -Parent $PSScriptRoot
    }

    if ([string]::IsNullOrWhiteSpace($Version) -and $ExecutionContext.SessionState.Module.Version) {
        $Version = $ExecutionContext.SessionState.Module.Version.ToString()
    }

    if ([string]::IsNullOrWhiteSpace($Version) -and $commandInfo -and $commandInfo.Module -and $commandInfo.Module.Version) {
        $Version = $commandInfo.Module.Version.ToString()
    }

    if ([string]::IsNullOrWhiteSpace($Version) -and -not [string]::IsNullOrWhiteSpace($ModuleRoot)) {
        $Version = (Test-ModuleManifest -Path (Join-Path -Path $ModuleRoot -ChildPath 'Hyde.psd1')).Version.ToString()
    }

    # Doctor follows the same quiet/information behavior as the build-oriented commands.
    if (-not $Quiet) {
        $InformationPreference = 'Continue'
    }

    if ($PSBoundParameters.ContainsKey('ScriptPath')) {
        # Keep the old wrapper/test contract working while the module becomes the primary entry point.
        $ModuleRoot = Split-Path -Parent $ScriptPath
    }

    $contextParameters = @{
        Environment = $Environment
        ModuleRoot  = $ModuleRoot
        Version     = $Version
    }

    if ($PSBoundParameters.ContainsKey('Source')) {
        $contextParameters['Source'] = $Source
    }

    if ($PSBoundParameters.ContainsKey('Destination')) {
        $contextParameters['Destination'] = $Destination
    }

    try {
        $context = initializeHydeBuildContext @contextParameters
    } catch {
        throw "Doctor failed while initializing site context. $($_.Exception.Message)"
    }
    initializeHydeLayouts -Context $context

    Write-Information "Running HYDE version $($context.Version)."
    Write-Verbose "Testing site at '$($context.SourcePath)'."
    Write-Verbose "Using environment '$($context.Environment)'."

    try {
        # Doctor uses normal source discovery so it validates the same item set that build would process.
        getHydeSourceItems -Context $context
    } catch {
        throw "Doctor failed while discovering source items in '$($context.SourcePath)'. $($_.Exception.Message)"
    }

    Write-Information "Checking $($context.Documents.Count) document(s) and $($context.StaticFiles.Count) static file(s)."

    $report = testHydeSiteContent -Context $context
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
