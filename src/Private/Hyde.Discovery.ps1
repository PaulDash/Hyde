function Get-HydeExcludedState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
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
        [HydeBuildContext]$Context
    )

    # Walk the source tree once and classify each file as a renderable document or a static asset.
    $excludedState = Get-HydeExcludedState -Context $Context
    $markdownExtensions = Get-HydeMarkdownExtensions -Settings $Context.Settings
    $contentExtensions = @('.htm', '.html') + $markdownExtensions
    $pendingDirectories = New-Object System.Collections.Queue
    $pendingDirectories.Enqueue($Context.SourcePath)

    while ($pendingDirectories.Count -gt 0) {
        $directoryPath = [string]$pendingDirectories.Dequeue()

        try {
            foreach ($directory in Get-ChildItem -LiteralPath $directoryPath -Directory) {
                $relativeDirectoryPath = [System.IO.Path]::GetRelativePath($Context.SourcePath, $directory.FullName).Replace('\', '/')
                if (Test-HydeItemExclusion -Item $directory -RelativePath $relativeDirectoryPath -ExcludedState $excludedState) {
                    continue
                }

                $pendingDirectories.Enqueue($directory.FullName)
            }
        } catch {
            throw "Could not enumerate directories in '$directoryPath'. $($_.Exception.Message)"
        }

        try {
            foreach ($file in Get-ChildItem -LiteralPath $directoryPath -File) {
                $relativeFilePath = [System.IO.Path]::GetRelativePath($Context.SourcePath, $file.FullName).Replace('\', '/')
                if (Test-HydeItemExclusion -Item $file -RelativePath $relativeFilePath -ExcludedState $excludedState) {
                    continue
                }

                if ($contentExtensions -contains $file.Extension.ToLowerInvariant()) {
                    # Documents move into the rendering pipeline and can later gain front matter and output paths.
                    $document = [HydeDocument]::new('Page', $file.FullName, $relativeFilePath)
                    $document.OutputRelativePath = Resolve-HydeDocumentOutputPath -Document $document -Settings $Context.Settings
                    $document.Url = '/' + $document.OutputRelativePath.Replace('\', '/')
                    $Context.AddDocument($document)
                } else {
                    # Everything else is preserved as a static file.
                    $staticFile = [HydeStaticFile]::new($file.FullName, $relativeFilePath)
                    $staticFile.OutputRelativePath = $relativeFilePath
                    $staticFile.Url = '/' + $relativeFilePath.Replace('\', '/')
                    $Context.AddStaticFile($staticFile)
                }
            }
        } catch {
            throw "Could not enumerate files in '$directoryPath'. $($_.Exception.Message)"
        }
    }
}

function Import-HydeDataFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
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
    }
}
