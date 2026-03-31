<#
.SYNOPSIS
Built-in Hyde plugin that compiles Sass/SCSS static files to CSS.

.DESCRIPTION
`libsass-converter` runs during static-file processing and transforms `.scss` and
`.sass` files into `.css` output.

The plugin preserves folder structure, remaps the extension to `.css`, and cancels
raw-source copy so transformed output replaces direct file copy.

Underscore-prefixed Sass files are treated as partials and are never emitted as
standalone output files.

Use `-Install` to download and bundle required LibSassHost binaries directly
from the plugin script.

.PARAMETER Context
Plugin execution context supplied by Hyde when the plugin is loaded.

This parameter is provided by Hyde's plugin loader and is not intended to be
supplied manually.

.PARAMETER Install
Runs plugin installation flow to download and bundle required LibSassHost assets.

.PARAMETER Version
NuGet package version to install. Use `latest` (default) to auto-resolve the
current published version.

.PARAMETER Force
Rebuilds the local bundle folder when it already exists.

.EXAMPLE
plugins:
    - libsass-converter

Enable the plugin in `_config.yml` so Hyde compiles Sass assets during build.

.EXAMPLE
libsass:
    include_paths:
        - assets/styles

Provide optional include paths (relative to site source or absolute paths) for
Sass imports.

.EXAMPLE
./tools/Get-LibSassHost.ps1

Download and bundle required LibSassHost binaries into the expected plugin path.

.EXAMPLE
./src/Plugins/libsass-converter.ps1 -Install

Installs required LibSassHost assets into the plugin-local bundle folder.

.EXAMPLE
./src/Plugins/libsass-converter.ps1 -Install -Version 2.2.0 -Force

Pins version and rebuilds local bundle assets.

.NOTES
Bundled LibSassHost assets are required. The plugin expects binaries under:
- `src/Plugins/libsass-converter/lib`

Recommended setup:
- Run `./src/Plugins/libsass-converter.ps1 -Install`

Alternative setup:
- Run `./tools/Get-LibSassHost.ps1`

Manual setup:
1. Download the `LibSassHost` NuGet package (`.nupkg`).
2. Extract the package.
3. Copy `LibSassHost.dll` from an available framework folder under `lib/` into
     `src/Plugins/libsass-converter/lib/...`.
4. Copy native runtime files from `runtimes/win-x64/native/` (and optionally
     `runtimes/win-x86/native/`) into matching plugin runtime paths.

If required assets are missing, the plugin fails fast with actionable guidance to
run `./tools/Get-LibSassHost.ps1`.

Compatibility note:
- This plugin uses LibSassHost (LibSass).
- Modern Dart Sass module features such as `@use` and `@forward` are not fully
    supported by LibSass.
- A future `dartsass-converter` plugin can coexist as a separate option; configure
    only one Sass converter plugin for a site.
#>
[CmdletBinding()]
param(
    $Context,

    [switch]$Install,

    [string]$Version = 'latest',

    [switch]$Force
)

if ($Install) {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    function Get-LibSassLatestVersion {
        $indexUrl = 'https://api.nuget.org/v3-flatcontainer/libsasshost/index.json'
        $indexPayload = Invoke-RestMethod -Uri $indexUrl -Method Get
        if ($null -eq $indexPayload -or -not $indexPayload.versions -or $indexPayload.versions.Count -eq 0) {
            throw 'Could not discover LibSassHost versions from NuGet.'
        }

        return [string]($indexPayload.versions | Select-Object -Last 1)
    }

    function Resolve-LibSassInstallVersion {
        param([string]$RequestedVersion)

        if ([string]::IsNullOrWhiteSpace($RequestedVersion) -or $RequestedVersion -eq 'latest') {
            return Get-LibSassLatestVersion
        }

        return $RequestedVersion.Trim()
    }

    function Copy-LibSassInstallAsset {
        param(
            [Parameter(Mandatory = $true)]
            [string]$SourcePath,

            [Parameter(Mandatory = $true)]
            [string]$TargetPath
        )

        $targetDirectory = Split-Path -Path $TargetPath -Parent
        if (-not (Test-Path -LiteralPath $targetDirectory -PathType Container)) {
            [void](New-Item -Path $targetDirectory -ItemType Directory -Force)
        }

        Copy-Item -LiteralPath $SourcePath -Destination $TargetPath -Force
    }

    function downloadLibSassNuGetPackage {
        param(
            [Parameter(Mandatory = $true)]
            [string]$PackageId,

            [Parameter(Mandatory = $true)]
            [string]$PackageVersion,

            [Parameter(Mandatory = $true)]
            [string]$DownloadRoot
        )

        $packageRoot = Join-Path -Path $DownloadRoot -ChildPath ("{0}.{1}" -f $PackageId, $PackageVersion)
        $packageFile = Join-Path -Path $packageRoot -ChildPath ("{0}.{1}.nupkg" -f $PackageId, $PackageVersion)
        $extractRoot = Join-Path -Path $packageRoot -ChildPath 'pkg'

        [void](New-Item -Path $packageRoot -ItemType Directory -Force)

        $lowerId = $PackageId.ToLowerInvariant()
        $lowerVersion = $PackageVersion.ToLowerInvariant()
        $packageUrl = "https://api.nuget.org/v3-flatcontainer/$lowerId/$lowerVersion/$lowerId.$lowerVersion.nupkg"

        Invoke-WebRequest -Uri $packageUrl -OutFile $packageFile
        Expand-Archive -LiteralPath $packageFile -DestinationPath $extractRoot -Force

        return $extractRoot
    }

    $resolvedVersion = Resolve-LibSassInstallVersion -RequestedVersion $Version
    $tempRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("hyde-libsass-install-{0}" -f [System.Guid]::NewGuid().ToString('N'))
    $packagePath = Join-Path -Path $tempRoot -ChildPath 'libsasshost.nupkg'
    $extractPath = Join-Path -Path $tempRoot -ChildPath 'pkg'

    # Installation paths are rooted to this plugin script so it is self-contained.
    $pluginScriptDirectory = Split-Path -Path $PSCommandPath -Parent
    $pluginRoot = Join-Path -Path $pluginScriptDirectory -ChildPath ([System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath))

    try {
        [void](New-Item -Path $tempRoot -ItemType Directory -Force)

        $packageUrl = "https://api.nuget.org/v3-flatcontainer/libsasshost/$resolvedVersion/libsasshost.$resolvedVersion.nupkg"
        Invoke-WebRequest -Uri $packageUrl -OutFile $packagePath
        Expand-Archive -LiteralPath $packagePath -DestinationPath $extractPath -Force

        if ((Test-Path -LiteralPath $pluginRoot -PathType Container) -and $Force) {
            Remove-Item -LiteralPath $pluginRoot -Recurse -Force
        }

        $bundleRoot = $pluginRoot
        [void](New-Item -Path $bundleRoot -ItemType Directory -Force)

        $managedCandidates = @(
            (Join-Path -Path $extractPath -ChildPath 'lib\net10.0\LibSassHost.dll'),
            (Join-Path -Path $extractPath -ChildPath 'lib\net9.0\LibSassHost.dll'),
            (Join-Path -Path $extractPath -ChildPath 'lib\net8.0\LibSassHost.dll'),
            (Join-Path -Path $extractPath -ChildPath 'lib\net7.0\LibSassHost.dll'),
            (Join-Path -Path $extractPath -ChildPath 'lib\netstandard2.0\LibSassHost.dll')
        )

        $managedAssemblyPath = $managedCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
        if ([string]::IsNullOrWhiteSpace([string]$managedAssemblyPath)) {
            throw 'Could not find LibSassHost.dll in NuGet package contents.'
        }

        $relativeManagedPath = $managedAssemblyPath.Substring($extractPath.Length).TrimStart([char[]]@('\', '/'))
        $managedTargetPath = Join-Path -Path $bundleRoot -ChildPath $relativeManagedPath
        Copy-LibSassInstallAsset -SourcePath $managedAssemblyPath -TargetPath $managedTargetPath

        $dependencySpecs = @(
            @{ Id = 'AdvancedStringBuilder'; Version = '0.1.1' }
            @{ Id = 'System.Buffers'; Version = '4.5.1' }
        )

        $managedTargetDirectory = Split-Path -Path $managedTargetPath -Parent
        foreach ($dependencySpec in $dependencySpecs) {
            try {
                $dependencyExtractRoot = downloadLibSassNuGetPackage -PackageId $dependencySpec.Id -PackageVersion $dependencySpec.Version -DownloadRoot $tempRoot

                $dependencyCandidates = @(
                    (Join-Path -Path $dependencyExtractRoot -ChildPath 'lib\netstandard2.0'),
                    (Join-Path -Path $dependencyExtractRoot -ChildPath 'lib\netstandard1.3'),
                    (Join-Path -Path $dependencyExtractRoot -ChildPath 'lib\netstandard1.0')
                )

                $dependencyLibFolder = $dependencyCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Container } | Select-Object -First 1
                if ($null -eq $dependencyLibFolder) {
                    continue
                }

                foreach ($dependencyDll in Get-ChildItem -LiteralPath $dependencyLibFolder -Filter '*.dll' -File) {
                    Copy-LibSassInstallAsset -SourcePath $dependencyDll.FullName -TargetPath (Join-Path -Path $managedTargetDirectory -ChildPath $dependencyDll.Name)
                }
            } catch {
                Write-Warning ("Could not bundle dependency {0} {1}. {2}" -f $dependencySpec.Id, $dependencySpec.Version, $_.Exception.Message)
            }
        }

        foreach ($runtimeFolder in @('win-x64', 'win-x86')) {
            $nativeSourcePath = Join-Path -Path $extractPath -ChildPath ("runtimes\\$runtimeFolder\\native")
            if (-not (Test-Path -LiteralPath $nativeSourcePath -PathType Container)) {
                continue
            }

            $nativeTargetPath = Join-Path -Path $bundleRoot -ChildPath ("runtimes\\$runtimeFolder\\native")
            if (-not (Test-Path -LiteralPath $nativeTargetPath -PathType Container)) {
                [void](New-Item -Path $nativeTargetPath -ItemType Directory -Force)
            }

            foreach ($nativeAsset in Get-ChildItem -LiteralPath $nativeSourcePath -File) {
                Copy-LibSassInstallAsset -SourcePath $nativeAsset.FullName -TargetPath (Join-Path -Path $nativeTargetPath -ChildPath $nativeAsset.Name)
            }
        }

        $nativePackageSpecs = @(
            @{ Id = 'LibSassHost.Native.win-x64'; Version = $resolvedVersion; Runtime = 'win-x64' }
            @{ Id = 'LibSassHost.Native.win-x86'; Version = $resolvedVersion; Runtime = 'win-x86' }
        )

        foreach ($nativePackageSpec in $nativePackageSpecs) {
            try {
                $nativeExtractRoot = downloadLibSassNuGetPackage -PackageId $nativePackageSpec.Id -PackageVersion $nativePackageSpec.Version -DownloadRoot $tempRoot

                $nativeCandidates = @(
                    (Join-Path -Path $nativeExtractRoot -ChildPath ("runtimes\\{0}\\native" -f $nativePackageSpec.Runtime)),
                    (Join-Path -Path $nativeExtractRoot -ChildPath 'native')
                )

                $nativeSourceFolder = $nativeCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Container } | Select-Object -First 1
                if ($null -eq $nativeSourceFolder) {
                    continue
                }

                $nativeTargetFolder = Join-Path -Path $bundleRoot -ChildPath ("runtimes\\{0}\\native" -f $nativePackageSpec.Runtime)
                if (-not (Test-Path -LiteralPath $nativeTargetFolder -PathType Container)) {
                    [void](New-Item -Path $nativeTargetFolder -ItemType Directory -Force)
                }

                foreach ($nativeAsset in Get-ChildItem -LiteralPath $nativeSourceFolder -File) {
                    Copy-LibSassInstallAsset -SourcePath $nativeAsset.FullName -TargetPath (Join-Path -Path $nativeTargetFolder -ChildPath $nativeAsset.Name)
                }
            } catch {
                Write-Warning ("Could not bundle native package {0} {1}. {2}" -f $nativePackageSpec.Id, $nativePackageSpec.Version, $_.Exception.Message)
            }
        }

        if ($VerbosePreference -eq 'Continue' -or $VerbosePreference -eq 'Inquire') {
            Write-Verbose ("Installed LibSassHost {0} assets to '{1}'." -f $resolvedVersion, $bundleRoot)
        }

        return $true
    } finally {
        if (Test-Path -LiteralPath $tempRoot -PathType Container) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}

# Built-in plugin that compiles SCSS/Sass static files to CSS during static copy.
# All logic is inlined to avoid scope issues when hooks are executed in different contexts.
$null = $Context
@{
    Name = 'libsass-converter'
    Hooks = @{
        AfterDiscoverStaticFile = {
            param($Invocation)

            if ($null -ne $Invocation.StaticFile -and $Invocation.StaticFile.Extension -in @('.scss', '.sass')) {
                # Sass convention: underscore-prefixed files are partials
                $Invocation.StaticFile.Metadata['hyde_libsass_is_partial'] = $Invocation.StaticFile.BaseName.StartsWith('_', [System.StringComparison]::Ordinal)
            }
        }

        ResolveStaticFileOutputPath = {
            param($CurrentValue, $Invocation)

            $staticFile = $Invocation.StaticFile
            if ($null -eq $staticFile -or $staticFile.Extension -notin @('.scss', '.sass')) {
                return $CurrentValue
            }

            # Don't emit partial files (they're dependencies only)
            if ($staticFile.BaseName.StartsWith('_', [System.StringComparison]::Ordinal)) {
                return $CurrentValue
            }

            # Compile-to-css: change extension and normalize path separators
            return ([System.IO.Path]::ChangeExtension($CurrentValue, '.css').Replace('\\', '/'))
        }

        BeforeCopyStaticFile = {
            param($Invocation)

            $staticFile = $Invocation.StaticFile
            if ($null -eq $staticFile -or $staticFile.Extension -notin @('.scss', '.sass')) {
                return
            }

            # Partials are never emitted to output
            if ($staticFile.BaseName.StartsWith('_', [System.StringComparison]::Ordinal)) {
                $Invocation.CancelCopy = $true
                return
            }

            # === INLINE COMPILATION LOGIC ===

            # Step 1: Load LibSassHost assembly (cached on repeat).
            $libSassAssembly = [AppDomain]::CurrentDomain.GetAssemblies() |
                Where-Object { $_.GetName().Name -eq 'LibSassHost' } |
                Select-Object -First 1

            if ($null -eq $libSassAssembly) {
                $moduleBase = if ($ExecutionContext.SessionState.Module -and $ExecutionContext.SessionState.Module.ModuleBase) {
                    $ExecutionContext.SessionState.Module.ModuleBase
                } else {
                    Split-Path -Path $PSScriptRoot -Parent
                }

                $bundleRoot = Join-Path -Path $moduleBase -ChildPath 'Plugins\\libsass-converter'
                $candidates = @(
                    (Join-Path -Path $bundleRoot -ChildPath 'LibSassHost.dll'),
                    (Join-Path -Path $bundleRoot -ChildPath 'lib\net10.0\LibSassHost.dll'),
                    (Join-Path -Path $bundleRoot -ChildPath 'lib\net9.0\LibSassHost.dll'),
                    (Join-Path -Path $bundleRoot -ChildPath 'lib\net8.0\LibSassHost.dll'),
                    (Join-Path -Path $bundleRoot -ChildPath 'lib\net7.0\LibSassHost.dll'),
                    (Join-Path -Path $bundleRoot -ChildPath 'lib\netstandard2.0\LibSassHost.dll')
                )

                $selectedDll = $null
                foreach ($candidate in $candidates) {
                    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                        $selectedDll = $candidate
                        break
                    }
                }

                if ($null -eq $selectedDll) {
                    throw "libsass-converter requires LibSassHost binaries. Run: .\\tools\\Get-LibSassHost.ps1"
                }

                # Add runtime native path before loading the managed assembly.
                $runtimeFolder = if ([System.Environment]::Is64BitProcess) { 'win-x64' } else { 'win-x86' }
                $nativePath = Join-Path -Path $bundleRoot -ChildPath "runtimes\$runtimeFolder\native"
                if (Test-Path -LiteralPath $nativePath) {
                    $pathItems = @($env:PATH -split ';')
                    if ($pathItems -notcontains $nativePath) {
                        $env:PATH = "$nativePath;$env:PATH"
                    }
                }

                try {
                    $managedDirectory = Split-Path -Path $selectedDll -Parent
                    foreach ($dependencyDll in Get-ChildItem -LiteralPath $managedDirectory -Filter '*.dll' -File) {
                        if ($dependencyDll.Name -ieq 'LibSassHost.dll') {
                            continue
                        }

                        try {
                            [void][System.Reflection.Assembly]::LoadFrom($dependencyDll.FullName)
                        } catch {
                            # Ignore optional dependency load failures and let compiler load surface hard requirements.
                            Write-Verbose ("Could not load dependency assembly '{0}'. Trying in a different context. {1}" -f $dependencyDll.FullName, $_.Exception.Message)
                        }
                    }

                    $libSassAssembly = [System.Reflection.Assembly]::LoadFrom($selectedDll)
                } catch {
                    throw "Cannot load LibSassHost from '$selectedDll': $($_.Exception.Message)"
                }
            }

            # Step 2: Prepare compilation options using reflection.
            # Newer LibSassHost versions expose CompilationOptions; older builds used SassOptions.
            $optionsType = $libSassAssembly.GetType('LibSassHost.CompilationOptions', $false)
            if ($null -eq $optionsType) {
                $optionsType = $libSassAssembly.GetType('LibSassHost.SassOptions', $true)
            }
            $outputStyleType = $libSassAssembly.GetType('LibSassHost.OutputStyle', $true)
            $options = [System.Activator]::CreateInstance($optionsType)

            # Set output style (expanded for dev, compressed otherwise)
            $style = if ($Invocation.Context.Environment -eq 'development') { 'Expanded' } else { 'Compressed' }
            $styleProp = $optionsType.GetProperty('OutputStyle')
            if ($styleProp) {
                $styleProp.SetValue($options, [System.Enum]::Parse($outputStyleType, $style))
            }

            # Set include paths (always include source dir for relative imports)
            $sourceDir = Split-Path -Path $staticFile.SourcePath -Parent
            $includePathsProp = $optionsType.GetProperty('IncludePaths')
            if ($includePathsProp) {
                $includePathList = [System.Collections.Generic.List[string]]::new()
                [void]$includePathList.Add([string]$sourceDir)

                # Honor Jekyll-style sass.sass_dir when configured.
                if ($Invocation.Context.Settings.ContainsKey('sass') -and
                    $Invocation.Context.Settings.sass -is [hashtable] -and
                    $Invocation.Context.Settings.sass.ContainsKey('sass_dir') -and
                    -not [string]::IsNullOrWhiteSpace([string]$Invocation.Context.Settings.sass.sass_dir)) {
                    $sassDirectoryPath = Join-Path -Path $Invocation.Context.SourcePath -ChildPath ([string]$Invocation.Context.Settings.sass.sass_dir)
                    [void]$includePathList.Add($sassDirectoryPath)

                    if (-not [string]::IsNullOrWhiteSpace($Invocation.Context.ThemePath)) {
                        $themeSassDirectoryPath = Join-Path -Path $Invocation.Context.ThemePath -ChildPath ([string]$Invocation.Context.Settings.sass.sass_dir)
                        if (Test-Path -LiteralPath $themeSassDirectoryPath -PathType Container) {
                            [void]$includePathList.Add($themeSassDirectoryPath)
                        }
                    }
                }

                # Allow plugin-specific include paths from _config.yml under libsass.include_paths.
                if ($Invocation.Context.Settings.ContainsKey('libsass') -and
                    $Invocation.Context.Settings.libsass -is [hashtable] -and
                    $Invocation.Context.Settings.libsass.ContainsKey('include_paths') -and
                    $Invocation.Context.Settings.libsass.include_paths) {
                    foreach ($configuredIncludePath in @($Invocation.Context.Settings.libsass.include_paths)) {
                        if ([string]::IsNullOrWhiteSpace([string]$configuredIncludePath)) {
                            continue
                        }

                        $resolvedIncludePath = if ([System.IO.Path]::IsPathRooted([string]$configuredIncludePath)) {
                            [string]$configuredIncludePath
                        } else {
                            Join-Path -Path $Invocation.Context.SourcePath -ChildPath ([string]$configuredIncludePath)
                        }

                        [void]$includePathList.Add($resolvedIncludePath)
                    }
                }

                $includePathsProp.SetValue($options, $includePathList)
            }

            # Step 3: Compile
            $compilerType = $libSassAssembly.GetType('LibSassHost.SassCompiler', $true)
            $compileMethods = @($compilerType.GetMethods() |
                Where-Object { $_.Name -eq 'CompileFile' -and $_.IsStatic })

            # Some themes include YAML front matter in SCSS files. Strip it before compilation.
            $compileSourcePath = $staticFile.SourcePath
            $tempCompilePath = $null
            $rawSass = Get-Content -LiteralPath $staticFile.SourcePath -Raw
            $frontMatterMatch = [System.Text.RegularExpressions.Regex]::Match(
                $rawSass,
                '\A---\s*\r?\n(.*?)^---\s*(?:\r?\n|$)',
                [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::Multiline
            )

            if ($frontMatterMatch.Success) {
                $sourceDirectory = Split-Path -Path $staticFile.SourcePath -Parent
                $tempCompilePath = Join-Path -Path $sourceDirectory -ChildPath (".hyde-scss-{0}{1}" -f [System.Guid]::NewGuid().ToString('N'), $staticFile.Extension)
                $strippedContent = $rawSass.Substring($frontMatterMatch.Length)
                Set-Content -LiteralPath $tempCompilePath -Encoding UTF8 -Value $strippedContent
                $compileSourcePath = $tempCompilePath
            }

            # Prefer the modern 4-parameter overload: inputPath, outputPath, sourceMapPath, options.
            $method = $compilerType.GetMethod(
                'CompileFile',
                [System.Reflection.BindingFlags]'Public, Static',
                $null,
                [Type[]]@([string], [string], [string], $optionsType),
                $null
            )

            $invokeCompile = {
                if ($null -ne $method) {
                    return $method.Invoke($null, @([string]$compileSourcePath, [string]::Empty, [string]::Empty, $options))
                }

                # Fall back to older 2-parameter overloads where arg2 is *Options.
                $fallbackMethod = $compileMethods |
                    Where-Object {
                        $_.GetParameters().Count -eq 2 -and
                        $_.GetParameters()[0].ParameterType -eq [string] -and
                        $_.GetParameters()[1].ParameterType.Name -like '*Options'
                    } |
                    Select-Object -First 1

                if ($null -ne $fallbackMethod) {
                    return $fallbackMethod.Invoke($null, @([string]$compileSourcePath, $options))
                }

                # Final fallback: single-argument CompileFile(inputPath).
                $fallbackMethod = $compileMethods | Where-Object { $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType -eq [string] } | Select-Object -First 1
                if ($null -eq $fallbackMethod) {
                    throw 'No supported LibSassHost CompileFile overload found.'
                }

                return $fallbackMethod.Invoke($null, @([string]$compileSourcePath))
            }

            $isVerboseBuild = $VerbosePreference -eq 'Continue' -or $VerbosePreference -eq 'Inquire'
            if ($isVerboseBuild) {
                $result = & $invokeCompile
            } else {
                # LibSass can emit warnings through native std handles. Mute those by temporarily
                # redirecting process stdout/stderr to NUL for non-verbose builds.
                if (-not ('Hyde.NativeStdHandle' -as [type])) {
                    Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Hyde_NativeStdHandle {
    [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr GetStdHandle(int nStdHandle);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetStdHandle(int nStdHandle, IntPtr handle);
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] public static extern IntPtr CreateFileW(string fileName, uint desiredAccess, uint shareMode, IntPtr securityAttributes, uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool CloseHandle(IntPtr hObject);
}
"@ -ErrorAction Stop
                }

                $stdOutId = -11
                $stdErrId = -12
                $genericWrite = [uint32]0x40000000
                $fileShareReadWrite = [uint32]0x3
                $openExisting = [uint32]3
                $fileAttributeNormal = [uint32]0x80

                $oldStdOut = [Hyde_NativeStdHandle]::GetStdHandle($stdOutId)
                $oldStdErr = [Hyde_NativeStdHandle]::GetStdHandle($stdErrId)
                $nulHandle = [Hyde_NativeStdHandle]::CreateFileW('NUL', $genericWrite, $fileShareReadWrite, [IntPtr]::Zero, $openExisting, $fileAttributeNormal, [IntPtr]::Zero)

                if ($nulHandle -eq [IntPtr]::Zero -or $nulHandle -eq [IntPtr]::op_Explicit(-1)) {
                    # If NUL handle creation fails, fall back to normal behavior instead of failing build.
                    $result = & $invokeCompile
                }

                if ($nulHandle -ne [IntPtr]::Zero -and $nulHandle -ne [IntPtr]::op_Explicit(-1)) {
                    try {
                        [void][Hyde_NativeStdHandle]::SetStdHandle($stdOutId, $nulHandle)
                        [void][Hyde_NativeStdHandle]::SetStdHandle($stdErrId, $nulHandle)
                        $result = & $invokeCompile
                    } finally {
                        [void][Hyde_NativeStdHandle]::SetStdHandle($stdOutId, $oldStdOut)
                        [void][Hyde_NativeStdHandle]::SetStdHandle($stdErrId, $oldStdErr)
                        [void][Hyde_NativeStdHandle]::CloseHandle($nulHandle)
                    }
                }
            }

            # Extract CSS from result
            $css = if ($result -is [string]) { $result } else { $result.CompiledContent }
            if ([string]::IsNullOrWhiteSpace($css)) {
                throw "Compilation of ' $($staticFile.RelativePath)' returned empty CSS"
            }

            # Step 4: Write output
            $outputPath = Join-Path -Path $Invocation.Context.DestinationPath -ChildPath $staticFile.OutputRelativePath
            $outputDir = Split-Path -Path $outputPath -Parent
            if (-not (Test-Path -LiteralPath $outputDir)) {
                [void](New-Item -Path $outputDir -ItemType Directory -Force)
            }

            Set-Content -LiteralPath $outputPath -Encoding UTF8 -Value $css
            if ($null -ne $tempCompilePath -and (Test-Path -LiteralPath $tempCompilePath -PathType Leaf)) {
                Remove-Item -LiteralPath $tempCompilePath -Force
            }
            $Invocation.CancelCopy = $true
        }
    }
}
