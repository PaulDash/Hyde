function Publish-StaticSite {
    [CmdletBinding()]
    param(
        [string]$Source,
        [string]$Destination,
        [Parameter(Mandatory = $true)]
        [string]$Environment,
        [switch]$Quiet,
        [string]$ScriptPath,
        [string]$ModuleRoot = $script:HydeModuleRoot,
        [string]$Version = $script:HydeVersion
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # Build emits informational progress unless the caller explicitly asks for quiet mode.
    if (-not $Quiet) {
        $InformationPreference = 'Continue'
    }

    # Pass only the caller-provided overrides into the shared context initializer.
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

    Write-Verbose "Initializing Hyde build context."
    try {
        $context = initializeHydeBuildContext @contextParameters
    } catch {
        throw "Build failed while initializing site context. $($_.Exception.Message)"
    }

    Write-Information "Running HYDE version $($context.Version)."
    Write-Verbose "Building site from '$($context.SourcePath)' to '$($context.DestinationPath)'."
    Write-Verbose "Using environment '$($context.Environment)'."
    Write-Verbose "Loaded $($context.LoadedPlugins.Count) plugin(s)."
    initializeHydeLayouts -Context $context

    try {
        if (-not (Test-Path -LiteralPath $context.DestinationPath -PathType Container)) {
            Write-Verbose "Creating destination directory '$($context.DestinationPath)'."
            [void](New-Item -Path $context.DestinationPath -ItemType Directory -Force)
        } else {
            Write-Verbose "Destination directory '$($context.DestinationPath)' already exists."
        }
    } catch {
        throw "Build failed while preparing destination '$($context.DestinationPath)'. $($_.Exception.Message)"
    }

    Write-Verbose "Discovering source items under '$($context.SourcePath)'."
    try {
        # Discover the source tree before any rendering starts.
        getHydeSourceItems -Context $context
    } catch {
        throw "Build failed while discovering source items in '$($context.SourcePath)'. $($_.Exception.Message)"
    }

    Write-Information "Processing $($context.Documents.Count) document(s) and $($context.StaticFiles.Count) static file(s)."
    Write-Verbose "Discovered $($context.Documents.Count) document(s) and $($context.StaticFiles.Count) static file(s)."
    Write-Verbose "Preparing document metadata phase."

    # Resolve front matter and semantic metadata for every document before any template loops read site collections.
    foreach ($document in $context.Documents) {
        try {
            Write-Verbose "Preparing document metadata for '$($document.RelativePath)'."
            initializeHydeDocument -Document $document -Context $context
        } catch {
            throw "Build failed while preparing document '$($document.SourcePath)'. $($_.Exception.Message)"
        }
    }

    # Post loops should see the final published, sorted post set before any page starts rendering.
    syncHydePosts -Context $context

    Write-Verbose "Starting document rendering phase."

    # Documents are rendered and written first so any rendering failures stop the build early.
    $documentIndex = 0
    $publishedDocumentCount = 0
    foreach ($document in $context.Documents) {
        $documentIndex++
        try {
            Write-Verbose "Rendering document $documentIndex of $($context.Documents.Count): '$($document.RelativePath)'."
            convertHydeDocument -Document $document -Context $context
            if (-not $document.Published) {
                Write-Verbose "Skipping unpublished document '$($document.RelativePath)'."
                continue
            }

            if (-not $document.WriteOutput) {
                Write-Verbose "Skipping output for collection document '$($document.RelativePath)' because its collection is not configured for output."
                continue
            }

            Write-Verbose "Writing document '$($document.RelativePath)' to '$($document.OutputRelativePath)'."
            writeHydeDocument -Document $document -Context $context
            $publishedDocumentCount++
            Write-Verbose "Finished document '$($document.RelativePath)'."
        } catch {
            throw "Build failed while processing document '$($document.SourcePath)'. $($_.Exception.Message)"
        }
    }

    Write-Verbose "Starting static file copy phase."
    # Static assets are copied after document rendering.
    $staticFileIndex = 0
    foreach ($staticFile in $context.StaticFiles) {
        $staticFileIndex++
        try {
            Write-Verbose "Copying static file $staticFileIndex of $($context.StaticFiles.Count): '$($staticFile.RelativePath)' to '$($staticFile.OutputRelativePath)'."
            copyHydeStaticFile -StaticFile $staticFile -Context $context
            Write-Verbose "Finished static file '$($staticFile.RelativePath)'."
        } catch {
            throw "Build failed while copying static file '$($staticFile.SourcePath)'. $($_.Exception.Message)"
        }
    }

    Write-Verbose "Build summary: wrote $publishedDocumentCount published document(s) and copied $($context.StaticFiles.Count) static file(s)."
    Write-Information "Finished in $(((Get-Date) - $context.Site.time).TotalSeconds.ToString('0.00')) seconds."

    return $context
}
