function Invoke-HydeBuild {
    [CmdletBinding()]
    param(
        [string]$Source,
        [string]$Destination,
        [Parameter(Mandatory = $true)]
        [string]$Environment,
        [switch]$Quiet,
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

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

    $context = Initialize-HydeBuildContext @contextParameters

    Write-Information "Running HYDE version $($context.Version)."
    Write-Verbose "Building site from '$($context.SourcePath)' to '$($context.DestinationPath)'."

    if (-not (Test-Path -LiteralPath $context.DestinationPath -PathType Container)) {
        [void](New-Item -Path $context.DestinationPath -ItemType Directory -Force)
    }

    Get-HydeSourceItems -Context $context

    Write-Information "Processing $($context.Documents.Count) document(s) and $($context.StaticFiles.Count) static file(s)."

    foreach ($document in $context.Documents) {
        Convert-HydeDocument -Document $document -Context $context
        Write-HydeDocument -Document $document -Context $context
    }

    foreach ($staticFile in $context.StaticFiles) {
        Copy-HydeStaticFile -StaticFile $staticFile -Context $context
    }

    Write-Information "Finished in $(((Get-Date) - $context.Site.time).TotalSeconds.ToString('0.00')) seconds."

    return $context
}
