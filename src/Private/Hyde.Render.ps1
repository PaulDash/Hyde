function convertToHydePublishedState {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        $InputObject
    )

    if ($null -eq $InputObject) {
        return $true
    }

    if ($InputObject -is [bool]) {
        return $InputObject
    }

    if ($InputObject -is [string]) {
        switch ($InputObject.Trim().ToLowerInvariant()) {
            'true' { return $true }
            'false' { return $false }
            default { throw "Unsupported value for front matter setting 'published': '$InputObject'." }
        }
    }

    return [bool]$InputObject
}

function convertToHydeBooleanFrontMatterValue {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SettingName,

        $InputObject,

        [bool]$DefaultValue = $true
    )

    if ($null -eq $InputObject) {
        return $DefaultValue
    }

    if ($InputObject -is [bool]) {
        return $InputObject
    }

    if ($InputObject -is [string]) {
        switch ($InputObject.Trim().ToLowerInvariant()) {
            'true' { return $true }
            'false' { return $false }
            default { throw "Unsupported value for front matter setting '$SettingName': '$InputObject'." }
        }
    }

    return [bool]$InputObject
}

function convertToHydeSlug {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $normalizedText = $Text.ToLowerInvariant()
    $normalizedText = [System.Text.RegularExpressions.Regex]::Replace($normalizedText, '[^a-z0-9]+', '-')
    $normalizedText = $normalizedText.Trim('-')

    return $normalizedText
}

function convertToHydeDateTime {
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SettingName,

        $InputObject
    )

    if ($InputObject -is [datetime]) {
        return $InputObject
    }

    if ($InputObject -is [datetimeoffset]) {
        return $InputObject.DateTime
    }

    try {
        return [datetime]$InputObject
    } catch {
        throw "Unsupported value for front matter setting '$SettingName': '$InputObject'."
    }
}

function testHydePostDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document
    )

    return ($Document.CollectionName -eq 'posts')
}

function getHydeDocumentCategories {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document
    )

    # Categories are normalized during document preparation so permalink resolution can reuse them directly.
    return @($Document.Categories | ForEach-Object { convertToHydeSlug -Text $_ })
}

function getHydeDocumentTerms {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document,

        [Parameter(Mandatory = $true)]
        [string[]]$Keys
    )

    foreach ($key in $Keys) {
        if (-not $Document.FrontMatter.ContainsKey($key)) {
            continue
        }

        $termsValue = $Document.FrontMatter[$key]
        if ($null -eq $termsValue) {
            continue
        }

        if ($termsValue -is [System.Collections.IEnumerable] -and $termsValue -isnot [string]) {
            return @(
                $termsValue |
                    ForEach-Object { [string]$_ } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            )
        }

        if ($termsValue -is [string]) {
            return @($termsValue -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }

        return @([string]$termsValue)
    }

    return @()
}

function getHydeDocumentPermalinkPattern {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document,

        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    if ($Document.FrontMatter.ContainsKey('permalink') -and -not [string]::IsNullOrWhiteSpace([string]$Document.FrontMatter.permalink)) {
        return [string]$Document.FrontMatter.permalink
    }

    if ($Document.Kind -eq 'CollectionDocument' -and -not [string]::IsNullOrWhiteSpace($Document.CollectionName)) {
        $collectionDefinition = getHydeCollectionDefinition -Context $Context -CollectionName $Document.CollectionName
        if ($null -ne $collectionDefinition -and
            $collectionDefinition.Settings.ContainsKey('permalink') -and
            -not [string]::IsNullOrWhiteSpace([string]$collectionDefinition.Settings.permalink)) {
            return [string]$collectionDefinition.Settings.permalink
        }
    }

    if (testHydePostDocument -Document $Document) {
        $configuredPermalink = if ($Context.Settings.ContainsKey('permalink') -and -not [string]::IsNullOrWhiteSpace([string]$Context.Settings.permalink)) {
            [string]$Context.Settings.permalink
        } else {
            'date'
        }

        switch ($configuredPermalink.Trim().ToLowerInvariant()) {
            'date' { return '/:categories/:year/:month/:day/:title:output_ext' }
            'pretty' { return '/:categories/:year/:month/:day/:title/' }
            default { return $configuredPermalink }
        }
    }

    return ''
}

function resolveHydePermalink {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document,

        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context,

        [Parameter(Mandatory = $true)]
        [string]$DefaultOutputPath
    )

    $permalinkPattern = getHydeDocumentPermalinkPattern -Document $Document -Context $Context
    if ([string]::IsNullOrWhiteSpace($permalinkPattern)) {
        return @{
            OutputRelativePath = $DefaultOutputPath.Replace('\', '/')
            Url                = '/' + $DefaultOutputPath.Replace('\', '/')
        }
    }

    $titleValue = if (-not [string]::IsNullOrWhiteSpace($Document.Title)) {
        $Document.Title
    } elseif ((testHydePostDocument -Document $Document) -and -not [string]::IsNullOrWhiteSpace($Document.Slug)) {
        $Document.Slug
    } elseif ($Document.FrontMatter.ContainsKey('title') -and -not [string]::IsNullOrWhiteSpace([string]$Document.FrontMatter.title)) {
        [string]$Document.FrontMatter.title
    } else {
        $Document.BaseName
    }

    $postDate = if ($Document.PostDate -ne [datetime]::MinValue) { $Document.PostDate } else { Get-Date }

    $tokenValues = @{
        collection = $Document.CollectionName
        title      = convertToHydeSlug -Text $titleValue
        slug       = if (-not [string]::IsNullOrWhiteSpace($Document.Slug)) { $Document.Slug } else { convertToHydeSlug -Text $titleValue }
        name       = $Document.BaseName
        categories = ((getHydeDocumentCategories -Document $Document) -join '/')
        year       = $postDate.ToString('yyyy')
        month      = $postDate.ToString('MM')
        i_month    = $postDate.Month
        day        = $postDate.ToString('dd')
        i_day      = $postDate.Day
        output_ext = [System.IO.Path]::GetExtension($DefaultOutputPath)
    }

    $resolvedPermalink = $permalinkPattern.Replace('\', '/').Trim()
    foreach ($tokenName in $tokenValues.Keys) {
        $resolvedPermalink = $resolvedPermalink.Replace(":$tokenName", [string]$tokenValues[$tokenName])
    }

    $resolvedPermalink = [System.Text.RegularExpressions.Regex]::Replace($resolvedPermalink, '/+', '/')
    if (-not $resolvedPermalink.StartsWith('/')) {
        $resolvedPermalink = '/' + $resolvedPermalink
    }

    $outputRelativePath = $resolvedPermalink.TrimStart('/')
    if ([string]::IsNullOrWhiteSpace($outputRelativePath)) {
        $outputRelativePath = 'index.html'
        $resolvedPermalink = '/'
    } elseif ($outputRelativePath.EndsWith('/')) {
        $outputRelativePath += 'index.html'
    } elseif (-not [System.IO.Path]::GetExtension($outputRelativePath)) {
        $outputRelativePath += '/index.html'
        $resolvedPermalink += '/'
    }

    return @{
        OutputRelativePath = $outputRelativePath.Replace('\', '/')
        Url                = $resolvedPermalink
    }
}

function resolveHydeLayoutPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LayoutName,

        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    $layoutsDirectoryName = if ($Context.Settings.ContainsKey('layouts_dir') -and $Context.Settings.layouts_dir) {
        $Context.Settings.layouts_dir
    } else {
        '_layouts'
    }

    $layoutsDirectoryPath = Join-Path -Path $Context.SourcePath -ChildPath $layoutsDirectoryName
    $layoutCandidates = @($LayoutName)
    if (-not [System.IO.Path]::GetExtension($LayoutName)) {
        $layoutCandidates += "$LayoutName.html"
    }

    foreach ($candidate in $layoutCandidates) {
        $layoutPath = Join-Path -Path $layoutsDirectoryPath -ChildPath $candidate
        if (Test-Path -LiteralPath $layoutPath -PathType Leaf) {
            return $layoutPath
        }
    }

    throw "Could not find layout '$LayoutName' in '$layoutsDirectoryPath'."
}

function initializeHydeLayouts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    # Parse layout files once so documents and doctor checks resolve the same inheritance graph.
    $Context.Layouts.Clear()

    $layoutsDirectoryName = if ($Context.Settings.ContainsKey('layouts_dir') -and $Context.Settings.layouts_dir) {
        $Context.Settings.layouts_dir
    } else {
        '_layouts'
    }

    $layoutsDirectoryPath = Join-Path -Path $Context.SourcePath -ChildPath $layoutsDirectoryName
    if (-not (Test-Path -LiteralPath $layoutsDirectoryPath -PathType Container)) {
        Write-Verbose "No layouts directory found at '$layoutsDirectoryPath'."
        return
    }

    foreach ($layoutFile in Get-ChildItem -LiteralPath $layoutsDirectoryPath -File) {
        $layoutRelativePath = [System.IO.Path]::GetRelativePath($Context.SourcePath, $layoutFile.FullName).Replace('\', '/')
        $layoutDocument = [HydeDocument]::new('Layout', $layoutFile.FullName, $layoutRelativePath)
        readHydeFrontMatter -Document $layoutDocument

        $Context.Layouts[$layoutFile.Name.ToLowerInvariant()] = $layoutDocument
        if (-not $Context.Layouts.ContainsKey($layoutFile.BaseName.ToLowerInvariant())) {
            $Context.Layouts[$layoutFile.BaseName.ToLowerInvariant()] = $layoutDocument
        }

        Write-Verbose "Pre-parsed layout '$($layoutFile.Name)'."
    }
}

function getHydeLayoutDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LayoutName,

        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    $layoutCandidates = @($LayoutName)
    if (-not [System.IO.Path]::GetExtension($LayoutName)) {
        $layoutCandidates += "$LayoutName.html"
    }

    foreach ($candidate in $layoutCandidates) {
        $normalizedCandidate = $candidate.ToLowerInvariant()
        if ($Context.Layouts.ContainsKey($normalizedCandidate)) {
            return $Context.Layouts[$normalizedCandidate]
        }
    }

    $layoutsDirectoryName = if ($Context.Settings.ContainsKey('layouts_dir') -and $Context.Settings.layouts_dir) {
        $Context.Settings.layouts_dir
    } else {
        '_layouts'
    }

    $layoutsDirectoryPath = Join-Path -Path $Context.SourcePath -ChildPath $layoutsDirectoryName
    throw "Could not find layout '$LayoutName' in '$layoutsDirectoryPath'."
}

function getHydeLayoutChain {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LayoutName,

        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    $layoutChain = New-Object System.Collections.ArrayList
    $visitedLayoutNames = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $currentLayoutName = $LayoutName

    while (-not [string]::IsNullOrWhiteSpace($currentLayoutName) -and $currentLayoutName -notin @('none', 'null')) {
        if (-not $visitedLayoutNames.Add($currentLayoutName)) {
            throw "Layout inheritance cycle detected at layout '$currentLayoutName'."
        }

        $layoutDocument = getHydeLayoutDocument -LayoutName $currentLayoutName -Context $Context
        [void]$layoutChain.Add($layoutDocument)

        if ($layoutDocument.FrontMatter.ContainsKey('layout')) {
            $currentLayoutName = [string]$layoutDocument.FrontMatter.layout
        } else {
            $currentLayoutName = ''
        }
    }

    return @($layoutChain.ToArray())
}

function resolveHydeIncludesPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    # Includes resolve from the configured includes directory and are passed into the Liquid runtime.
    $includesDirectoryName = if ($Context.Settings.ContainsKey('includes_dir') -and $Context.Settings.includes_dir) {
        $Context.Settings.includes_dir
    } else {
        '_includes'
    }

    return (Join-Path -Path $Context.SourcePath -ChildPath $includesDirectoryName)
}

function newHydePageVariables {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document
    )

    $page = @{}
    foreach ($key in $Document.FrontMatter.Keys) {
        $page[$key] = $Document.FrontMatter[$key]
    }

    if (-not [string]::IsNullOrWhiteSpace($Document.Title)) {
        # Document.Title gives plugins and future features a semantic title slot beyond raw front matter.
        $page['title'] = $Document.Title
    }

    $page['content'] = $Document.RenderedContent
    $page['collection'] = $Document.CollectionName
    $page['url'] = $Document.Url
    $page['path'] = $Document.RelativePath
    $page['name'] = $Document.Name
    $page['basename'] = $Document.BaseName
    $page['extname'] = $Document.Extension
    $page['slug'] = $Document.Slug
    $page['tags'] = @($Document.Tags)
    $page['categories'] = @($Document.Categories)
    $page['draft'] = $Document.IsDraft

    if ($Document.PostDate -ne [datetime]::MinValue) {
        $page['date'] = $Document.PostDate
    }

    return $page
}

function invokeHydeDocumentLiquid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document,

        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    if (-not $Document.RenderWithLiquid) {
        Write-Verbose "Liquid rendering disabled for '$($Document.RelativePath)'."
        return
    }

    $liquidContext = @{
        page  = newHydePageVariables -Document $Document
        site  = $Context.Site
        hyde  = @{
            version     = $Context.Version
            environment = $Context.Environment
        }
    }

    $Document.RawContent = Invoke-LiquidTemplate -Template $Document.RawContent -Context $liquidContext -Dialect 'JekyllLiquid' -IncludeRoot (resolveHydeIncludesPath -Context $Context) -Registry $Context.LiquidRegistry
    Write-Verbose "Rendered Liquid content for '$($Document.RelativePath)'."
}

function invokeHydeLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document,

        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    if (-not $Document.FrontMatter.ContainsKey('layout')) {
        return
    }

    $layoutName = [string]$Document.FrontMatter.layout
    if ([string]::IsNullOrWhiteSpace($layoutName) -or $layoutName -in @('none', 'null')) {
        Write-Verbose "No layout applied to '$($Document.RelativePath)'."
        return
    }

    $layoutChain = getHydeLayoutChain -LayoutName $layoutName -Context $Context
    $renderedContent = $Document.RenderedContent

    foreach ($layoutDocument in $layoutChain) {
        Write-Verbose "Applying layout '$([System.IO.Path]::GetFileName($layoutDocument.SourcePath))' to '$($Document.RelativePath)'."
        $liquidContext = @{
            content = $renderedContent
            page    = newHydePageVariables -Document $Document
            site    = $Context.Site
            layout  = $layoutDocument.FrontMatter
            hyde    = @{
                version     = $Context.Version
                environment = $Context.Environment
            }
        }

        $renderedContent = Invoke-LiquidTemplate -Template $layoutDocument.RawContent -Context $liquidContext -Dialect 'JekyllLiquid' -IncludeRoot (resolveHydeIncludesPath -Context $Context) -Registry $Context.LiquidRegistry
    }

    $Document.RenderedContent = $renderedContent
    Write-Verbose "Rendered layout chain '$layoutName' for '$($Document.RelativePath)'."
}

function readHydeFrontMatter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document,

        [HydeBuildContext]$Context,

        [switch]$Strict
    )

    # Read the full source file so we can split the front matter block from the body in one pass.
    $rawFileContent = Get-Content -LiteralPath $Document.SourcePath -Raw
    $Document.FrontMatter = @{}

    if ($rawFileContent.StartsWith("---")) {
        # Match the opening and closing YAML fence at the start of the file, including an empty front matter block.
        $match = [System.Text.RegularExpressions.Regex]::Match(
            $rawFileContent,
            '\A---\s*\r?\n(.*?)^---\s*(?:\r?\n|$)',
            [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::Multiline
        )

        if (-not $match.Success) {
            throw "Front matter in '$($Document.SourcePath)' is not properly terminated."
        }

        $yamlText = $match.Groups[1].Value
        if (-not [string]::IsNullOrWhiteSpace($yamlText)) {
            try {
                $Document.FrontMatter = convertToHydeHashtable -InputObject (ConvertFrom-Yaml -Yaml $yamlText)
            } catch {
                throw "Could not parse front matter in '$($Document.SourcePath)'. $($_.Exception.Message)"
            }
        }

        $Document.RawContent = $rawFileContent.Substring($match.Length)
        Write-Verbose "Parsed front matter for '$($Document.RelativePath)'."
    } else {
        if ($Strict) {
            throw "Strict front matter is enabled but '$($Document.SourcePath)' does not start with front matter."
        }

        $Document.RawContent = $rawFileContent
        Write-Verbose "No front matter found for '$($Document.RelativePath)'."
    }

    # Apply matching defaults before interpreting final front matter flags.
    if ($PSBoundParameters.ContainsKey('Context') -and $null -ne $Context) {
        foreach ($default in getHydeMatchingDefaults -Context $Context -Item $Document) {
            mergeHydeFrontMatterDefaults -Target $Document.FrontMatter -Defaults $default.Values
        }
    }

    # Hyde honors front matter flags early so later stages can skip or alter rendering behavior.
    if ($Document.FrontMatter.ContainsKey('published')) {
        $Document.Published = convertToHydeBooleanFrontMatterValue -SettingName 'published' -InputObject $Document.FrontMatter.published -DefaultValue $true
    }

    if ($Document.FrontMatter.ContainsKey('title') -and -not [string]::IsNullOrWhiteSpace([string]$Document.FrontMatter.title)) {
        # Capture the title semantically so other code does not need to dig through raw front matter.
        $Document.Title = [string]$Document.FrontMatter.title
    } else {
        $Document.Title = ''
    }

    # Store tags and categories semantically so templates and future features can consume them consistently.
    $Document.Tags = @(getHydeDocumentTerms -Document $Document -Keys @('tags', 'tag'))
    $Document.Categories = @(getHydeDocumentTerms -Document $Document -Keys @('categories', 'category'))

    if ($Document.FrontMatter.ContainsKey('render_with_liquid')) {
        $Document.RenderWithLiquid = convertToHydeBooleanFrontMatterValue -SettingName 'render_with_liquid' -InputObject $Document.FrontMatter.render_with_liquid -DefaultValue $true
    }

    if ((testHydePostDocument -Document $Document) -and $Document.FrontMatter.ContainsKey('date')) {
        $Document.PostDate = convertToHydeDateTime -SettingName 'date' -InputObject $Document.FrontMatter.date
    }

    if (testHydePostDocument -Document $Document) {
        $includeDraftPosts = ($Context.Settings.ContainsKey('show_drafts') -and [bool]$Context.Settings.show_drafts)
        $includeFuturePosts = ($Context.Settings.ContainsKey('future') -and [bool]$Context.Settings.future)
        $includeUnpublishedPosts = ($Context.Settings.ContainsKey('unpublished') -and [bool]$Context.Settings.unpublished)

        if ($Document.IsDraft) {
            $Document.Published = $includeDraftPosts
        } elseif (-not $includeFuturePosts -and $Document.PostDate -gt (Get-Date)) {
            $Document.Published = $false
        } elseif (-not $includeUnpublishedPosts -and $Document.FrontMatter.ContainsKey('published') -and -not $Document.Published) {
            $Document.Published = $false
        } elseif ($includeUnpublishedPosts -and $Document.FrontMatter.ContainsKey('published') -and -not $Document.Published) {
            $Document.Published = $true
        }
    }

    Write-Verbose "Document '$($Document.RelativePath)' resolved with title='$($Document.Title)', published=$($Document.Published), and render_with_liquid=$($Document.RenderWithLiquid)."
}

function initializeHydeDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document,

        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    if ($Document.IsPrepared) {
        return
    }

    # Prepare front matter and plugin-derived metadata before any page renders against site.* collections.
    $strictFrontMatter = $false
    if ($Context.Settings.ContainsKey('strict_front_matter')) {
        $strictFrontMatter = [bool]$Context.Settings.strict_front_matter
    }

    readHydeFrontMatter -Document $Document -Context $Context -Strict:$strictFrontMatter

    if ($Document.Published) {
        invokeHydePluginHook -Context $Context -HookName 'BeforeRenderDocument' -Arguments @{
            Context  = $Context
            Document = $Document
        }
    }

    # Resolve permalink-based output after front matter and plugin-derived metadata are available.
    $resolvedPermalink = resolveHydePermalink -Document $Document -Context $Context -DefaultOutputPath $Document.OutputRelativePath
    $document.OutputRelativePath = [string]$resolvedPermalink.OutputRelativePath
    $document.Url = [string]$resolvedPermalink.Url

    $Document.IsPrepared = $true
}

function convertHydeInlineMarkdown {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    # Escape first, then apply a small markdown subset for inline formatting.
    $encoded = [System.Net.WebUtility]::HtmlEncode($Text)

    $encoded = [System.Text.RegularExpressions.Regex]::Replace(
        $encoded,
        '&lt;(https?://[^&]+)&gt;',
        '<a href="$1">$1</a>'
    )

    $encoded = [System.Text.RegularExpressions.Regex]::Replace(
        $encoded,
        '`([^`]+)`',
        '<code>$1</code>'
    )

    $encoded = [System.Text.RegularExpressions.Regex]::Replace(
        $encoded,
        '\[([^\]]+)\]\(([^)]+)\)',
        '<a href="$2">$1</a>'
    )

    $encoded = [System.Text.RegularExpressions.Regex]::Replace(
        $encoded,
        '\*\*([^\*]+)\*\*',
        '<strong>$1</strong>'
    )

    $encoded = [System.Text.RegularExpressions.Regex]::Replace(
        $encoded,
        '__([^_]+)__',
        '<strong>$1</strong>'
    )

    $encoded = [System.Text.RegularExpressions.Regex]::Replace(
        $encoded,
        '(?<!\*)\*([^\*]+)\*(?!\*)',
        '<em>$1</em>'
    )

    $encoded = [System.Text.RegularExpressions.Regex]::Replace(
        $encoded,
        '(?<!_)_([^_]+)_(?!_)',
        '<em>$1</em>'
    )

    return $encoded
}

function convertHydeMarkdown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Markdown
    )

    # Normalize line endings first so the simple parser behaves the same on all platforms.
    $normalizedContent = ($Markdown -replace "`r`n", "`n") -replace "`r", "`n"
    $lines = $normalizedContent -split "`n"
    $blocks = New-Object System.Collections.ArrayList
    $paragraphLines = New-Object System.Collections.ArrayList
    $listItems = New-Object System.Collections.ArrayList
    $codeLines = New-Object System.Collections.ArrayList
    $inCodeFence = $false

    # Buffer-based helpers let the parser convert markdown one block at a time.
    function completeHydeParagraphBuffer {
        if ($paragraphLines.Count -eq 0) {
            return
        }

        $text = ($paragraphLines.ToArray() -join ' ').Trim()
        [void]$blocks.Add("<p>$(convertHydeInlineMarkdown -Text $text)</p>")
        $paragraphLines.Clear()
    }

    function completeHydeListBuffer {
        if ($listItems.Count -eq 0) {
            return
        }

        $items = $listItems.ToArray() | ForEach-Object {
            "<li>$(convertHydeInlineMarkdown -Text $_)</li>"
        }

        [void]$blocks.Add("<ul>$($items -join '')</ul>")
        $listItems.Clear()
    }

    function completeHydeCodeFenceBuffer {
        if ($codeLines.Count -eq 0) {
            [void]$blocks.Add('<pre><code></code></pre>')
            return
        }

        $code = [System.Net.WebUtility]::HtmlEncode(($codeLines.ToArray() -join "`n"))
        [void]$blocks.Add("<pre><code>$code</code></pre>")
        $codeLines.Clear()
    }

    foreach ($line in $lines) {
        if ($line -match '^\s*```') {
            if ($inCodeFence) {
                completeHydeCodeFenceBuffer
                $inCodeFence = $false
            } else {
                completeHydeParagraphBuffer
                completeHydeListBuffer
                $codeLines.Clear()
                $inCodeFence = $true
            }

            continue
        }

        if ($inCodeFence) {
            [void]$codeLines.Add($line)
            continue
        }

        if ([string]::IsNullOrWhiteSpace($line)) {
            completeHydeParagraphBuffer
            completeHydeListBuffer
            continue
        }

        if ($line -match '^(#{1,6})\s+(.*)$') {
            completeHydeParagraphBuffer
            completeHydeListBuffer
            $level = $Matches[1].Length
            $headingText = convertHydeInlineMarkdown -Text $Matches[2].Trim()
            [void]$blocks.Add("<h$level>$headingText</h$level>")
            continue
        }

        if ($line -match '^\s*[-*+]\s+(.*)$') {
            completeHydeParagraphBuffer
            [void]$listItems.Add($Matches[1].Trim())
            continue
        }

        # Raw HTML blocks pass straight through instead of being escaped as markdown paragraphs.
        if ($line.TrimStart().StartsWith('<')) {
            completeHydeParagraphBuffer
            completeHydeListBuffer
            [void]$blocks.Add($line)
            continue
        }

        [void]$paragraphLines.Add($line.Trim())
    }

    if ($inCodeFence) {
        completeHydeCodeFenceBuffer
    } else {
        completeHydeParagraphBuffer
        completeHydeListBuffer
    }

    return ($blocks.ToArray() -join [Environment]::NewLine)
}

function convertHydeDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document,

        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    # Rendering starts by preparing front matter and plugin-derived metadata.
    initializeHydeDocument -Document $Document -Context $Context

    if (-not $Document.Published) {
        Write-Verbose "Stopping render pipeline for unpublished document '$($Document.RelativePath)'."
        return
    }

    # Liquid rendering happens against the document body before any markup conversion.
    invokeHydeDocumentLiquid -Document $Document -Context $Context

    $markdownExtensions = getHydeMarkdownExtensions -Settings $Context.Settings
    if ($Document.Extension -in @('.htm', '.html')) {
        # HTML pages are currently copied through after front matter is stripped.
        $Document.RenderedContent = $Document.RawContent
        Write-Verbose "Using HTML passthrough renderer for '$($Document.RelativePath)'."
    } elseif ($Document.Extension -in $markdownExtensions) {
        # Markdown pages are converted into HTML before being written to disk.
        $Document.RenderedContent = convertHydeMarkdown -Markdown $Document.RawContent
        Write-Verbose "Converted markdown document '$($Document.RelativePath)' to HTML."
    } else {
        throw "No renderer exists for '$($Document.SourcePath)'."
    }

    # Layout rendering happens after the page body itself has been converted.
    invokeHydeLayout -Document $Document -Context $Context
    invokeHydePluginHook -Context $Context -HookName 'AfterRenderDocument' -Arguments @{
        Context  = $Context
        Document = $Document
    }
}

function resolveHydeDocumentOutputPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document,

        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    # Markdown sources render to .html while html inputs keep their existing filenames.
    $markdownExtensions = getHydeMarkdownExtensions -Settings $Context.Settings
    $sourceRelativePath = $Document.RelativePath
    if ($Document.Kind -eq 'CollectionDocument' -and -not [string]::IsNullOrWhiteSpace($Document.CollectionName)) {
        $normalizedRelativePath = $sourceRelativePath.Replace('\', '/')
        if ($Document.CollectionName -eq 'posts') {
            $sourceRelativePath = 'posts/{0}' -f $Document.Name
        } else {
            $collectionMarker = '/_{0}/' -f $Document.CollectionName
            $markerIndex = $normalizedRelativePath.IndexOf($collectionMarker, [System.StringComparison]::OrdinalIgnoreCase)
            if ($markerIndex -ge 0) {
                $pathWithinCollection = $normalizedRelativePath.Substring($markerIndex + $collectionMarker.Length)
                $sourceRelativePath = '{0}/{1}' -f $Document.CollectionName, $pathWithinCollection
            } elseif ($normalizedRelativePath.StartsWith('_{0}/' -f $Document.CollectionName, [System.StringComparison]::OrdinalIgnoreCase)) {
                $sourceRelativePath = '{0}/{1}' -f $Document.CollectionName, $normalizedRelativePath.Substring($Document.CollectionName.Length + 2)
            }
        }
    }

    if ($Document.Extension -in $markdownExtensions) {
        $outputPath = [System.IO.Path]::ChangeExtension($sourceRelativePath, '.html').Replace('\', '/')
    } else {
        $outputPath = $sourceRelativePath.Replace('\', '/')
    }

    return (resolveHydePluginValue -Context $Context -HookName 'ResolveDocumentOutputPath' -CurrentValue $outputPath -Arguments @{
            Context  = $Context
            Document = $Document
        })
}

function resolveHydeStaticFileOutputPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeStaticFile]$StaticFile,

        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    return (resolveHydePluginValue -Context $Context -HookName 'ResolveStaticFileOutputPath' -CurrentValue $StaticFile.RelativePath.Replace('\', '/') -Arguments @{
            Context    = $Context
            StaticFile = $StaticFile
        })
}

function writeHydeDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document,

        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    if (-not $Document.Published -or -not $Document.WriteOutput) {
        return
    }

    invokeHydePluginHook -Context $Context -HookName 'BeforeWriteDocument' -Arguments @{
        Context  = $Context
        Document = $Document
    }

    # Materialize the destination tree lazily as each document is written.
    $destinationPath = Join-Path -Path $Context.DestinationPath -ChildPath $Document.OutputRelativePath
    $destinationDirectory = Split-Path -Path $destinationPath -Parent

    try {
        if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
            [void](New-Item -Path $destinationDirectory -ItemType Directory -Force)
        }

        Set-Content -LiteralPath $destinationPath -Value $Document.RenderedContent -Encoding UTF8
        Write-Verbose "Wrote rendered document to '$destinationPath'."
    } catch {
        throw "Could not write rendered document to '$destinationPath'. $($_.Exception.Message)"
    }

    invokeHydePluginHook -Context $Context -HookName 'AfterWriteDocument' -Arguments @{
        Context  = $Context
        Document = $Document
    }
}

function copyHydeStaticFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
    [HydeStaticFile]$StaticFile,

        [Parameter(Mandatory = $true)]
    [HydeBuildContext]$Context
    )

    # Static files reuse the same output tree logic but skip the rendering step entirely.
    invokeHydePluginHook -Context $Context -HookName 'BeforeCopyStaticFile' -Arguments @{
        Context    = $Context
        StaticFile = $StaticFile
    }

    $destinationPath = Join-Path -Path $Context.DestinationPath -ChildPath $StaticFile.OutputRelativePath
    $destinationDirectory = Split-Path -Path $destinationPath -Parent

    try {
        if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
            [void](New-Item -Path $destinationDirectory -ItemType Directory -Force)
        }

        Copy-Item -LiteralPath $StaticFile.SourcePath -Destination $destinationPath -Force
        Write-Verbose "Copied static file to '$destinationPath'."
    } catch {
        throw "Could not copy static file to '$destinationPath'. $($_.Exception.Message)"
    }

    invokeHydePluginHook -Context $Context -HookName 'AfterCopyStaticFile' -Arguments @{
        Context    = $Context
        StaticFile = $StaticFile
    }
}
