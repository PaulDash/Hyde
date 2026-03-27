function newHydePluginRegistry {
    [CmdletBinding()]
    param()

    # Hyde plugins can hook build stages or participate in output path calculation.
    return @{
        Hooks = @{
            AfterInitialize          = New-Object System.Collections.ArrayList
            AfterDiscoverDocument    = New-Object System.Collections.ArrayList
            AfterDiscoverStaticFile  = New-Object System.Collections.ArrayList
            BeforeRenderDocument     = New-Object System.Collections.ArrayList
            AfterRenderDocument      = New-Object System.Collections.ArrayList
            BeforeWriteDocument      = New-Object System.Collections.ArrayList
            AfterWriteDocument       = New-Object System.Collections.ArrayList
            BeforeCopyStaticFile     = New-Object System.Collections.ArrayList
            AfterCopyStaticFile      = New-Object System.Collections.ArrayList
            ResolveDocumentOutputPath = New-Object System.Collections.ArrayList
            ResolveStaticFileOutputPath = New-Object System.Collections.ArrayList
        }
    }
}

function resolveHydePluginDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    $pluginsDirectoryName = if ($Context.Settings.ContainsKey('plugins_dir') -and $Context.Settings.plugins_dir) {
        $Context.Settings.plugins_dir
    } else {
        '_plugins'
    }

    return (Join-Path -Path $Context.SourcePath -ChildPath $pluginsDirectoryName)
}

function getHydePluginConfigurationNames {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    $configuredNames = New-Object System.Collections.ArrayList
    foreach ($settingName in @('plugins', 'gems')) {
        if (-not $Context.Settings.ContainsKey($settingName) -or -not $Context.Settings[$settingName]) {
            continue
        }

        foreach ($pluginName in $Context.Settings[$settingName]) {
            if ([string]::IsNullOrWhiteSpace([string]$pluginName)) {
                continue
            }

            [void]$configuredNames.Add([string]$pluginName)
        }
    }

    return @($configuredNames.ToArray())
}

function getHydePluginCandidateNames {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PluginName
    )

    # Hyde accepts Jekyll-style plugin names and translates them into simpler Hyde-friendly names.
    $candidates = New-Object System.Collections.ArrayList
    [void]$candidates.Add($PluginName)

    if ($PluginName.StartsWith('jekyll-', [System.StringComparison]::OrdinalIgnoreCase)) {
        $trimmedName = $PluginName.Substring(7)
        if (-not [string]::IsNullOrWhiteSpace($trimmedName)) {
            [void]$candidates.Add($trimmedName)
            [void]$candidates.Add("hyde-$trimmedName")
        }
    }

    return @($candidates | Select-Object -Unique)
}

function getHydeWhitelistedPluginNames {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    if (-not $Context.Settings.ContainsKey('whitelist') -or -not $Context.Settings.whitelist) {
        return @()
    }

    return @($Context.Settings.whitelist | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
}

function resolveHydePluginFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    # Hyde plugins are PowerShell scripts under the configured plugin directory.
    $pluginsDirectory = resolveHydePluginDirectory -Context $Context
    $builtInPluginsDirectory = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Plugins'
    if (-not (Test-Path -LiteralPath $pluginsDirectory -PathType Container)) {
        Write-Verbose "No plugin directory found at '$pluginsDirectory'."
        $pluginFiles = @()
    } else {
        $pluginFiles = @(Get-ChildItem -LiteralPath $pluginsDirectory -Filter '*.ps1' -File | Sort-Object BaseName)
    }

    $configuredNames = @(getHydePluginConfigurationNames -Context $Context)
    if ($configuredNames.Count -eq 0) {
        return $pluginFiles
    }

    $pluginMap = @{}
    foreach ($pluginFile in $pluginFiles) {
        $pluginMap[$pluginFile.BaseName] = $pluginFile
    }

    $builtInPluginMap = @{}
    if (Test-Path -LiteralPath $builtInPluginsDirectory -PathType Container) {
        foreach ($pluginFile in Get-ChildItem -LiteralPath $builtInPluginsDirectory -Filter '*.ps1' -File | Sort-Object BaseName) {
            $builtInPluginMap[$pluginFile.BaseName] = $pluginFile
        }
    }

    $resolvedFiles = New-Object System.Collections.ArrayList
    $seenPluginPaths = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($pluginName in $configuredNames) {
        $resolvedPluginFile = $null
        foreach ($candidateName in getHydePluginCandidateNames -PluginName $pluginName) {
            if ($pluginMap.ContainsKey($candidateName)) {
                $resolvedPluginFile = $pluginMap[$candidateName]
                break
            }

            if ($builtInPluginMap.ContainsKey($candidateName)) {
                $resolvedPluginFile = $builtInPluginMap[$candidateName]
                break
            }
        }

        if ($null -eq $resolvedPluginFile) {
            throw "Could not locate plugin '$pluginName' in '$pluginsDirectory' or '$builtInPluginsDirectory'."
        }

        if ($seenPluginPaths.Add($resolvedPluginFile.FullName)) {
            [void]$resolvedFiles.Add($resolvedPluginFile)
        }
    }

    return @($resolvedFiles.ToArray())
}

function testHydePluginAllowed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context,

        [Parameter(Mandatory = $true)]
        [string]$PluginName
    )

    # Safe mode only permits plugins that are explicitly whitelisted.
    $safeModeEnabled = $Context.Settings.ContainsKey('safe') -and [bool]$Context.Settings.safe
    if (-not $safeModeEnabled) {
        return $true
    }

    $whitelist = @(getHydeWhitelistedPluginNames -Context $Context)
    return ($whitelist -contains $PluginName)
}

function registerHydePluginDescriptor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Descriptor,

        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context,

        [Parameter(Mandatory = $true)]
        [string]$PluginPath
    )

    $pluginName = if ($Descriptor.ContainsKey('Name') -and $Descriptor.Name) {
        [string]$Descriptor.Name
    } else {
        [System.IO.Path]::GetFileNameWithoutExtension($PluginPath)
    }

    if ($Descriptor.ContainsKey('Hooks') -and $Descriptor.Hooks) {
        foreach ($hookName in $Descriptor.Hooks.Keys) {
            if (-not $Context.PluginRegistry.Hooks.ContainsKey($hookName)) {
                throw "Plugin '$pluginName' uses unsupported Hyde hook '$hookName'."
            }

            $handler = $Descriptor.Hooks[$hookName]
            if ($handler -isnot [scriptblock]) {
                throw "Plugin '$pluginName' hook '$hookName' must be a script block."
            }

            [void]$Context.PluginRegistry.Hooks[$hookName].Add([pscustomobject]@{
                Plugin = $pluginName
                Path   = $PluginPath
                Action = $handler
            })
        }
    }

    if ($Descriptor.ContainsKey('Liquid') -and $Descriptor.Liquid) {
        $liquidDefinition = $Descriptor.Liquid
        $dialectDefinitions = @{}

        # A simple top-level Tags/Filters block targets the JekyllLiquid dialect by default.
        if (($liquidDefinition.ContainsKey('Tags') -and $liquidDefinition.Tags) -or
            ($liquidDefinition.ContainsKey('Filters') -and $liquidDefinition.Filters)) {
            $dialectDefinitions['JekyllLiquid'] = @{
                Tags    = if ($liquidDefinition.ContainsKey('Tags')) { $liquidDefinition.Tags } else { @{} }
                Filters = if ($liquidDefinition.ContainsKey('Filters')) { $liquidDefinition.Filters } else { @{} }
            }
        }

        if ($liquidDefinition.ContainsKey('Dialects') -and $liquidDefinition.Dialects) {
            foreach ($dialectName in $liquidDefinition.Dialects.Keys) {
                $dialectDefinitions[$dialectName] = $liquidDefinition.Dialects[$dialectName]
            }
        }

        foreach ($dialectName in $dialectDefinitions.Keys) {
            $dialectDefinition = $dialectDefinitions[$dialectName]
            if ($dialectDefinition.Tags) {
                foreach ($tagName in $dialectDefinition.Tags.Keys) {
                    Register-LiquidTag -Registry $Context.LiquidRegistry -Dialect $dialectName -Name ([string]$tagName) -Handler $dialectDefinition.Tags[$tagName]
                }
            }

            if ($dialectDefinition.Filters) {
                foreach ($filterName in $dialectDefinition.Filters.Keys) {
                    Register-LiquidFilter -Registry $Context.LiquidRegistry -Dialect $dialectName -Name ([string]$filterName) -Handler $dialectDefinition.Filters[$filterName]
                }
            }
        }
    }

    [void]$Context.LoadedPlugins.Add([pscustomobject]@{
        Name = $pluginName
        Path = $PluginPath
    })
}

function importHydePlugins {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    $pluginFiles = @(resolveHydePluginFiles -Context $Context)
    if ($pluginFiles.Count -eq 0) {
        Write-Verbose 'No Hyde plugins selected for loading.'
        return
    }

    foreach ($pluginFile in $pluginFiles) {
        if (-not (testHydePluginAllowed -Context $Context -PluginName $pluginFile.BaseName)) {
            Write-Verbose "Skipping plugin '$($pluginFile.BaseName)' because safe mode requires a whitelist entry."
            continue
        }

        Write-Verbose "Loading plugin '$($pluginFile.BaseName)' from '$($pluginFile.FullName)'."
        try {
            $descriptor = & $pluginFile.FullName -Context $Context
        } catch {
            throw "Could not load plugin '$($pluginFile.BaseName)'. $($_.Exception.Message)"
        }

        if ($null -eq $descriptor) {
            Write-Verbose "Plugin '$($pluginFile.BaseName)' did not register any behavior."
            continue
        }

        if ($descriptor -isnot [hashtable]) {
            throw "Plugin '$($pluginFile.BaseName)' must return a hashtable descriptor."
        }

        registerHydePluginDescriptor -Descriptor $descriptor -Context $Context -PluginPath $pluginFile.FullName
    }
}

function invokeHydePluginHook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context,

        [Parameter(Mandatory = $true)]
        [string]$HookName,

        [hashtable]$Arguments = @{}
    )

    if (-not $Context.PluginRegistry.Hooks.ContainsKey($HookName)) {
        throw "Hyde hook '$HookName' is not supported."
    }

    foreach ($hook in $Context.PluginRegistry.Hooks[$HookName]) {
        try {
            & $hook.Action $Arguments
        } catch {
            throw "Plugin '$($hook.Plugin)' failed while running hook '$HookName'. $($_.Exception.Message)"
        }
    }
}

function resolveHydePluginValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context,

        [Parameter(Mandatory = $true)]
        [string]$HookName,

        [Parameter(Mandatory = $true)]
        $CurrentValue,

        [hashtable]$Arguments = @{}
    )

    if (-not $Context.PluginRegistry.Hooks.ContainsKey($HookName)) {
        throw "Hyde hook '$HookName' is not supported."
    }

    $resolvedValue = $CurrentValue
    foreach ($hook in $Context.PluginRegistry.Hooks[$HookName]) {
        try {
            $nextValue = & $hook.Action $resolvedValue $Arguments
        } catch {
            throw "Plugin '$($hook.Plugin)' failed while running hook '$HookName'. $($_.Exception.Message)"
        }

        if ($null -ne $nextValue) {
            $resolvedValue = $nextValue
        }
    }

    return $resolvedValue
}
