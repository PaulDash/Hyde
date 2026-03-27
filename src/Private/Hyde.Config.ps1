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
        [string]$ScriptPath
    )

    $moduleRoot = Split-Path -Parent $ScriptPath
    $defaultConfigPath = Join-Path -Path $moduleRoot -ChildPath 'globalConfig.yaml'
    $siteConfigName = '_config.yml'

    # Start with Hyde defaults, then layer site config and command-line overrides on top.
    $settings = Read-HydeConfigFile -Path $defaultConfigPath

    $sourceSetting = if ($PSBoundParameters.ContainsKey('Source')) { $Source } else { $settings.source }
    $sourcePath = Resolve-HydePath -Location $sourceSetting

    $siteConfigPath = Join-Path -Path $sourcePath -ChildPath $siteConfigName
    if (Test-Path -LiteralPath $siteConfigPath -PathType Leaf) {
        $siteConfig = Read-HydeConfigFile -Path $siteConfigPath
        Merge-HydeConfig -Existing $settings -Difference $siteConfig
    }

    if ($PSBoundParameters.ContainsKey('Source')) {
        $settings.source = $Source
    }

    if ($PSBoundParameters.ContainsKey('Destination')) {
        $settings.destination = $Destination
    }

    $destinationPath = Resolve-HydePath -Location $settings.destination -BasePath $sourcePath -MayNotExist

    # Build up the runtime context that the rest of the pipeline will mutate.
    $context = [HydeBuildContext]::new()
    $context.Version = (Get-PSScriptFileInfo -Path $ScriptPath).ScriptMetadataComment.Version.Version.ToString()
    $context.Environment = $Environment
    $context.Settings = $settings
    $context.Site = Copy-HydeValue -InputObject $settings
    $context.SourcePath = $sourcePath
    $context.DestinationPath = $destinationPath

    # These values are generated per invocation and do not come from configuration files.
    $context.Site['time'] = Get-Date
    $context.Site['pages'] = New-Object System.Collections.ArrayList
    $context.Site['posts'] = New-Object System.Collections.ArrayList
    $context.Site['static_files'] = New-Object System.Collections.ArrayList

    Import-HydeDataFiles -Context $context

    return $context
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
        $Item
    )

    switch ($Item.Kind) {
        'Page' { return 'pages' }
        default { return '' }
    }
}

function Get-HydeMatchingDefaults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context,

        [Parameter(Mandatory = $true)]
        $Item
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

    # Refuse paths that look too short to be a real generated child path.
    if ($resolvedTargetPath.Length -lt ($resolvedSourcePath.Length + 2) -and
        $resolvedTargetPath -ne $resolvedSourcePath) {
        throw "Refusing to remove suspicious $Kind path '$resolvedTargetPath'."
    }

    # Clean is currently conservative and only removes paths inside the source tree.
    if (($resolvedTargetPath -ne $resolvedSourcePath) -and
        (-not $resolvedTargetPath.StartsWith($resolvedSourcePath + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "Refusing to remove $Kind path '$resolvedTargetPath' because it is outside the site source '$resolvedSourcePath'."
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
