function Clear-StaticSite {
    [CmdletBinding()]
    param(
        [string]$Destination,
        [switch]$Quiet,
        [string]$ScriptPath,
        [string]$ModuleRoot = $script:HydeModuleRoot,
        [string]$Version = $script:HydeVersion
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # Clean shares the same quiet/information behavior as build.
    if (-not $Quiet) {
        $InformationPreference = 'Continue'
    }

    # Reuse the normal context initialization so clean honors the current site's config and any destination override.
    if ($PSBoundParameters.ContainsKey('ScriptPath')) {
        # Keep the old wrapper/test contract working while the module becomes the primary entry point.
        $ModuleRoot = Split-Path -Parent $ScriptPath
    }

    $contextParameters = @{
        Environment = 'development'
        ModuleRoot  = $ModuleRoot
        Version     = $Version
    }

    if ($PSBoundParameters.ContainsKey('Destination')) {
        $contextParameters['Destination'] = $Destination
    }

    try {
        $context = Initialize-HydeBuildContext @contextParameters
        $targets = Get-HydeCleanTargets -Context $context
    } catch {
        throw "Clean failed while initializing site context. $($_.Exception.Message)"
    }

    Write-Information "Running HYDE version $($context.Version)."
    Write-Verbose "Cleaning generated content for '$($context.SourcePath)'."
    Write-Verbose "Prepared $($targets.Count) clean target(s)."

    # Clean each generated target independently so missing paths do not block the rest.
    foreach ($target in $targets) {
        try {
            Write-Verbose "Removing $($target.Kind) at '$($target.Path)'."
            Remove-HydeGeneratedPath -Path $target.Path -SourcePath $context.SourcePath -Kind $target.Kind
        } catch {
            throw "Clean failed while removing $($target.Kind) '$($target.Path)'. $($_.Exception.Message)"
        }
    }

    Write-Information "Cleaned generated output for '$($context.SourcePath)'."

    return $targets
}
