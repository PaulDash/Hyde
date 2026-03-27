function Merge-HydeConfig {
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
                Merge-HydeConfig -Existing $Existing[$key] -Difference $Difference[$key]
            } else {
                $Existing[$key] = $Difference[$key]
            }
        } else {
            $Existing[$key] = $Difference[$key]
        }
    }
}

function Read-HydeConfigFile {
    [CmdletBinding()]
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
        return (ConvertTo-HydeHashtable -InputObject $parsed)
    } catch {
        throw "Could not parse configuration file '$Path'. $($_.Exception.Message)"
    }
}

function Resolve-HydePath {
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

function Initialize-HydeBuildContext {
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
    $settings = Read-HydeConfigFile -Path $defaultConfigPath

    $sourceSetting = if ($PSBoundParameters.ContainsKey('Source')) { $Source } else { $settings.source }
    $sourcePath = Resolve-HydePath -Location $sourceSetting
    Write-Verbose "Resolved source path to '$sourcePath'."

    $siteConfigPath = Join-Path -Path $sourcePath -ChildPath $siteConfigName
    if (Test-Path -LiteralPath $siteConfigPath -PathType Leaf) {
        Write-Verbose "Loading site configuration from '$siteConfigPath'."
        $siteConfig = Read-HydeConfigFile -Path $siteConfigPath
        Merge-HydeConfig -Existing $settings -Difference $siteConfig
    } else {
        Write-Verbose "No site configuration file found at '$siteConfigPath'."
    }

    if ($PSBoundParameters.ContainsKey('Source')) {
        $settings.source = $Source
    }

    if ($PSBoundParameters.ContainsKey('Destination')) {
        $settings.destination = $Destination
    }

    $destinationPath = Resolve-HydePath -Location $settings.destination -BasePath $sourcePath -MayNotExist
    Write-Verbose "Resolved destination path to '$destinationPath'."

    # Build up the runtime context that the rest of the pipeline will mutate.
    $context = [HydeBuildContext]::new()
    $context.Version = $Version
    $context.Environment = $Environment
    $context.Settings = $settings
    $context.Site = Copy-HydeValue -InputObject $settings
    $context.SourcePath = $sourcePath
    $context.DestinationPath = $destinationPath
    $context.PluginRegistry = New-HydePluginRegistry
    $context.LiquidRegistry = New-LiquidExtensionRegistry

    # These values are generated per invocation and do not come from configuration files.
    $context.Site['time'] = Get-Date
    $context.Site['pages'] = New-Object System.Collections.ArrayList
    $context.Site['posts'] = New-Object System.Collections.ArrayList
    $context.Site['static_files'] = New-Object System.Collections.ArrayList
    $context.Site['collections'] = @{}

    Initialize-HydeCollections -Context $context

    Import-HydePlugins -Context $context
    Import-HydeDataFiles -Context $context
    Invoke-HydePluginHook -Context $context -HookName 'AfterInitialize' -Arguments @{ Context = $context }
    Write-Verbose "Initialized Hyde build context."

    return $context
}

function Get-HydeCollectionDefinitions {
    [CmdletBinding()]
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

function Get-HydeCollectionDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context,

        [Parameter(Mandatory = $true)]
        [string]$CollectionName
    )

    foreach ($definition in Get-HydeCollectionDefinitions -Context $Context) {
        if ($definition.Label -ieq $CollectionName) {
            return $definition
        }
    }

    return $null
}

function Initialize-HydeCollections {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    foreach ($definition in Get-HydeCollectionDefinitions -Context $Context) {
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

function Get-HydeFrontMatterDefaults {
    [CmdletBinding()]
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
        $values = if ($entry.values -is [hashtable]) { Copy-HydeValue -InputObject $entry.values } else { @{} }

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

function Get-HydeDefaultScopePathSpecificity {
    [CmdletBinding()]
    param(
        [string]$ScopePath
    )

    if ([string]::IsNullOrWhiteSpace($ScopePath)) {
        return 0
    }

    return ($ScopePath -replace '\*', '').Length
}

function Test-HydeDefaultScopePath {
    [CmdletBinding()]
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

function Test-HydeDefaultScopeType {
    [CmdletBinding()]
    param(
        [string]$ScopeType,
        [string]$ItemType
    )

    if ([string]::IsNullOrWhiteSpace($ScopeType)) {
        return $true
    }

    return ($ScopeType -ieq $ItemType)
}

function Get-HydeItemDefaultType {
    [CmdletBinding()]
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

function Get-HydeMatchingDefaults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context,

        [Parameter(Mandatory = $true)]
        [HydeContentItem]$Item
    )

    $defaults = Get-HydeFrontMatterDefaults -Context $Context
    if (-not $defaults) {
        return @()
    }

    $itemType = Get-HydeItemDefaultType -Item $Item
    $matchingDefaults = @(
        $defaults | Where-Object {
            (Test-HydeDefaultScopePath -ScopePath $_.Scope.path -RelativePath $Item.RelativePath) -and
            (Test-HydeDefaultScopeType -ScopeType $_.Scope.type -ItemType $itemType)
        } | Sort-Object `
            @{ Expression = { Get-HydeDefaultScopePathSpecificity -ScopePath $_.Scope.path } ; Descending = $true },
            @{ Expression = { if ([string]::IsNullOrWhiteSpace($_.Scope.type)) { 0 } else { 1 } } ; Descending = $true },
            @{ Expression = { $_.Index } ; Descending = $true }
    )

    return @($matchingDefaults)
}

function Merge-HydeFrontMatterDefaults {
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
            $Target[$key] = Copy-HydeValue -InputObject $Defaults[$key]
        }
    }
}

function Get-HydeCleanTargets {
    [CmdletBinding()]
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

function Test-HydeSiteRootPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    # A Hyde site root is identified by the presence of the normal site configuration file.
    return (Test-Path -LiteralPath (Join-Path -Path $Path -ChildPath '_config.yml') -PathType Leaf)
}

function Remove-HydeGeneratedPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$Kind
    )

    # Resolve paths first so the safety checks operate on normalized absolute paths.
    $resolvedSourcePath = [System.IO.Path]::GetFullPath($SourcePath)
    $resolvedTargetPath = [System.IO.Path]::GetFullPath($Path)

    # Clean must never remove an actual site source directory, even if the destination points at it.
    if (($Kind -eq 'destination folder') -and (Test-HydeSiteRootPath -Path $resolvedTargetPath)) {
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
