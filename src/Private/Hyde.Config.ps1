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
