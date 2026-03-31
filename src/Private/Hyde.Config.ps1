# Recursively merge configuration hashtables so site values override defaults.
function mergeHydeConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Existing,

        [Parameter(Mandatory = $true)]
        [hashtable]$Difference
    )

    # Merge nested configuration sections recursively so site config can override Hyde defaults.
    foreach ($key in $Difference.Keys) {
        if ($Existing.ContainsKey($key)) {
            if ($Existing[$key] -is [hashtable] -and $Difference[$key] -is [hashtable]) {
                mergeHydeConfig -Existing $Existing[$key] -Difference $Difference[$key]
            } else {
                $Existing[$key] = $Difference[$key]
            }
        } else {
            $Existing[$key] = $Difference[$key]
        }
    }
}

# Load a YAML configuration file and normalize it to a hashtable.
function readHydeConfigFile {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Could not validate location of configuration file '$Path'."
    }

    try {
        # Read the whole file at once so YAML parsing sees the original structure.
        $content = Get-Content -LiteralPath $Path -Raw
        if ([string]::IsNullOrWhiteSpace($content)) {
            return @{}
        }

        $parsed = ConvertFrom-Yaml -Yaml $content
        return (convertToHydeHashtable -InputObject $parsed)
    } catch {
        throw "Could not parse configuration file '$Path'. $($_.Exception.Message)"
    }
}

# Resolve a path relative to a base directory with optional non-existent targets.
function resolveHydePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Location,

        [string]$BasePath = (Get-Location).Path,

        [switch]$MayNotExist
    )

    # Resolve relative paths against the current site root while still allowing absolute overrides.
    $candidate = if ([System.IO.Path]::IsPathRooted($Location)) {
        $Location
    } else {
        Join-Path -Path $BasePath -ChildPath $Location
    }

    try {
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }

        if ($MayNotExist) {
            $parentPath = Split-Path -Path $candidate -Parent
            if (-not $parentPath) {
                $parentPath = $BasePath
            }

            if (-not (Test-Path -LiteralPath $parentPath -PathType Container)) {
                throw "Could not validate parent directory '$parentPath'."
            }

            return Join-Path -Path (Resolve-Path -LiteralPath $parentPath).Path -ChildPath (Split-Path -Path $candidate -Leaf)
        }
    } catch {
        throw "Could not resolve target path of '$Location'. $($_.Exception.Message)"
    }

    throw "Could not resolve target path of '$Location'."
}

# Resolve the configured theme directory to an absolute local path.
function resolveHydeThemePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Settings,

        [Parameter(Mandatory = $true)]
        [string]$SourcePath
    )

    if (-not $Settings.ContainsKey('theme_dir')) {
        return ''
    }

    $themeDirectory = [string]$Settings.theme_dir
    if ([string]::IsNullOrWhiteSpace($themeDirectory)) {
        return ''
    }

    $resolvedThemePath = resolveHydePath -Location $themeDirectory -BasePath $SourcePath -MayNotExist
    if (-not (Test-Path -LiteralPath $resolvedThemePath -PathType Container)) {
        throw "Could not find configured theme directory '$themeDirectory' at '$resolvedThemePath'."
    }

    return $resolvedThemePath
}

# Resolve a configured support directory beneath a root if it exists.
function resolveHydeSupportDirectoryPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Settings,

        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [ValidateSet('includes_dir', 'layouts_dir', 'data_dir', 'plugins_dir')]
        [string]$SettingName,

        [Parameter(Mandatory = $true)]
        [string]$DefaultDirectoryName
    )

    $directoryName = if ($Settings.ContainsKey($SettingName) -and -not [string]::IsNullOrWhiteSpace([string]$Settings[$SettingName])) {
        [string]$Settings[$SettingName]
    } else {
        $DefaultDirectoryName
    }

    $directoryPath = Join-Path -Path $RootPath -ChildPath $directoryName
    if (-not (Test-Path -LiteralPath $directoryPath -PathType Container)) {
        return ''
    }

    return $directoryPath
}

# Build the include root used by Liquid when a theme contributes fallback includes.
function newHydeEffectiveIncludesPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Settings,

        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [string]$ThemePath
    )

    $siteIncludesPath = resolveHydeSupportDirectoryPath -Settings $Settings -RootPath $SourcePath -SettingName 'includes_dir' -DefaultDirectoryName '_includes'
    if ([string]::IsNullOrWhiteSpace($ThemePath)) {
        return ''
    }

    $themeIncludesPath = resolveHydeSupportDirectoryPath -Settings $Settings -RootPath $ThemePath -SettingName 'includes_dir' -DefaultDirectoryName '_includes'
    if ([string]::IsNullOrWhiteSpace($themeIncludesPath)) {
        return ''
    }

    $effectiveIncludesPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("hyde-includes-{0}" -f [System.Guid]::NewGuid().ToString('N'))
    [void](New-Item -Path $effectiveIncludesPath -ItemType Directory -Force)

    # Copy theme include files first so site files can overwrite them with the same relative path.
    foreach ($themeIncludeItem in Get-ChildItem -LiteralPath $themeIncludesPath -Force) {
        Copy-Item -LiteralPath $themeIncludeItem.FullName -Destination $effectiveIncludesPath -Recurse -Force
    }

    if (-not [string]::IsNullOrWhiteSpace($siteIncludesPath)) {
        foreach ($siteIncludeItem in Get-ChildItem -LiteralPath $siteIncludesPath -Force) {
            Copy-Item -LiteralPath $siteIncludeItem.FullName -Destination $effectiveIncludesPath -Recurse -Force
        }
    }

    return $effectiveIncludesPath
}

# Build the Hyde context from defaults, site config, plugins, and data files.
function initializeHydeBuildContext {
    [CmdletBinding()]
    param(
        [string]$Source,
        [string]$Destination,
        [Parameter(Mandatory = $true)]
        [string]$Environment,
        [Parameter(Mandatory = $true)]
        [string]$ModuleRoot,
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    $defaultConfigPath = Join-Path -Path $ModuleRoot -ChildPath 'globalConfig.yaml'
    $siteConfigName = '_config.yml'

    # Start with Hyde defaults, then layer site config and command-line overrides on top.
    Write-Verbose "Loading Hyde defaults from '$defaultConfigPath'."
    $settings = readHydeConfigFile -Path $defaultConfigPath

    $sourceSetting = if ($PSBoundParameters.ContainsKey('Source')) { $Source } else { $settings.source }
    $sourcePath = resolveHydePath -Location $sourceSetting
    Write-Verbose "Resolved source path to '$sourcePath'."

    $siteConfigPath = Join-Path -Path $sourcePath -ChildPath $siteConfigName
    $siteConfig = @{}
    if (Test-Path -LiteralPath $siteConfigPath -PathType Leaf) {
        Write-Verbose "Loading site configuration from '$siteConfigPath'."
        $siteConfig = readHydeConfigFile -Path $siteConfigPath
    } else {
        Write-Verbose "No site configuration file found at '$siteConfigPath'."
    }

    $themeConfig = @{}
    $themePath = ''
    if ($siteConfig.ContainsKey('theme_dir') -and -not [string]::IsNullOrWhiteSpace([string]$siteConfig.theme_dir)) {
        $themePath = resolveHydeThemePath -Settings $siteConfig -SourcePath $sourcePath
        $themeConfigPath = Join-Path -Path $themePath -ChildPath $siteConfigName
        if (Test-Path -LiteralPath $themeConfigPath -PathType Leaf) {
            Write-Verbose "Loading theme configuration from '$themeConfigPath'."
            $themeConfig = readHydeConfigFile -Path $themeConfigPath
        } else {
            Write-Verbose "No theme configuration file found at '$themeConfigPath'."
        }
    }

    if ($themeConfig.Count -gt 0) {
        mergeHydeConfig -Existing $settings -Difference $themeConfig
    }

    if ($siteConfig.Count -gt 0) {
        mergeHydeConfig -Existing $settings -Difference $siteConfig
    }

    if ($PSBoundParameters.ContainsKey('Source')) {
        $settings.source = $Source
    }

    if ($PSBoundParameters.ContainsKey('Destination')) {
        $settings.destination = $Destination
    }

    $destinationPath = resolveHydePath -Location $settings.destination -BasePath $sourcePath -MayNotExist
    Write-Verbose "Resolved destination path to '$destinationPath'."

    # Build up the runtime context that the rest of the pipeline will mutate.
    $context = [HydeBuildContext]::new()
    $context.Version = $Version
    $context.Environment = $Environment
    $context.Settings = $settings
    $context.Site = copyHydeValue -InputObject $settings
    $context.SourcePath = $sourcePath
    $context.DestinationPath = $destinationPath
    $context.ThemePath = $themePath
    $context.EffectiveIncludesPath = newHydeEffectiveIncludesPath -Settings $settings -SourcePath $sourcePath -ThemePath $themePath
    $context.PluginRegistry = newHydePluginRegistry
    $context.LiquidRegistry = New-LiquidExtensionRegistry
    Register-LiquidTrustedType -Registry $context.LiquidRegistry -TypeName HydeDocument
    Register-LiquidTrustedType -Registry $context.LiquidRegistry -TypeName HydeStaticFile

    # These values are generated per invocation and do not come from configuration files.
    $context.Site['time'] = Get-Date
    $context.Site['pages'] = New-Object System.Collections.ArrayList
    $context.Site['posts'] = New-Object System.Collections.ArrayList
    $context.Site['documents'] = New-Object System.Collections.ArrayList
    $context.Site['static_files'] = New-Object System.Collections.ArrayList
    $context.Site['collections'] = @{}
    $context.Site['tags'] = @{}
    $context.Site['categories'] = @{}

    initializeHydeCollections -Context $context

    importHydePlugins -Context $context
    importHydeDataFiles -Context $context
    invokeHydePluginHook -Context $context -HookName 'AfterInitialize' -Arguments @{ Context = $context }
    Write-Verbose "Initialized Hyde build context."

    return $context
}

# Convert configured collections into a normalized definition list.
function getHydeCollectionDefinitions {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    # Collections are configured under the Jekyll-style collections map in _config.yml.
    if (-not $Context.Settings.ContainsKey('collections') -or -not $Context.Settings.collections) {
        return @()
    }

    $definitions = New-Object System.Collections.ArrayList
    foreach ($collectionName in $Context.Settings.collections.Keys) {
        $collectionSettings = if ($Context.Settings.collections[$collectionName] -is [hashtable]) {
            $Context.Settings.collections[$collectionName]
        } else {
            @{}
        }

        [void]$definitions.Add([pscustomobject]@{
            Label     = [string]$collectionName
            Directory = '_' + [string]$collectionName
            Output    = ($collectionSettings.ContainsKey('output') -and [bool]$collectionSettings.output)
            Settings  = $collectionSettings
        })
    }

    return @($definitions.ToArray())
}

# Find a single collection definition by name.
function getHydeCollectionDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context,

        [Parameter(Mandatory = $true)]
        [string]$CollectionName
    )

    foreach ($definition in getHydeCollectionDefinitions -Context $Context) {
        if ($definition.Label -ieq $CollectionName) {
            return $definition
        }
    }

    return $null
}

# Initialize site collection bags on the build context.
function initializeHydeCollections {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    foreach ($definition in getHydeCollectionDefinitions -Context $Context) {
        # Expose collections through both site.collections.<label> and site.<label>.
        $Context.Site.collections[$definition.Label] = @{
            label     = $definition.Label
            directory = $definition.Directory
            output    = $definition.Output
            docs      = New-Object System.Collections.ArrayList
        }

        $Context.Site[$definition.Label] = New-Object System.Collections.ArrayList
    }
}

# Refresh site.posts and collections.posts.docs from published post documents.
function syncHydePosts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    if (-not $Context.Site.ContainsKey('posts') -or -not $Context.Site.ContainsKey('collections') -or -not $Context.Site.collections.ContainsKey('posts')) {
        return
    }

    $eligiblePosts = @(
        $Context.Documents |
            Where-Object {
                $_.CollectionName -eq 'posts' -and
                $_.Published
            } |
            Sort-Object -Property @{ Expression = { $_.PostDate } ; Descending = $true }, @{ Expression = { $_.RelativePath } ; Descending = $false }
    )

    $postLimit = 0
    if ($Context.Settings.ContainsKey('limit_posts') -and $Context.Settings.limit_posts) {
        $postLimit = [int]$Context.Settings.limit_posts
    }

    if ($postLimit -gt 0 -and $eligiblePosts.Count -gt $postLimit) {
        $eligiblePosts = @($eligiblePosts | Select-Object -First $postLimit)
    }

    $Context.Site.posts.Clear()
    $Context.Site.collections.posts.docs.Clear()

    foreach ($post in $eligiblePosts) {
        [void]$Context.Site.posts.Add($post)
        [void]$Context.Site.collections.posts.docs.Add($post)
    }
}

# Populate site.tags and site.categories from published posts.
function syncHydeTaxonomies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    $Context.Site.tags = @{}
    $Context.Site.categories = @{}

    foreach ($document in $Context.Documents) {
        if (-not $document.Published -or $document.CollectionName -ne 'posts') {
            continue
        }

        foreach ($tag in @($document.Tags)) {
            if ([string]::IsNullOrWhiteSpace($tag)) {
                continue
            }

            if (-not $Context.Site.tags.ContainsKey($tag)) {
                $Context.Site.tags[$tag] = New-Object System.Collections.ArrayList
            }

            [void]$Context.Site.tags[$tag].Add($document)
        }

        foreach ($category in @($document.Categories)) {
            if ([string]::IsNullOrWhiteSpace($category)) {
                continue
            }

            if (-not $Context.Site.categories.ContainsKey($category)) {
                $Context.Site.categories[$category] = New-Object System.Collections.ArrayList
            }

            [void]$Context.Site.categories[$category].Add($document)
        }
    }
}

# Normalize the defaults array from configuration for consistent matching.
function getHydeFrontMatterDefaults {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    # Normalize configured defaults into a consistent internal shape.
    if (-not $Context.Settings.ContainsKey('defaults') -or -not $Context.Settings.defaults) {
        return @()
    }

    $defaults = New-Object System.Collections.ArrayList
    $index = 0
    foreach ($entry in $Context.Settings.defaults) {
        if ($null -eq $entry) {
            $index++
            continue
        }

        $scope = if ($entry.scope -is [hashtable]) { $entry.scope } else { @{} }
        $values = if ($entry.values -is [hashtable]) { copyHydeValue -InputObject $entry.values } else { @{} }

        [void]$defaults.Add([pscustomobject]@{
            Index = $index
            Scope = @{
                path = if ($scope.ContainsKey('path') -and $null -ne $scope.path) { ([string]$scope.path).Replace('\', '/').TrimStart('/') } else { '' }
                type = if ($scope.ContainsKey('type') -and $null -ne $scope.type) { [string]$scope.type } else { '' }
            }
            Values = $values
        })

        $index++
    }

    return @($defaults.ToArray())
}

# Score scope paths to prefer more specific defaults.
function getHydeDefaultScopePathSpecificity {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [string]$ScopePath
    )

    if ([string]::IsNullOrWhiteSpace($ScopePath)) {
        return 0
    }

    return ($ScopePath -replace '\*', '').Length
}

# Check whether an item's relative path matches a default scope path.
function testHydeDefaultScopePath {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string]$ScopePath,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($ScopePath)) {
        return $true
    }

    $normalizedScopePath = $ScopePath.Replace('\', '/').Trim('/').Trim()
    $normalizedRelativePath = $RelativePath.Replace('\', '/').TrimStart('/')

    if ($normalizedScopePath.Contains('*')) {
        return ($normalizedRelativePath -like $normalizedScopePath)
    }

    return (
        $normalizedRelativePath -eq $normalizedScopePath -or
        $normalizedRelativePath.StartsWith($normalizedScopePath.TrimEnd('/') + '/', [System.StringComparison]::OrdinalIgnoreCase)
    )
}

# Check whether an item's type matches a default scope type.
function testHydeDefaultScopeType {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string]$ScopeType,
        [string]$ItemType
    )

    if ([string]::IsNullOrWhiteSpace($ScopeType)) {
        return $true
    }

    return ($ScopeType -ieq $ItemType)
}

# Map a content item to its default scope type label.
function getHydeItemDefaultType {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeContentItem]$Item
    )

    switch ($Item.Kind) {
        'Page' { return 'pages' }
        'CollectionDocument' { return $Item.CollectionName }
        default { return '' }
    }
}

# Gather all front matter defaults that apply to the given item.
function getHydeMatchingDefaults {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context,

        [Parameter(Mandatory = $true)]
        [HydeContentItem]$Item
    )

    $defaults = getHydeFrontMatterDefaults -Context $Context
    if (-not $defaults) {
        return @()
    }

    $itemType = getHydeItemDefaultType -Item $Item
    $matchingDefaults = @(
        $defaults | Where-Object {
            (testHydeDefaultScopePath -ScopePath $_.Scope.path -RelativePath $Item.RelativePath) -and
            (testHydeDefaultScopeType -ScopeType $_.Scope.type -ItemType $itemType)
        } | Sort-Object `
            @{ Expression = { getHydeDefaultScopePathSpecificity -ScopePath $_.Scope.path } ; Descending = $true },
            @{ Expression = { if ([string]::IsNullOrWhiteSpace($_.Scope.type)) { 0 } else { 1 } } ; Descending = $true },
            @{ Expression = { $_.Index } ; Descending = $true }
    )

    return @($matchingDefaults)
}

# Apply missing default values to a front matter hashtable.
function mergeHydeFrontMatterDefaults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Target,

        [Parameter(Mandatory = $true)]
        [hashtable]$Defaults
    )

    # Defaults only fill missing values; explicit front matter still wins.
    foreach ($key in $Defaults.Keys) {
        if (-not $Target.ContainsKey($key)) {
            $Target[$key] = copyHydeValue -InputObject $Defaults[$key]
        }
    }
}

# Build the list of generated paths Hyde Clean should remove.
function getHydeCleanTargets {
    [CmdletBinding()]
    [OutputType([System.Collections.ArrayList])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    # Hyde clean intentionally targets the same generated artifacts that Jekyll clean removes.
    $targets = New-Object System.Collections.ArrayList
    $candidatePaths = @(
        @{ Kind = 'destination folder'; Path = $Context.DestinationPath }
        @{ Kind = 'metadata file'; Path = Join-Path -Path $Context.SourcePath -ChildPath '.jekyll-metadata' }
        @{ Kind = 'Jekyll cache'; Path = Join-Path -Path $Context.SourcePath -ChildPath '.jekyll-cache' }
        @{ Kind = 'Sass cache'; Path = Join-Path -Path $Context.SourcePath -ChildPath '.sass-cache' }
    )

    foreach ($candidate in $candidatePaths) {
        if ([string]::IsNullOrWhiteSpace($candidate.Path)) {
            continue
        }

        [void]$targets.Add([pscustomobject]@{
            Kind = $candidate.Kind
            Path = $candidate.Path
        })
    }

    return $targets
}

# Identify a Hyde site root by the presence of _config.yml.
function testHydeSiteRootPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    # A Hyde site root is identified by the presence of the normal site configuration file.
    return (Test-Path -LiteralPath (Join-Path -Path $Path -ChildPath '_config.yml') -PathType Leaf)
}

# Remove a generated file or folder with safety checks.
function removeHydeGeneratedPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Kind
    )

    # TODO: Add safety check to prevent removing the destination if it is a parent of the source
    #  That is also a common misconfiguration that can lead to data loss. Jekyll clean does not protect against this currently, but it would be a valuable safeguard to add in Hyde.



    # TODO: Handle case of destination being a drive


    # Resolve paths first so the safety checks operate on normalized absolute paths.
    $resolvedTargetPath = [System.IO.Path]::GetFullPath($Path)

    # Clean must never remove an actual site source directory, even if the destination points at it.
    if (($Kind -eq 'destination folder') -and (testHydeSiteRootPath -Path $resolvedTargetPath)) {
        throw "Refusing to remove destination folder path '$resolvedTargetPath' because it is the source of a site."
    }

    if (-not (Test-Path -LiteralPath $resolvedTargetPath)) {
        Write-Verbose "Skipping missing $Kind at '$resolvedTargetPath'."
        return
    }

    # Remove files and directories with the appropriate PowerShell cmdlet shape.
    $item = Get-Item -LiteralPath $resolvedTargetPath -Force
    if ($item.PSIsContainer) {
        Remove-Item -LiteralPath $resolvedTargetPath -Recurse -Force
    } else {
        Remove-Item -LiteralPath $resolvedTargetPath -Force
    }

    Write-Verbose "Removed $Kind at '$resolvedTargetPath'."
}
