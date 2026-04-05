<#
.SYNOPSIS
Builds and publishes a Hyde static site.

.DESCRIPTION
Publish-StaticSite performs a full Hyde build pipeline:

- initializes site context and configuration
- discovers documents and static files
- prepares document metadata/front matter
- synchronizes posts, pagination, and taxonomies
- renders published documents
- copies static assets

The command returns the full Hyde build context so callers can inspect build state,
discovered items, and output metadata.

.PARAMETER Source
Optional source path for the site. When omitted, Hyde uses default source discovery.

.PARAMETER Destination
Optional destination path override for generated output.

.PARAMETER Environment
Required environment name used for context initialization and environment-specific settings.

.PARAMETER Quiet
Suppresses informational output and emits only warnings/errors unless verbose output is enabled.

.PARAMETER ScriptPath
Internal/back-compat parameter for wrapper invocation. Not intended for normal use.

.PARAMETER ModuleRoot
Internal override for Hyde module root resolution. Not intended for normal use.

.PARAMETER Version
Internal override for reported Hyde version. Not intended for normal use.

.EXAMPLE
Publish-StaticSite -Source .\site -Destination .\site\_site -Environment development

Builds a site from .\site into .\site\_site using the development environment.

.EXAMPLE
Publish-StaticSite -Source .\site -Environment production -Verbose

Builds using production context and emits detailed build phase tracing.

.EXAMPLE
Publish-StaticSite -Source .\site -Destination .\site\_site -Environment development -WhatIf

Shows file writes/copies that would occur without modifying output.

.OUTPUTS
HydeBuildContext
Returns the populated build context for the completed run.

.NOTES
Supports ShouldProcess, so -WhatIf and -Confirm are honored.

Configuration is merged in this order: Hyde global defaults, theme `_config.yml`, then site
`_config.yml`. Later values replace earlier values. For array settings such as `plugins`, the
later configuration replaces the entire earlier list rather than appending to it.

Themes act as a fallback layer. Theme layouts, includes, static assets, and configuration are used
when the site does not provide a matching file or setting. Site layouts, includes, static assets,
and configuration override matching theme content.

Plugin names are read from the final merged configuration, so site plugin settings override theme
plugin settings, and theme plugin settings override global defaults. Plugin scripts are resolved
from the site's configured plugin directory and Hyde's built-in `Plugins` directory. Theme
directories are not searched for plugin script files.
#>
function Publish-StaticSite {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$Source,
        [string]$Destination,
        [Parameter(Mandatory = $true)]
        [string]$Environment,
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
        try {
            if (-not (Test-Path -LiteralPath $context.DestinationPath -PathType Container)) {
                if ($PSCmdlet.ShouldProcess($context.DestinationPath, 'Create destination directory')) {
                    Write-Verbose "Creating destination directory '$($context.DestinationPath)'."
                    [void](New-Item -Path $context.DestinationPath -ItemType Directory -Force)
                } else {
                    Write-Verbose "Skipping creation of destination directory '$($context.DestinationPath)' because ShouldProcess declined it."
                }
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

        # Paginated listing pages are generated from the final site.posts set before rendering begins.
        initializeHydePagination -Context $context

        # Tag and category loops should also see the final published document buckets before rendering starts.
        syncHydeTaxonomies -Context $context

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

                $documentTargetPath = Join-Path -Path $context.DestinationPath -ChildPath $document.OutputRelativePath
                if ($PSCmdlet.ShouldProcess($documentTargetPath, "Write document '$($document.RelativePath)'")) {
                    Write-Verbose "Writing document '$($document.RelativePath)' to '$($document.OutputRelativePath)'."
                    writeHydeDocument -Document $document -Context $context
                    $publishedDocumentCount++
                    Write-Verbose "Finished document '$($document.RelativePath)'."
                } else {
                    Write-Verbose "Skipping write of document '$($document.RelativePath)' because ShouldProcess declined it."
                }
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
                $staticFileTargetPath = Join-Path -Path $context.DestinationPath -ChildPath $staticFile.OutputRelativePath
                if ($PSCmdlet.ShouldProcess($staticFileTargetPath, "Copy static file '$($staticFile.RelativePath)'")) {
                    Write-Verbose "Copying static file $staticFileIndex of $($context.StaticFiles.Count): '$($staticFile.RelativePath)' to '$($staticFile.OutputRelativePath)'."
                    copyHydeStaticFile -StaticFile $staticFile -Context $context
                    Write-Verbose "Finished static file '$($staticFile.RelativePath)'."
                } else {
                    Write-Verbose "Skipping copy of static file '$($staticFile.RelativePath)' because ShouldProcess declined it."
                }
            } catch {
                throw "Build failed while copying static file '$($staticFile.SourcePath)'. $($_.Exception.Message)"
            }
        }

        Write-Verbose "Build summary: wrote $publishedDocumentCount published document(s) and copied $($context.StaticFiles.Count) static file(s)."
        Write-Information "Finished in $(((Get-Date) - $context.Site.time).TotalSeconds.ToString('0.00')) seconds."

        return $context
    } finally {
        if ($context -and -not [string]::IsNullOrWhiteSpace($context.EffectiveIncludesPath) -and (Test-Path -LiteralPath $context.EffectiveIncludesPath -PathType Container)) {
            # Theme include fallback uses a temporary merged directory that should not outlive the build.
            Remove-Item -LiteralPath $context.EffectiveIncludesPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
