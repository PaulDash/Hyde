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

    # Build emits informational progress unless the caller explicitly asks for quiet mode.
    if (-not $Quiet) {
        $InformationPreference = 'Continue'
    }

    # Pass only the caller-provided overrides into the shared context initializer.
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
        throw "Build failed while initializing site context. $($_.Exception.Message)"
    }

    Write-Information "Running HYDE version $($context.Version)."
    Write-Verbose "Building site from '$($context.SourcePath)' to '$($context.DestinationPath)'."

    try {
        if (-not (Test-Path -LiteralPath $context.DestinationPath -PathType Container)) {
            [void](New-Item -Path $context.DestinationPath -ItemType Directory -Force)
        }
    } catch {
        throw "Build failed while preparing destination '$($context.DestinationPath)'. $($_.Exception.Message)"
    }

    try {
        # Discover the source tree before any rendering starts.
        Get-HydeSourceItems -Context $context
    } catch {
        throw "Build failed while discovering source items in '$($context.SourcePath)'. $($_.Exception.Message)"
    }

    Write-Information "Processing $($context.Documents.Count) document(s) and $($context.StaticFiles.Count) static file(s)."

    # Documents are rendered and written first so any rendering failures stop the build early.
    foreach ($document in $context.Documents) {
        try {
            Convert-HydeDocument -Document $document -Context $context
            Write-HydeDocument -Document $document -Context $context
        } catch {
            throw "Build failed while processing document '$($document.SourcePath)'. $($_.Exception.Message)"
        }
    }

    # Static assets are copied after document rendering.
    foreach ($staticFile in $context.StaticFiles) {
        try {
            Copy-HydeStaticFile -StaticFile $staticFile -Context $context
        } catch {
            throw "Build failed while copying static file '$($staticFile.SourcePath)'. $($_.Exception.Message)"
        }
    }

    Write-Information "Finished in $(((Get-Date) - $context.Site.time).TotalSeconds.ToString('0.00')) seconds."

    return $context
}
