function Clear-StaticSite {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$SourcePath,
        [string]$Destination,
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

    # Clean shares the same quiet/information behavior as build.
    if (-not $Quiet) {
        $InformationPreference = 'Continue'
    }

    # Reuse the normal context initialization so clean can read the site's config and any destination override.
    if ($PSBoundParameters.ContainsKey('ScriptPath')) {
        # Keep the old wrapper/test contract working while the module becomes the primary entry point.
        $ModuleRoot = Split-Path -Parent $ScriptPath
    }

    $contextParameters = @{
        Environment = 'development'
        ModuleRoot  = $ModuleRoot
        Version     = $Version
    }

    if ($PSBoundParameters.ContainsKey('SourcePath')) {
        # Clean only uses the source path to discover the configured destination from site config.
        $contextParameters['Source'] = $SourcePath
    }

    if ($PSBoundParameters.ContainsKey('Destination')) {
        $contextParameters['Destination'] = $Destination
    }

    try {
        $context = initializeHydeBuildContext @contextParameters
        $targets = getHydeCleanTargets -Context $context
    } catch {
        throw "Clean failed while initializing site context. $($_.Exception.Message)"
    }

    Write-Information "Running HYDE version $($context.Version)."
    Write-Verbose "Cleaning generated content for '$($context.SourcePath)'."
    Write-Verbose "Prepared $($targets.Count) clean target(s)."

    # Clean each generated target independently so missing paths do not block the rest.
    foreach ($target in $targets) {
        try {
            if ($PSCmdlet.ShouldProcess($target.Path, "Remove $($target.Kind)")) {
                Write-Verbose "Removing $($target.Kind) at '$($target.Path)'."
                removeHydeGeneratedPath -Path $target.Path -Kind $target.Kind -SourcePath $context.SourcePath
            } else {
                Write-Verbose "Skipping removal of $($target.Kind) at '$($target.Path)' because ShouldProcess declined it."
            }
        } catch {
            throw "Clean failed while removing $($target.Kind) '$($target.Path)'. $($_.Exception.Message)"
        }
    }

    Write-Information "Cleaned generated output for '$($context.SourcePath)'."

    return $targets
}
