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
