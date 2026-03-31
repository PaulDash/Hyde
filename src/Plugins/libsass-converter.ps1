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

            # Step 1: Import LibSassHost assembly (cached on repeat)
            if ($null -eq ([System.Type]::GetType('LibSassHost.SassCompiler, LibSassHost', $false))) {
                $bundleRoot = Join-Path -Path (Split-Path -Path "$PSScriptRoot" -Parent) -ChildPath 'Plugins\libsass-converter\lib'
                $candidates = @(
                    (Join-Path -Path $bundleRoot -ChildPath 'lib\netstandard2.0\LibSassHost.dll'),
                    (Join-Path -Path $bundleRoot -ChildPath 'lib\net8.0\LibSassHost.dll'),
                    (Join-Path -Path $bundleRoot -ChildPath 'lib\net7.0\LibSassHost.dll'),
                    (Join-Path -Path $bundleRoot -ChildPath 'LibSassHost.dll')
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

                # Add runtime natives to PATH
                $runtimes = @('win-x64', 'win-x86')
                $runtimeFolder = if ([System.Environment]::Is64BitProcess) { 'win-x64' } else { 'win-x86' }
                $nativePath = Join-Path -Path $bundleRoot -ChildPath "runtimes\$runtimeFolder\native"
                if (Test-Path -LiteralPath $nativePath) {
                    $pathItems = @($env:PATH -split ';')
                    if ($pathItems -notcontains $nativePath) {
                        $env:PATH = "$nativePath;$env:PATH"
                    }
                }

                try {
                    Add-Type -Path $selectedDll -ErrorAction Stop | Out-Null
                } catch {
                    throw "Cannot load LibSassHost from '$selectedDll': $($_.Exception.Message)"
                }
            }

            # Step 2: Prepare compilation options using reflection
            $optionsType = [System.Type]::GetType('LibSassHost.SassOptions, LibSassHost', $true)
            $outputStyleType = [System.Type]::GetType('LibSassHost.OutputStyle, LibSassHost', $true)
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
                $includePathsProp.SetValue($options, @($sourceDir))
            }

            # Step 3: Compile
            $compilerType = [System.Type]::GetType('LibSassHost.SassCompiler, LibSassHost', $true)
            $compileMethods = @($compilerType.GetMethods() |
                Where-Object { $_.Name -eq 'CompileFile' -and $_.IsStatic })

            $method = $compileMethods |
                Where-Object { $_.GetParameters()[1].ParameterType.Name -eq 'SassOptions' } |
                Select-Object -First 1

            if ($null -eq $method) {
                $method = $compileMethods | Where-Object { $_.GetParameters().Count -eq 1 } | Select-Object -First 1
                $result = $method.Invoke($null, @($staticFile.SourcePath))
            } else {
                $result = $method.Invoke($null, @($staticFile.SourcePath, $options))
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
            $Invocation.CancelCopy = $true
        }
    }
}
