<#
.SYNOPSIS
Removes generated Hyde output and cache artifacts.

.DESCRIPTION
Clear-StaticSite removes generated content for a Hyde site, including the destination
folder and common build artifact paths used by Hyde/Jekyll-compatible workflows.

The command initializes a normal Hyde build context so destination resolution follows
the same rules as build commands (site config, source location, and optional override).

Safety checks prevent destructive cleanup scenarios such as deleting drive roots,
site source roots, or parent paths of the source tree.

.PARAMETER SourcePath
Optional site source path used to resolve the site configuration and configured destination.
When omitted, Hyde uses its default source discovery behavior.

.PARAMETER Destination
Optional destination override. When provided, it takes precedence over destination values
from site configuration.

.PARAMETER Quiet
Suppresses informational output and emits only warnings/errors unless verbose output is enabled.

.PARAMETER ScriptPath
Internal/back-compat parameter for wrapper invocation. Not intended for normal use.

.PARAMETER ModuleRoot
Internal override for Hyde module root resolution. Not intended for normal use.

.PARAMETER Version
Internal override for reported Hyde version. Not intended for normal use.

.EXAMPLE
Clear-StaticSite -SourcePath .\site

Resolves site config from .\site and removes generated output and cache targets.

.EXAMPLE
Clear-StaticSite -SourcePath .\site -Destination .\site\_dist

Uses .\site for config lookup but removes generated output from the explicit destination override.

.EXAMPLE
Clear-StaticSite -SourcePath .\site -WhatIf

Shows what clean targets would be removed without deleting anything.

.OUTPUTS
System.Object[]
Returns the clean target descriptors evaluated and processed by the command.

.NOTES
Supports ShouldProcess, so -WhatIf and -Confirm are honored.
#>
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
