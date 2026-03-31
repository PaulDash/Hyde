param($Context)

# Read optional plugin settings from _config.yml under the libsass key.
function Get-LibSassPluginSettings {
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$BuildContext
    )

    if ($BuildContext.Settings.ContainsKey('libsass') -and $BuildContext.Settings.libsass -is [hashtable]) {
        return $BuildContext.Settings.libsass
    }

    return @{}
}

function Get-LibSassBundleRoot {
    # Keep all plugin-owned assets under the plugin folder so Hyde core stays dependency-agnostic.
    return (Join-Path -Path $PSScriptRoot -ChildPath 'libsass-converter\lib')
}

function Resolve-LibSassManagedAssemblyPath {
    $bundleRoot = Get-LibSassBundleRoot
    # Probe in preferred order to support older/newer package target frameworks.
    $candidates = @(
        (Join-Path -Path $bundleRoot -ChildPath 'lib\netstandard2.0\LibSassHost.dll'),
        (Join-Path -Path $bundleRoot -ChildPath 'lib\net8.0\LibSassHost.dll'),
        (Join-Path -Path $bundleRoot -ChildPath 'lib\net7.0\LibSassHost.dll'),
        (Join-Path -Path $bundleRoot -ChildPath 'LibSassHost.dll')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    return $null
}

function Add-LibSassNativePath {
    $bundleRoot = Get-LibSassBundleRoot
    $runtimeFolderName = if ([System.Environment]::Is64BitProcess) { 'win-x64' } else { 'win-x86' }
    $nativePath = Join-Path -Path $bundleRoot -ChildPath ("runtimes\{0}\native" -f $runtimeFolderName)

    if (-not (Test-Path -LiteralPath $nativePath -PathType Container)) {
        return
    }

    # Prepend runtime-native path so LibSassHost can resolve unmanaged dependencies at runtime.
    $pathEntries = @($env:PATH -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($pathEntries -notcontains $nativePath) {
        $env:PATH = "$nativePath;$env:PATH"
    }
}

function Import-LibSassHostAssembly {
    # Fast path when the assembly was already loaded by a previous file in this build.
    if ($null -ne ([System.Type]::GetType('LibSassHost.SassCompiler, LibSassHost', $false))) {
        return
    }

    $managedAssemblyPath = Resolve-LibSassManagedAssemblyPath
    if ([string]::IsNullOrWhiteSpace($managedAssemblyPath)) {
        throw "The libsass-converter plugin requires bundled LibSassHost DLLs. Run '.\\tools\\Get-LibSassHost.ps1' from the Hyde repository root, or manually place LibSassHost assets under 'src/Plugins/libsass-converter/lib'."
    }

    Add-LibSassNativePath

    try {
        Add-Type -Path $managedAssemblyPath -ErrorAction Stop | Out-Null
    } catch {
        throw "Could not load LibSassHost assembly from '$managedAssemblyPath'. $($_.Exception.Message)"
    }
}

function Get-LibSassOutputStyle {
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$BuildContext
    )

    # Favor readable output in development and compact output elsewhere.
    $defaultStyle = if ($BuildContext.Environment -eq 'development') { 'expanded' } else { 'compressed' }
    $pluginSettings = Get-LibSassPluginSettings -BuildContext $BuildContext

    $configuredStyle = $defaultStyle
    if ($BuildContext.Settings.ContainsKey('sass_style') -and -not [string]::IsNullOrWhiteSpace([string]$BuildContext.Settings.sass_style)) {
        $configuredStyle = [string]$BuildContext.Settings.sass_style
    } elseif ($pluginSettings.ContainsKey('style') -and -not [string]::IsNullOrWhiteSpace([string]$pluginSettings.style)) {
        $configuredStyle = [string]$pluginSettings.style
    }

    $normalizedStyle = $configuredStyle.Trim().ToLowerInvariant()
    switch ($normalizedStyle) {
        'compressed' { return 'Compressed' }
        'expanded' { return 'Expanded' }
        default {
            throw "Unsupported libsass style '$configuredStyle'. Supported styles are 'compressed' and 'expanded'."
        }
    }
}

function Get-LibSassIncludePaths {
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$BuildContext,

        [Parameter(Mandatory = $true)]
        [string]$SourcePath
    )

    $includePaths = New-Object System.Collections.ArrayList
    # Always include the source file directory so relative imports work naturally.
    [void]$includePaths.Add((Split-Path -Path $SourcePath -Parent))

    $pluginSettings = Get-LibSassPluginSettings -BuildContext $BuildContext
    if ($pluginSettings.ContainsKey('include_paths') -and $pluginSettings.include_paths) {
        foreach ($configuredPath in @($pluginSettings.include_paths)) {
            if ([string]::IsNullOrWhiteSpace([string]$configuredPath)) {
                continue
            }

            $resolvedPath = if ([System.IO.Path]::IsPathRooted([string]$configuredPath)) {
                [string]$configuredPath
            } else {
                Join-Path -Path $BuildContext.SourcePath -ChildPath ([string]$configuredPath)
            }

            [void]$includePaths.Add($resolvedPath)
        }
    }

    return @($includePaths | Select-Object -Unique)
}

function New-LibSassOptions {
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$BuildContext,

        [Parameter(Mandatory = $true)]
        [string]$SourcePath
    )

    $optionsType = [System.Type]::GetType('LibSassHost.SassOptions, LibSassHost', $true)
    $outputStyleType = [System.Type]::GetType('LibSassHost.OutputStyle, LibSassHost', $true)

    # Build options via reflection to tolerate minor API differences across package versions.
    $options = [System.Activator]::CreateInstance($optionsType)

    $outputStyleProperty = $optionsType.GetProperty('OutputStyle')
    if ($null -ne $outputStyleProperty) {
        $outputStyle = [System.Enum]::Parse($outputStyleType, (Get-LibSassOutputStyle -BuildContext $BuildContext), $true)
        $outputStyleProperty.SetValue($options, $outputStyle)
    }

    $includePathsProperty = $optionsType.GetProperty('IncludePaths')
    if ($null -ne $includePathsProperty) {
        $includePaths = Get-LibSassIncludePaths -BuildContext $BuildContext -SourcePath $SourcePath
        $includePathsProperty.SetValue($options, $includePaths)
    }

    return $options
}

function Invoke-LibSassCompileFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [object]$Options
    )

    $compilerType = [System.Type]::GetType('LibSassHost.SassCompiler, LibSassHost', $true)
    # Reflection keeps invocation resilient if overload signatures evolve.
    $compileMethods = @($compilerType.GetMethods() | Where-Object {
            $_.Name -eq 'CompileFile' -and $_.IsStatic -and $_.GetParameters().Count -ge 1 -and $_.GetParameters()[0].ParameterType -eq [string]
        })

    $methodWithOptions = $compileMethods | Where-Object {
        $_.GetParameters().Count -eq 2 -and $_.GetParameters()[1].ParameterType.Name -eq 'SassOptions'
    } | Select-Object -First 1

    if ($null -ne $methodWithOptions) {
        return $methodWithOptions.Invoke($null, @($SourcePath, $Options))
    }

    $methodWithoutOptions = $compileMethods | Where-Object { $_.GetParameters().Count -eq 1 } | Select-Object -First 1
    if ($null -ne $methodWithoutOptions) {
        return $methodWithoutOptions.Invoke($null, @($SourcePath))
    }

    throw 'Could not find a supported LibSassHost.SassCompiler.CompileFile overload.'
}

function Get-LibSassCompiledContent {
    param(
        [Parameter(Mandatory = $true)]
        $CompilationResult
    )

    if ($CompilationResult -is [string]) {
        return $CompilationResult
    }

    # Some wrappers expose a result object instead of returning CSS directly.
    $compiledContentProperty = $CompilationResult.PSObject.Properties['CompiledContent']
    if ($null -ne $compiledContentProperty -and -not [string]::IsNullOrWhiteSpace([string]$compiledContentProperty.Value)) {
        return [string]$compiledContentProperty.Value
    }

    throw 'LibSassHost did not return compiled CSS content.'
}

function Test-LibSassPartial {
    param(
        [Parameter(Mandatory = $true)]
        [HydeStaticFile]$StaticFile
    )

    # Match Sass convention: underscore-prefixed files are partials and not emitted directly.
    return $StaticFile.BaseName.StartsWith('_', [System.StringComparison]::Ordinal)
}

# Built-in plugin that compiles SCSS/Sass static files to CSS during static copy.
$null = $Context
@{
    Name = 'libsass-converter'
    Hooks = @{
        AfterDiscoverStaticFile = {
            param($Invocation)

            $staticFile = $Invocation.StaticFile
            if ($null -eq $staticFile) {
                return
            }

            if ($staticFile.Extension -in @('.scss', '.sass')) {
                # Persist partial metadata so later hooks do not need to recompute from path text.
                $staticFile.Metadata['hyde_libsass_is_partial'] = (Test-LibSassPartial -StaticFile $staticFile)
            }
        }

        ResolveStaticFileOutputPath = {
            param($CurrentValue, $Invocation)

            $staticFile = $Invocation.StaticFile
            if ($null -eq $staticFile) {
                return $CurrentValue
            }

            if ($staticFile.Extension -notin @('.scss', '.sass')) {
                return $CurrentValue
            }

            if (Test-LibSassPartial -StaticFile $staticFile) {
                return $CurrentValue
            }

            # Compile-to-css means output path must switch extension while preserving folder structure.
            return ([System.IO.Path]::ChangeExtension($CurrentValue, '.css').Replace('\\', '/'))
        }

        BeforeCopyStaticFile = {
            param($Invocation)

            $staticFile = $Invocation.StaticFile
            if ($null -eq $staticFile -or $staticFile.Extension -notin @('.scss', '.sass')) {
                return
            }

            # Sass partials are dependency inputs and should never be emitted to the output tree.
            if (Test-LibSassPartial -StaticFile $staticFile) {
                $Invocation.CancelCopy = $true
                return
            }

            Import-LibSassHostAssembly

            $destinationPath = Join-Path -Path $Invocation.Context.DestinationPath -ChildPath $staticFile.OutputRelativePath
            $destinationDirectory = Split-Path -Path $destinationPath -Parent
            if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
                [void](New-Item -Path $destinationDirectory -ItemType Directory -Force)
            }

            try {
                $options = New-LibSassOptions -BuildContext $Invocation.Context -SourcePath $staticFile.SourcePath
                $compilationResult = Invoke-LibSassCompileFile -SourcePath $staticFile.SourcePath -Options $options
                $compiledContent = Get-LibSassCompiledContent -CompilationResult $compilationResult

                # Hyde writes transformed output with UTF-8 to match document/static file defaults.
                Set-Content -LiteralPath $destinationPath -Encoding UTF8 -Value $compiledContent
            } catch {
                throw "libsass-converter failed to compile '$($staticFile.RelativePath)'. $($_.Exception.Message)"
            }

            # Cancel the normal static copy because this source file has been transformed.
            $Invocation.CancelCopy = $true
        }
    }
}
