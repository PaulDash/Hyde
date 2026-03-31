param($Context)

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
