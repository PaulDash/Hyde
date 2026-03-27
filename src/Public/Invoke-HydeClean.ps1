function Invoke-HydeClean {
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

    # Clean shares the same quiet/information behavior as build.
    if (-not $Quiet) {
        $InformationPreference = 'Continue'
    }

    # Reuse the normal context initialization so clean honors site config and CLI overrides.
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

    $context = Initialize-HydeBuildContext @contextParameters
    $targets = Get-HydeCleanTargets -Context $context

    Write-Information "Running HYDE version $($context.Version)."
    Write-Verbose "Cleaning generated content for '$($context.SourcePath)'."

    # Clean each generated target independently so missing paths do not block the rest.
    foreach ($target in $targets) {
        Remove-HydeGeneratedPath -Path $target.Path -SourcePath $context.SourcePath -Kind $target.Kind
    }

    Write-Information "Cleaned generated output for '$($context.SourcePath)'."

    return $targets
}
