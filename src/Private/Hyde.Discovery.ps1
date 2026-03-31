# Build the exclusion and include rules for source discovery.
function getHydeExcludedState {
    [CmdletBinding()]
    [OutputType([hashtable])]
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
    $sourceLeafName = Split-Path -Path $Context.SourcePath -Leaf
    if ($Context.Site.ContainsKey('exclude') -and $Context.Site.exclude) {
        foreach ($entry in $Context.Site.exclude) {
            if ([string]::IsNullOrWhiteSpace($entry)) {
                continue
            }

            # Jekyll exclude entries are relative to the site source, but some sites still write
            # them with the source directory name prefixed (for example "src/file.md").
            $normalizedEntry = $entry.Replace('\', '/').Trim()
            if ($sourceLeafName) {
                $sourcePrefixedEntry = '{0}/' -f $sourceLeafName.Replace('\', '/').Trim('/')
                if ($normalizedEntry.StartsWith($sourcePrefixedEntry, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $normalizedEntry = $normalizedEntry.Substring($sourcePrefixedEntry.Length)
                }
            }

            $normalizedEntry = $normalizedEntry.TrimStart('/')

            if ($entry.StartsWith('/')) {
                $configuredDirectoryExclusions += $normalizedEntry.Trim('/')
                continue
            }

            if ($entry.EndsWith('/')) {
                $configuredDirectoryExclusions += $normalizedEntry.Trim('/')
                continue
            }

            $configuredFileExclusions += $normalizedEntry
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

# Determine whether a file or directory should be excluded from the build.
function testHydeItemExclusion {
    [CmdletBinding()]
    [OutputType([bool])]
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

# Scan the source tree and classify documents versus static files.
function getHydeSourceItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    # Walk the source tree once and classify each file as a renderable document or a static asset.
    $excludedState = getHydeExcludedState -Context $Context
    $markdownExtensions = getHydeMarkdownExtensions -Settings $Context.Settings
    $contentExtensions = @('.htm', '.html') + $markdownExtensions
    $pendingDirectories = New-Object System.Collections.Queue
    $pendingDirectories.Enqueue($Context.SourcePath)

    while ($pendingDirectories.Count -gt 0) {
        $directoryPath = [string]$pendingDirectories.Dequeue()
        Write-Verbose "Scanning directory '$directoryPath'."

        try {
            foreach ($directory in Get-ChildItem -LiteralPath $directoryPath -Directory) {
                $relativeDirectoryPath = [System.IO.Path]::GetRelativePath($Context.SourcePath, $directory.FullName).Replace('\', '/')
                if (testHydeItemExclusion -Item $directory -RelativePath $relativeDirectoryPath -ExcludedState $excludedState) {
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
                if (testHydeItemExclusion -Item $file -RelativePath $relativeFilePath -ExcludedState $excludedState) {
                    Write-Verbose "Excluding file '$relativeFilePath'."
                    continue
                }

                if ($contentExtensions -contains $file.Extension.ToLowerInvariant()) {
                    # Documents move into the rendering pipeline and can later gain front matter and output paths.
                    $document = [HydeDocument]::new('Page', $file.FullName, $relativeFilePath)
                    $document.OutputRelativePath = resolveHydeDocumentOutputPath -Document $document -Context $Context
                    $document.Url = '/' + $document.OutputRelativePath.Replace('\', '/')
                    $Context.AddDocument($document)
                    invokeHydePluginHook -Context $Context -HookName 'AfterDiscoverDocument' -Arguments @{
                        Context  = $Context
                        Document = $document
                    }
                    Write-Verbose "Discovered document '$relativeFilePath'."
                } else {
                    # Everything else is preserved as a static file.
                    $staticFile = [HydeStaticFile]::new($file.FullName, $relativeFilePath)
                    $staticFile.OutputRelativePath = resolveHydeStaticFileOutputPath -StaticFile $staticFile -Context $Context
                    $staticFile.Url = '/' + $relativeFilePath.Replace('\', '/')
                    foreach ($default in getHydeMatchingDefaults -Context $Context -Item $staticFile) {
                        mergeHydeFrontMatterDefaults -Target $staticFile.Metadata -Defaults $default.Values
                    }
                    $Context.AddStaticFile($staticFile)
                    invokeHydePluginHook -Context $Context -HookName 'AfterDiscoverStaticFile' -Arguments @{
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

    getHydeCollectionItems -Context $Context
}

# Initialize a post document’s metadata from its file name and location.
function initializeHydePostDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document
    )

    $normalizedRelativePath = $Document.RelativePath.Replace('\', '/')
    if ($normalizedRelativePath.StartsWith('_drafts/', [System.StringComparison]::OrdinalIgnoreCase)) {
        $Document.CollectionName = 'posts'
        $Document.IsDraft = $true
        $Document.Slug = convertToHydeSlug -Text $Document.BaseName
        $Document.PostDate = (Get-Item -LiteralPath $Document.SourcePath).LastWriteTime
        return
    }

    $postFileNameMatch = [System.Text.RegularExpressions.Regex]::Match(
        $Document.BaseName,
        '^(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})-(?<slug>.+)$'
    )

    if (-not $postFileNameMatch.Success) {
        throw "Post '$($Document.SourcePath)' must use the filename format 'YEAR-MONTH-DAY-title.EXT'."
    }

    try {
        $Document.PostDate = Get-Date -Year ([int]$postFileNameMatch.Groups['year'].Value) -Month ([int]$postFileNameMatch.Groups['month'].Value) -Day ([int]$postFileNameMatch.Groups['day'].Value) -Hour 0 -Minute 0 -Second 0
    } catch {
        throw "Post '$($Document.SourcePath)' has an invalid date in its filename. $($_.Exception.Message)"
    }

    $Document.Slug = convertToHydeSlug -Text $postFileNameMatch.Groups['slug'].Value
}

# Validate whether a document name follows the post filename convention.
function testHydePostFileName {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document
    )

    $normalizedRelativePath = $Document.RelativePath.Replace('\', '/')
    if ($normalizedRelativePath.StartsWith('_drafts/', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    return [System.Text.RegularExpressions.Regex]::IsMatch(
        $Document.BaseName,
        '^(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})-(?<slug>.+)$'
    )
}

# Load supported _data files into site.data.
function importHydeDataFile {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable], [System.Object[]])]
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
        Write-Verbose "No data directory found at '$dataDirectoryPath'."
        return
    }

    try {
        $dataFiles = @(Get-ChildItem -LiteralPath $dataDirectoryPath -File -Recurse | Sort-Object -Property FullName)
    } catch {
        throw "Could not enumerate data files in '$dataDirectoryPath'. $($_.Exception.Message)"
    }

    foreach ($dataFile in $dataFiles) {
        switch ($dataFile.Extension.ToLowerInvariant()) {
            '.yml' { }
            '.yaml' { }
            '.json' { }
            '.csv' { }
            '.tsv' { }
            default {
                Write-Verbose "Skipping unsupported data file '$($dataFile.Name)'."
                continue
            }
        }

        try {
            # Data files map to nested site.data keys based on their path under _data.
            $relativeDataPath = [System.IO.Path]::GetRelativePath($dataDirectoryPath, $dataFile.FullName).Replace('\', '/')
            $pathWithoutExtension = [System.Text.RegularExpressions.Regex]::Replace($relativeDataPath, '\.[^./\\]+$', '')
            $dataPathSegments = @($pathWithoutExtension -split '/' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $dataContent = importHydeDataFile -Path $dataFile.FullName
            setHydeDataValue -Root $Context.Site.data -PathSegments $dataPathSegments -Value $dataContent -SourcePath $relativeDataPath
            Write-Verbose "Imported data file '$relativeDataPath' to 'site.data.$($pathWithoutExtension.Replace('/', '.'))'."
        } catch {
            throw "Could not import data file '$($dataFile.FullName)'. $($_.Exception.Message)"
        }
    }
}

# Assign a parsed data file into the nested site.data map.
function setHydeDataValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Root,

        [Parameter(Mandatory = $true)]
        [string[]]$PathSegments,

        [Parameter(Mandatory = $true)]
        $Value,

        [Parameter(Mandatory = $true)]
        [string]$SourcePath
    )

    if ($PathSegments.Count -eq 0) {
        throw "Data file '$SourcePath' does not resolve to a valid site.data key."
    }

    $currentNode = $Root
    for ($index = 0; $index -lt ($PathSegments.Count - 1); $index++) {
        $segment = $PathSegments[$index]
        if ([string]::IsNullOrWhiteSpace($segment)) {
            throw "Data file '$SourcePath' does not resolve to a valid site.data key."
        }

        if (-not $currentNode.ContainsKey($segment)) {
            # Create intermediate namespace containers for nested _data folders.
            $currentNode[$segment] = @{}
        } elseif ($currentNode[$segment] -isnot [hashtable]) {
            $existingPath = ($PathSegments[0..$index] -join '.')
            throw "Data file '$SourcePath' conflicts with existing site.data entry '$existingPath'."
        }

        $currentNode = $currentNode[$segment]
    }

    $leafSegment = $PathSegments[-1]
    if ([string]::IsNullOrWhiteSpace($leafSegment)) {
        throw "Data file '$SourcePath' does not resolve to a valid site.data key."
    }

    if ($currentNode.ContainsKey($leafSegment)) {
        $existingPath = ($PathSegments -join '.')
        throw "Data file '$SourcePath' conflicts with existing site.data entry '$existingPath'."
    }

    $currentNode[$leafSegment] = $Value
}

# Parse a single data file by extension into PowerShell objects.
function importHydeDataFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Could not validate location of data file '$Path'."
    }

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()

    try {
        # Read the whole file once so each parser gets the original structure.
        $content = Get-Content -LiteralPath $Path -Raw
    } catch {
        throw "Could not read data file '$Path'. $($_.Exception.Message)"
    }

    if ([string]::IsNullOrWhiteSpace($content)) {
        switch ($extension) {
            '.csv' { return @() }
            '.tsv' { return @() }
            default { return @{} }
        }
    }

    try {
        switch ($extension) {
            '.yml' { return (readHydeConfigFile -Path $Path) }
            '.yaml' { return (readHydeConfigFile -Path $Path) }
            '.json' {
                $parsed = ConvertFrom-Json -InputObject $content
                return (convertToHydeHashtable -InputObject $parsed)
            }
            '.csv' {
                $parsed = ConvertFrom-Csv -InputObject $content
                return (convertToHydeHashtable -InputObject $parsed)
            }
            '.tsv' {
                $parsed = ConvertFrom-Csv -InputObject $content -Delimiter "`t"
                return (convertToHydeHashtable -InputObject $parsed)
            }
            default {
                throw "Unsupported data file extension '$extension'."
            }
        }
    } catch {
        throw "Could not parse data file '$Path'. $($_.Exception.Message)"
    }
}

# Discover collection documents (including posts and drafts).
function getHydeCollectionItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    $collectionDefinitions = @(getHydeCollectionDefinitions -Context $Context)
    if ($collectionDefinitions.Count -eq 0) {
        return
    }

    # Collections should honor the same exclusion rules as pages and static files.
    $excludedState = getHydeExcludedState -Context $Context
    $collectionsDirectoryName = if ($Context.Settings.ContainsKey('collections_dir') -and $Context.Settings.collections_dir) {
        $Context.Settings.collections_dir
    } else {
        '.'
    }

    $collectionsRootPath = resolveHydePath -Location $collectionsDirectoryName -BasePath $Context.SourcePath
    $markdownExtensions = getHydeMarkdownExtensions -Settings $Context.Settings
    $contentExtensions = @('.htm', '.html') + $markdownExtensions

    foreach ($definition in $collectionDefinitions) {
        $collectionDirectories = New-Object System.Collections.ArrayList
        if ($definition.Label -eq 'posts') {
            # Jekyll treats any directory above `_posts` as path-based categories, so posts may live in nested `_posts` folders.
            foreach ($postsDirectory in Get-ChildItem -LiteralPath $Context.SourcePath -Directory -Recurse | Where-Object { $_.Name -eq '_posts' }) {
                [void]$collectionDirectories.Add($postsDirectory.FullName)
            }

            $rootPostsDirectoryPath = Join-Path -Path $Context.SourcePath -ChildPath '_posts'
            if ((Test-Path -LiteralPath $rootPostsDirectoryPath -PathType Container) -and ($collectionDirectories -notcontains $rootPostsDirectoryPath)) {
                [void]$collectionDirectories.Add($rootPostsDirectoryPath)
            }
        } else {
            $collectionDirectoryPath = Join-Path -Path $collectionsRootPath -ChildPath $definition.Directory
            if (Test-Path -LiteralPath $collectionDirectoryPath -PathType Container) {
                [void]$collectionDirectories.Add($collectionDirectoryPath)
            }
        }

        foreach ($collectionDirectoryPath in $collectionDirectories) {
            Write-Verbose "Scanning collection '$($definition.Label)' in '$collectionDirectoryPath'."
            foreach ($file in Get-ChildItem -LiteralPath $collectionDirectoryPath -File -Recurse) {
            if ($contentExtensions -notcontains $file.Extension.ToLowerInvariant()) {
                continue
            }

            $relativeFilePath = [System.IO.Path]::GetRelativePath($Context.SourcePath, $file.FullName).Replace('\', '/')
            if (testHydeItemExclusion -Item $file -RelativePath $relativeFilePath -ExcludedState $excludedState) {
                Write-Verbose "Excluding collection document '$relativeFilePath'."
                continue
            }

            $document = [HydeDocument]::new('CollectionDocument', $file.FullName, $relativeFilePath)
            $document.CollectionName = $definition.Label
            $document.WriteOutput = $definition.Output
            if ($definition.Label -eq 'posts') {
                if (-not (testHydePostFileName -Document $document)) {
                    Write-Verbose "Ignoring non-post content '$relativeFilePath' inside a _posts directory."
                    continue
                }

                initializeHydePostDocument -Document $document
            }
            $document.OutputRelativePath = resolveHydeDocumentOutputPath -Document $document -Context $Context
            $document.Url = '/' + $document.OutputRelativePath.Replace('\', '/')
            $Context.AddDocument($document)
            invokeHydePluginHook -Context $Context -HookName 'AfterDiscoverDocument' -Arguments @{
                Context  = $Context
                Document = $document
            }
            Write-Verbose "Discovered collection document '$relativeFilePath' in '$($definition.Label)'."
            }
        }
    }

    $showDrafts = $false
    if ($Context.Settings.ContainsKey('show_drafts') -and $null -ne $Context.Settings.show_drafts) {
        $showDrafts = [bool]$Context.Settings.show_drafts
    }

    if (-not $showDrafts) {
        return
    }

    $draftsDirectoryPath = Join-Path -Path $Context.SourcePath -ChildPath '_drafts'
    if (-not (Test-Path -LiteralPath $draftsDirectoryPath -PathType Container)) {
        return
    }

    Write-Verbose "Scanning drafts in '$draftsDirectoryPath'."
    foreach ($file in Get-ChildItem -LiteralPath $draftsDirectoryPath -File -Recurse) {
        if ($contentExtensions -notcontains $file.Extension.ToLowerInvariant()) {
            continue
        }

        $relativeFilePath = [System.IO.Path]::GetRelativePath($Context.SourcePath, $file.FullName).Replace('\', '/')
        if (testHydeItemExclusion -Item $file -RelativePath $relativeFilePath -ExcludedState $excludedState) {
            Write-Verbose "Excluding draft '$relativeFilePath'."
            continue
        }

        $document = [HydeDocument]::new('CollectionDocument', $file.FullName, $relativeFilePath)
        initializeHydePostDocument -Document $document
        $document.WriteOutput = $true
        $document.OutputRelativePath = resolveHydeDocumentOutputPath -Document $document -Context $Context
        $document.Url = '/' + $document.OutputRelativePath.Replace('\', '/')
        $Context.AddDocument($document)
        invokeHydePluginHook -Context $Context -HookName 'AfterDiscoverDocument' -Arguments @{
            Context  = $Context
            Document = $document
        }
        Write-Verbose "Discovered draft '$relativeFilePath'."
    }
}
