function Get-HydeExcludedState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    # Start with Jekyll-style implicit exclusions, then extend them from config.
    $defaultNamePatterns = @('.*', '_*', '#*', '~*')
    $defaultDirectoryNames = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($settingName in @('data_dir', 'layouts_dir', 'includes_dir', 'plugins_dir')) {
        if ($Context.Settings.ContainsKey($settingName) -and $Context.Settings[$settingName]) {
            [void]$defaultDirectoryNames.Add((Split-Path -Path $Context.Settings[$settingName] -Leaf))
        }
    }

    if ($Context.Settings.ContainsKey('sass') -and
        $Context.Settings.sass -is [hashtable] -and
        $Context.Settings.sass.ContainsKey('sass_dir') -and
        $Context.Settings.sass.sass_dir) {
        [void]$defaultDirectoryNames.Add((Split-Path -Path $Context.Settings.sass.sass_dir -Leaf))
    }

    # Prevent recursive builds by excluding the output folder when it lives under the source tree.
    if ($Context.DestinationPath.StartsWith($Context.SourcePath, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relativeDestination = [System.IO.Path]::GetRelativePath($Context.SourcePath, $Context.DestinationPath)
        if ($relativeDestination -and $relativeDestination -ne '.') {
            [void]$defaultDirectoryNames.Add(($relativeDestination -split '[\\/]' | Select-Object -First 1))
        }
    }

    $configuredFileExclusions = @()
    $configuredDirectoryExclusions = @()
    if ($Context.Site.ContainsKey('exclude') -and $Context.Site.exclude) {
        foreach ($entry in $Context.Site.exclude) {
            if ([string]::IsNullOrWhiteSpace($entry)) {
                continue
            }

            if ($entry.StartsWith('/')) {
                $configuredDirectoryExclusions += $entry.Trim('/').Replace('\', '/')
                continue
            }

            if ($entry.EndsWith('/')) {
                $configuredDirectoryExclusions += $entry.Trim('/').Replace('\', '/')
                continue
            }

            $configuredFileExclusions += $entry.Replace('\', '/')
        }
    }

    $configuredIncludes = @()
    if ($Context.Site.ContainsKey('include') -and $Context.Site.include) {
        $configuredIncludes = @($Context.Site.include | ForEach-Object { $_.Replace('\', '/') })
    }

    return @{
        NamePatterns                  = $defaultNamePatterns
        DefaultDirectoryNames         = $defaultDirectoryNames
        ConfiguredFileExclusions      = $configuredFileExclusions
        ConfiguredDirectoryExclusions = $configuredDirectoryExclusions
        ConfiguredIncludes            = $configuredIncludes
    }
}

function Test-HydeItemExclusion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileSystemInfo]$Item,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [hashtable]$ExcludedState
    )

    $normalizedRelativePath = $RelativePath.Replace('\', '/')

    # Explicit includes win over the normal exclusion rules.
    if ($ExcludedState.ConfiguredIncludes -contains $normalizedRelativePath) {
        return $false
    }

    foreach ($pattern in $ExcludedState.NamePatterns) {
        if ($Item.Name -like $pattern) {
            return $true
        }
    }

    if ($Item.PSIsContainer) {
        if ($ExcludedState.DefaultDirectoryNames.Contains($Item.Name)) {
            return $true
        }

        foreach ($directoryPath in $ExcludedState.ConfiguredDirectoryExclusions) {
            if ($normalizedRelativePath -eq $directoryPath -or $normalizedRelativePath.StartsWith("$directoryPath/")) {
                return $true
            }
        }

        return $false
    }

    foreach ($filePath in $ExcludedState.ConfiguredFileExclusions) {
        if ($normalizedRelativePath -eq $filePath) {
            return $true
        }
    }

    return $false
}

function Get-HydeSourceItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    # Walk the source tree once and classify each file as a renderable document or a static asset.
    $excludedState = Get-HydeExcludedState -Context $Context
    $markdownExtensions = Get-HydeMarkdownExtensions -Settings $Context.Settings
    $contentExtensions = @('.htm', '.html') + $markdownExtensions
    $pendingDirectories = New-Object System.Collections.Queue
    $pendingDirectories.Enqueue($Context.SourcePath)

    while ($pendingDirectories.Count -gt 0) {
        $directoryPath = [string]$pendingDirectories.Dequeue()
        Write-Verbose "Scanning directory '$directoryPath'."

        try {
            foreach ($directory in Get-ChildItem -LiteralPath $directoryPath -Directory) {
                $relativeDirectoryPath = [System.IO.Path]::GetRelativePath($Context.SourcePath, $directory.FullName).Replace('\', '/')
                if (Test-HydeItemExclusion -Item $directory -RelativePath $relativeDirectoryPath -ExcludedState $excludedState) {
                    Write-Verbose "Excluding directory '$relativeDirectoryPath'."
                    continue
                }

                Write-Verbose "Queueing directory '$relativeDirectoryPath'."
                $pendingDirectories.Enqueue($directory.FullName)
            }
        } catch {
            throw "Could not enumerate directories in '$directoryPath'. $($_.Exception.Message)"
        }

        try {
            foreach ($file in Get-ChildItem -LiteralPath $directoryPath -File) {
                $relativeFilePath = [System.IO.Path]::GetRelativePath($Context.SourcePath, $file.FullName).Replace('\', '/')
                if (Test-HydeItemExclusion -Item $file -RelativePath $relativeFilePath -ExcludedState $excludedState) {
                    Write-Verbose "Excluding file '$relativeFilePath'."
                    continue
                }

                if ($contentExtensions -contains $file.Extension.ToLowerInvariant()) {
                    # Documents move into the rendering pipeline and can later gain front matter and output paths.
                    $document = [HydeDocument]::new('Page', $file.FullName, $relativeFilePath)
                    $document.OutputRelativePath = Resolve-HydeDocumentOutputPath -Document $document -Context $Context
                    $document.Url = '/' + $document.OutputRelativePath.Replace('\', '/')
                    $Context.AddDocument($document)
                    Invoke-HydePluginHook -Context $Context -HookName 'AfterDiscoverDocument' -Arguments @{
                        Context  = $Context
                        Document = $document
                    }
                    Write-Verbose "Discovered document '$relativeFilePath'."
                } else {
                    # Everything else is preserved as a static file.
                    $staticFile = [HydeStaticFile]::new($file.FullName, $relativeFilePath)
                    $staticFile.OutputRelativePath = Resolve-HydeStaticFileOutputPath -StaticFile $staticFile -Context $Context
                    $staticFile.Url = '/' + $relativeFilePath.Replace('\', '/')
                    foreach ($default in Get-HydeMatchingDefaults -Context $Context -Item $staticFile) {
                        Merge-HydeFrontMatterDefaults -Target $staticFile.Metadata -Defaults $default.Values
                    }
                    $Context.AddStaticFile($staticFile)
                    Invoke-HydePluginHook -Context $Context -HookName 'AfterDiscoverStaticFile' -Arguments @{
                        Context    = $Context
                        StaticFile = $staticFile
                    }
                    Write-Verbose "Discovered static file '$relativeFilePath'."
                }
            }
        } catch {
            throw "Could not enumerate files in '$directoryPath'. $($_.Exception.Message)"
        }
    }

    Get-HydeCollectionItems -Context $Context
}

function Import-HydeDataFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    # Hyde exposes _data files through site.data before any documents are rendered.
    if (-not $Context.Site.ContainsKey('data')) {
        $Context.Site['data'] = @{}
    }

    $dataDirectoryName = if ($Context.Settings.ContainsKey('data_dir') -and $Context.Settings.data_dir) {
        $Context.Settings.data_dir
    } else {
        '_data'
    }

    $dataDirectoryPath = Join-Path -Path $Context.SourcePath -ChildPath $dataDirectoryName
    if (-not (Test-Path -LiteralPath $dataDirectoryPath -PathType Container)) {
        Write-Verbose "No data directory found at '$dataDirectoryPath'."
        return
    }

    foreach ($dataFile in Get-ChildItem -LiteralPath $dataDirectoryPath -File) {
        switch ($dataFile.Extension.ToLowerInvariant()) {
            '.yml' { }
            '.yaml' { }
            default { continue }
        }

        $dataContent = Read-HydeConfigFile -Path $dataFile.FullName
        $Context.Site.data[$dataFile.BaseName] = $dataContent
        Write-Verbose "Imported data file '$($dataFile.Name)'."
    }
}

function Get-HydeCollectionItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    $collectionDefinitions = @(Get-HydeCollectionDefinitions -Context $Context)
    if ($collectionDefinitions.Count -eq 0) {
        return
    }

    $collectionsDirectoryName = if ($Context.Settings.ContainsKey('collections_dir') -and $Context.Settings.collections_dir) {
        $Context.Settings.collections_dir
    } else {
        '.'
    }

    $collectionsRootPath = Resolve-HydePath -Location $collectionsDirectoryName -BasePath $Context.SourcePath
    $markdownExtensions = Get-HydeMarkdownExtensions -Settings $Context.Settings
    $contentExtensions = @('.htm', '.html') + $markdownExtensions

    foreach ($definition in $collectionDefinitions) {
        $collectionDirectoryPath = Join-Path -Path $collectionsRootPath -ChildPath $definition.Directory
        if (-not (Test-Path -LiteralPath $collectionDirectoryPath -PathType Container)) {
            continue
        }

        Write-Verbose "Scanning collection '$($definition.Label)' in '$collectionDirectoryPath'."
        foreach ($file in Get-ChildItem -LiteralPath $collectionDirectoryPath -File -Recurse) {
            if ($contentExtensions -notcontains $file.Extension.ToLowerInvariant()) {
                continue
            }

            $relativeFilePath = [System.IO.Path]::GetRelativePath($Context.SourcePath, $file.FullName).Replace('\', '/')
            $document = [HydeDocument]::new('CollectionDocument', $file.FullName, $relativeFilePath)
            $document.CollectionName = $definition.Label
            $document.WriteOutput = $definition.Output
            $document.OutputRelativePath = Resolve-HydeDocumentOutputPath -Document $document -Context $Context
            $document.Url = '/' + $document.OutputRelativePath.Replace('\', '/')
            $Context.AddDocument($document)
            Invoke-HydePluginHook -Context $Context -HookName 'AfterDiscoverDocument' -Arguments @{
                Context  = $Context
                Document = $document
            }
            Write-Verbose "Discovered collection document '$relativeFilePath' in '$($definition.Label)'."
        }
    }
}
