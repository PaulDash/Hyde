# Convert a published front matter value into a boolean.
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

# Parse a boolean front matter value with a configurable default.
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

# Slugify text for URLs and identifiers.
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

# Parse a date/time value from front matter input.
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

# Determine whether a document represents a post.
function testHydePostDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document
    )

    return ($Document.CollectionName -eq 'posts')
}

# Return normalized categories for a document.
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

# Read a slug override from front matter.
function getHydeDocumentSlugOverride {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document
    )

    if ($Document.FrontMatter.ContainsKey('slug') -and -not [string]::IsNullOrWhiteSpace([string]$Document.FrontMatter.slug)) {
        return [string]$Document.FrontMatter.slug
    }

    return ''
}

# Compute a base filename for a document, stripping post date prefixes.
function getHydeDocumentBaseFileName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document
    )

    if ((testHydePostDocument -Document $Document) -and -not $Document.IsDraft) {
        $postFileNameMatch = [System.Text.RegularExpressions.Regex]::Match(
            $Document.BaseName,
            '^(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})-(?<slug>.+)$'
        )

        if ($postFileNameMatch.Success) {
            return [string]$postFileNameMatch.Groups['slug'].Value
        }
    }

    return $Document.BaseName
}

# Create a slug while preserving case for display purposes.
function getHydePrettySlug {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $normalizedText = [System.Text.RegularExpressions.Regex]::Replace($Text.Trim(), '[^0-9A-Za-z]+', '-')
    return $normalizedText.Trim('-')
}

# Resolve the :title token for permalinks.
function getHydePermalinkTitleValue {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document
    )

    $slugOverride = getHydeDocumentSlugOverride -Document $Document
    if (-not [string]::IsNullOrWhiteSpace($slugOverride)) {
        return (getHydePrettySlug -Text $slugOverride)
    }

    return (getHydePrettySlug -Text (getHydeDocumentBaseFileName -Document $Document))
}

# Resolve the :slug token for permalinks.
function getHydePermalinkSlugValue {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document
    )

    $slugOverride = getHydeDocumentSlugOverride -Document $Document
    if (-not [string]::IsNullOrWhiteSpace($slugOverride)) {
        return (convertToHydeSlug -Text $slugOverride)
    }

    return (convertToHydeSlug -Text (getHydeDocumentBaseFileName -Document $Document))
}

# Resolve the :path token for permalinks.
function getHydePermalinkPathValue {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document
    )

    $normalizedRelativePath = $Document.RelativePath.Replace('\', '/')
    $relativePathWithoutExtension = [System.Text.RegularExpressions.Regex]::Replace($normalizedRelativePath, '\.[^./\\]+$', '')

    if ($Document.Kind -eq 'CollectionDocument' -and -not [string]::IsNullOrWhiteSpace($Document.CollectionName)) {
        $collectionSegment = "_$($Document.CollectionName)/"
        $collectionIndex = $relativePathWithoutExtension.IndexOf($collectionSegment, [System.StringComparison]::OrdinalIgnoreCase)
        if ($collectionIndex -ge 0) {
            return $relativePathWithoutExtension.Substring($collectionIndex + $collectionSegment.Length)
        }
    }

    return $relativePathWithoutExtension
}

# Resolve the :name token for permalinks.
function getHydePermalinkNameValue {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document
    )

    return (convertToHydeSlug -Text (getHydeDocumentBaseFileName -Document $Document))
}

# Resolve the :basename token for permalinks.
function getHydePermalinkBaseNameValue {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document
    )

    return (getHydeDocumentBaseFileName -Document $Document)
}

# Compute ISO week date parts for permalink tokens.
function getHydeWeekDatePart {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$Date
    )

    $isoWeek = [System.Globalization.ISOWeek]::GetWeekOfYear($Date)
    $isoYear = [System.Globalization.ISOWeek]::GetYear($Date)
    $isoDay = [int]$Date.DayOfWeek
    if ($isoDay -eq 0) {
        $isoDay = 7
    }

    return @{
        Week = $isoWeek
        Year = $isoYear
        Day  = $isoDay
    }
}

# Build the permalink token map for a document.
function getHydeDocumentPermalinkTokenValues {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document,

        [Parameter(Mandatory = $true)]
        [string]$DefaultOutputPath
    )

    $isPostDocument = (testHydePostDocument -Document $Document)
    $postDate = if ($isPostDocument -and $Document.PostDate -ne [datetime]::MinValue) { $Document.PostDate } else { $null }
    $weekDatePart = if ($null -ne $postDate) { getHydeWeekDatePart -Date $postDate } else { @{} }
    $dateCulture = [System.Globalization.CultureInfo]::InvariantCulture

    return @{
        collection            = $Document.CollectionName
        title                 = getHydePermalinkTitleValue -Document $Document
        slug                  = getHydePermalinkSlugValue -Document $Document
        name                  = getHydePermalinkNameValue -Document $Document
        basename              = getHydePermalinkBaseNameValue -Document $Document
        path                  = getHydePermalinkPathValue -Document $Document
        categories            = if ($isPostDocument) { ((@($Document.Categories) -join '/').Replace('\', '/')) } else { '' }
        slugified_categories  = if ($isPostDocument) { ((getHydeDocumentCategories -Document $Document) -join '/') } else { '' }
        year                  = if ($null -ne $postDate) { $postDate.ToString('yyyy', $dateCulture) } else { '' }
        short_year            = if ($null -ne $postDate) { $postDate.ToString('yy', $dateCulture) } else { '' }
        month                 = if ($null -ne $postDate) { $postDate.ToString('MM', $dateCulture) } else { '' }
        i_month               = if ($null -ne $postDate) { [string]$postDate.Month } else { '' }
        short_month           = if ($null -ne $postDate) { $postDate.ToString('MMM', $dateCulture) } else { '' }
        long_month            = if ($null -ne $postDate) { $postDate.ToString('MMMM', $dateCulture) } else { '' }
        day                   = if ($null -ne $postDate) { $postDate.ToString('dd', $dateCulture) } else { '' }
        i_day                 = if ($null -ne $postDate) { [string]$postDate.Day } else { '' }
        y_day                 = if ($null -ne $postDate) { $postDate.DayOfYear.ToString('000', $dateCulture) } else { '' }
        w_year                = if ($null -ne $postDate) { [string]$weekDatePart.Year } else { '' }
        week                  = if ($null -ne $postDate) { ([int]$weekDatePart.Week).ToString('00', $dateCulture) } else { '' }
        w_day                 = if ($null -ne $postDate) { [string]$weekDatePart.Day } else { '' }
        short_day             = if ($null -ne $postDate) { $postDate.ToString('ddd', $dateCulture) } else { '' }
        long_day              = if ($null -ne $postDate) { $postDate.ToString('dddd', $dateCulture) } else { '' }
        hour                  = if ($null -ne $postDate) { $postDate.ToString('HH', $dateCulture) } else { '' }
        minute                = if ($null -ne $postDate) { $postDate.ToString('mm', $dateCulture) } else { '' }
        second                = if ($null -ne $postDate) { $postDate.ToString('ss', $dateCulture) } else { '' }
        output_ext            = [System.IO.Path]::GetExtension($DefaultOutputPath)
    }
}

# Map a permalink style name to its pattern string.
function getHydePostPermalinkPattern {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfiguredPermalink
    )

    switch ($ConfiguredPermalink.Trim().ToLowerInvariant()) {
        'date' { return '/:categories/:year/:month/:day/:title:output_ext' }
        'pretty' { return '/:categories/:year/:month/:day/:title/' }
        'ordinal' { return '/:categories/:year/:y_day/:title:output_ext' }
        'weekdate' { return '/:categories/:year/W:week/:short_day/:title:output_ext' }
        'none' { return '/:categories/:title:output_ext' }
        default { return $ConfiguredPermalink }
    }
}

# Extract tag/category terms from front matter keys.
function getHydeDocumentTerms {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document,

        [Parameter(Mandatory = $true)]
        [string[]]$Keys,

        [string[]]$SingularKeys = @()
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
            if ($SingularKeys -contains $key) {
                return @([string]$termsValue.Trim())
            }

            return @($termsValue -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }

        return @([string]$termsValue)
    }

    return @()
}

# Derive post categories from the directory path above _posts.
function getHydePostPathCategories {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document
    )

    if (-not (testHydePostDocument -Document $Document)) {
        return @()
    }

    $relativeDirectory = Split-Path -Path $Document.RelativePath -Parent
    if ([string]::IsNullOrWhiteSpace($relativeDirectory)) {
        return @()
    }

    $segments = @($relativeDirectory.Replace('\', '/') -split '/')
    $postsIndex = [array]::IndexOf($segments, '_posts')
    if ($postsIndex -lt 0) {
        return @()
    }

    if ($postsIndex -eq 0) {
        return @()
    }

    return @(
        $segments[0..($postsIndex - 1)] |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

# Determine the permalink pattern to apply to a document.
function getHydeDocumentPermalinkPattern {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document,

        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    if ($Document.FrontMatter.ContainsKey('permalink') -and
        -not [string]::IsNullOrWhiteSpace([string]$Document.FrontMatter.permalink) -and
        (
            $Document.Kind -ne 'Page' -or
            ($Document.ExplicitFrontMatterKeys -contains 'permalink')
        )) {
        return [string]$Document.FrontMatter.permalink
    }

    if ($Document.Kind -eq 'CollectionDocument' -and -not [string]::IsNullOrWhiteSpace($Document.CollectionName)) {
        $collectionDefinition = getHydeCollectionDefinition -Context $Context -CollectionName $Document.CollectionName
        if ($null -ne $collectionDefinition -and
            $collectionDefinition.Settings.ContainsKey('permalink') -and
            -not [string]::IsNullOrWhiteSpace([string]$collectionDefinition.Settings.permalink)) {
            return (getHydePostPermalinkPattern -ConfiguredPermalink ([string]$collectionDefinition.Settings.permalink))
        }
    }

    if ($Context.Settings.ContainsKey('permalink') -and -not [string]::IsNullOrWhiteSpace([string]$Context.Settings.permalink)) {
        $configuredPermalink = [string]$Context.Settings.permalink
        return (getHydePostPermalinkPattern -ConfiguredPermalink $configuredPermalink)
    }

    if (testHydePostDocument -Document $Document) {
        return (getHydePostPermalinkPattern -ConfiguredPermalink 'date')
    }

    return ''
}

# Resolve a document’s permalink to output path and URL.
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

    $tokenValues = getHydeDocumentPermalinkTokenValues -Document $Document -DefaultOutputPath $DefaultOutputPath

    $resolvedPermalink = $permalinkPattern.Replace('\', '/').Trim()
    foreach ($tokenName in @($tokenValues.Keys | Sort-Object { $_.Length } -Descending)) {
        $resolvedPermalink = $resolvedPermalink.Replace(":$tokenName", [string]$tokenValues[$tokenName])
    }

    # Pages and collections ignore unavailable date and taxonomy placeholders rather than failing.
    $resolvedPermalink = [System.Text.RegularExpressions.Regex]::Replace($resolvedPermalink, ':[A-Za-z_]+', '')
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

# Convert an output-relative path into a site URL.
function convertHydeOutputPathToUrl {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputRelativePath
    )

    $normalizedPath = $OutputRelativePath.Replace('\', '/').TrimStart('/')
    if ([string]::IsNullOrWhiteSpace($normalizedPath)) {
        return '/'
    }

    if ($normalizedPath.EndsWith('/index.html', [System.StringComparison]::OrdinalIgnoreCase)) {
        $urlPath = $normalizedPath.Substring(0, $normalizedPath.Length - 'index.html'.Length)
        if (-not $urlPath.StartsWith('/')) {
            $urlPath = '/' + $urlPath
        }

        return $urlPath
    }

    return '/' + $normalizedPath
}

# Locate a layout file on disk given a layout name.
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

# Pre-parse layout files and cache them in the context.
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

# Retrieve a cached layout document by name.
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

# Build the inheritance chain for a layout.
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

# Resolve the includes directory path for Liquid.
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

# Resolve the root folder for include_relative in post content.
function resolveHydeRelativeIncludeRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document,

        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    # Hyde intentionally limits include_relative to post source files beneath the matching _posts tree.
    if (-not (testHydePostDocument -Document $Document)) {
        return ''
    }

    $relativeSegments = @($Document.RelativePath.Replace('\', '/') -split '/')
    $postsIndex = [array]::IndexOf($relativeSegments, '_posts')
    if ($postsIndex -lt 0) {
        return ''
    }

    $postsRootRelativePath = ($relativeSegments[0..$postsIndex] -join [System.IO.Path]::DirectorySeparatorChar)
    return (Join-Path -Path $Context.SourcePath -ChildPath $postsRootRelativePath)
}

# Delegate to the variables module for building Liquid page variables.
function newHydePageVariables {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document,

        [Parameter(Mandatory = $false)]
        [HydeBuildContext]$Context
    )

    # Proxy to the dedicated variables module for easier maintenance and consistency.
    return newHydePageVariables -Document $Document -Context $Context
}

# Decide whether a document is eligible for pagination.
function testHydePaginationDocument {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document
    )

    if ($Document.Kind -ne 'Page') {
        return $false
    }

    if ($Document.Extension -ne '.html') {
        return $false
    }

    return ($Document.Name -ieq 'index.html')
}

# Compute the output path and URL for a paginated page number.
function resolveHydePaginationOutput {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document,

        [Parameter(Mandatory = $true)]
        [int]$PageNumber,

        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    $baseOutputRelativePath = resolveHydeDocumentOutputPath -Document $Document -Context $Context

    if ($PageNumber -le 1) {
        return @{
            OutputRelativePath = $baseOutputRelativePath
            Url                = convertHydeOutputPathToUrl -OutputRelativePath $baseOutputRelativePath
        }
    }

    $paginatePath = if ($Context.Settings.ContainsKey('paginate_path') -and -not [string]::IsNullOrWhiteSpace([string]$Context.Settings.paginate_path)) {
        [string]$Context.Settings.paginate_path
    } else {
        '/page:num/'
    }

    $resolvedPath = $paginatePath.Replace('\', '/').Replace(':num', [string]$PageNumber).Trim()
    $resolvedPath = $resolvedPath.TrimStart('/')

    $pageDirectory = Split-Path -Path $baseOutputRelativePath -Parent
    if ($pageDirectory -and $pageDirectory -ne '.') {
        $resolvedPath = [System.IO.Path]::Combine($pageDirectory, $resolvedPath).Replace('\', '/')
    }

    $resolvedPath = $resolvedPath.Replace('\', '/').TrimStart('/')
    if ([string]::IsNullOrWhiteSpace($resolvedPath)) {
        $resolvedPath = 'index.html'
    } elseif ($resolvedPath.EndsWith('/')) {
        $resolvedPath += 'index.html'
    } elseif (-not [System.IO.Path]::GetExtension($resolvedPath)) {
        $resolvedPath += '/index.html'
    }

    return @{
        OutputRelativePath = $resolvedPath
        Url                = convertHydeOutputPathToUrl -OutputRelativePath $resolvedPath
    }
}

# Build the paginator object exposed to Liquid templates.
function newHydePaginator {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Posts,

        [Parameter(Mandatory = $true)]
        [int]$PageNumber,

        [Parameter(Mandatory = $true)]
        [int]$PerPage,

        [Parameter(Mandatory = $true)]
        [int]$TotalPosts,

        [Parameter(Mandatory = $true)]
        [int]$TotalPages,

        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document,

        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    $previousPage = $null
    $previousPagePath = $null
    if ($PageNumber -gt 1) {
        $previousPage = $PageNumber - 1
        $previousPagePath = (resolveHydePaginationOutput -Document $Document -PageNumber $previousPage -Context $Context).Url
    }

    $nextPage = $null
    $nextPagePath = $null
    if ($PageNumber -lt $TotalPages) {
        $nextPage = $PageNumber + 1
        $nextPagePath = (resolveHydePaginationOutput -Document $Document -PageNumber $nextPage -Context $Context).Url
    }

    return @{
        page               = $PageNumber
        per_page           = $PerPage
        posts              = @($Posts)
        total_posts        = $TotalPosts
        total_pages        = $TotalPages
        previous_page      = $previousPage
        previous_page_path = $previousPagePath
        next_page          = $nextPage
        next_page_path     = $nextPagePath
    }
}

# Clone a document for a paginated page instance.
function newHydePaginatedDocument {
    [CmdletBinding()]
    [OutputType([HydeDocument])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$SourceDocument,

        [Parameter(Mandatory = $true)]
        [int]$PageNumber,

        [Parameter(Mandatory = $true)]
        [hashtable]$Paginator,

        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    $paginatedDocument = [HydeDocument]::new($SourceDocument.Kind, $SourceDocument.SourcePath, $SourceDocument.RelativePath)
    $paginatedDocument.CollectionName = $SourceDocument.CollectionName
    $paginatedDocument.FrontMatter = copyHydeValue -InputObject $SourceDocument.FrontMatter
    $paginatedDocument.ExplicitFrontMatterKeys = @($SourceDocument.ExplicitFrontMatterKeys)
    $paginatedDocument.LiquidData = @{ paginator = $Paginator }
    $paginatedDocument.RawContent = $SourceDocument.RawContent
    $paginatedDocument.Title = $SourceDocument.Title
    $paginatedDocument.Slug = $SourceDocument.Slug
    $paginatedDocument.Tags = @($SourceDocument.Tags)
    $paginatedDocument.Categories = @($SourceDocument.Categories)
    $paginatedDocument.PostDate = $SourceDocument.PostDate
    $paginatedDocument.Published = $SourceDocument.Published
    $paginatedDocument.WriteOutput = $SourceDocument.WriteOutput
    $paginatedDocument.RenderWithLiquid = $SourceDocument.RenderWithLiquid
    $paginatedDocument.IsPrepared = $true
    $paginatedDocument.IsDraft = $SourceDocument.IsDraft

    $resolvedPaginationOutput = resolveHydePaginationOutput -Document $SourceDocument -PageNumber $PageNumber -Context $Context
    $paginatedDocument.OutputRelativePath = [string]$resolvedPaginationOutput.OutputRelativePath
    $paginatedDocument.Url = [string]$resolvedPaginationOutput.Url

    return $paginatedDocument
}

# Generate paginated documents and attach paginator data.
function initializeHydePagination {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    if (-not $Context.Settings.ContainsKey('paginate') -or -not $Context.Settings.paginate) {
        return
    }

    $perPage = [int]$Context.Settings.paginate
    if ($perPage -le 0) {
        return
    }

    $allPosts = @($Context.Site.posts)
    $totalPosts = $allPosts.Count
    $totalPages = [Math]::Max(1, [int][Math]::Ceiling($totalPosts / [double]$perPage))

    $paginatedDocuments = New-Object System.Collections.ArrayList
    foreach ($document in @($Context.Documents)) {
        if (-not (testHydePaginationDocument -Document $document)) {
            continue
        }

        if ($document.ExplicitFrontMatterKeys -contains 'permalink') {
            Write-Verbose "Skipping pagination for '$($document.RelativePath)' because paginated index pages must not define a permalink."
            continue
        }

        $firstPagePosts = @($allPosts | Select-Object -First $perPage)
        $firstPageOutput = resolveHydePaginationOutput -Document $document -PageNumber 1 -Context $Context
        $document.OutputRelativePath = [string]$firstPageOutput.OutputRelativePath
        $document.Url = [string]$firstPageOutput.Url
        $document.LiquidData['paginator'] = newHydePaginator -Posts $firstPagePosts -PageNumber 1 -PerPage $perPage -TotalPosts $totalPosts -TotalPages $totalPages -Document $document -Context $Context

        for ($pageNumber = 2; $pageNumber -le $totalPages; $pageNumber++) {
            $pagePosts = @($allPosts | Select-Object -Skip (($pageNumber - 1) * $perPage) -First $perPage)
            $paginator = newHydePaginator -Posts $pagePosts -PageNumber $pageNumber -PerPage $perPage -TotalPosts $totalPosts -TotalPages $totalPages -Document $document -Context $Context
            [void]$paginatedDocuments.Add((newHydePaginatedDocument -SourceDocument $document -PageNumber $pageNumber -Paginator $paginator -Context $Context))
        }
    }

    foreach ($paginatedDocument in $paginatedDocuments) {
        $Context.AddDocument($paginatedDocument)
    }
}

# Construct the Liquid context for document or layout rendering.
function newHydeLiquidContext {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document,

        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context,

        [hashtable]$AdditionalContext = @{}
    )

    $liquidContext = @{
        page = newHydePageVariables -Document $Document -Context $Context
        site = $Context.Site
        hyde = @{
            version     = $Context.Version
            environment = $Context.Environment
        }
    }

    foreach ($key in $Document.LiquidData.Keys) {
        $liquidContext[$key] = $Document.LiquidData[$key]
    }

    foreach ($key in $AdditionalContext.Keys) {
        $liquidContext[$key] = $AdditionalContext[$key]
    }

    return $liquidContext
}

# Render a document’s raw content through Liquid.
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

    $liquidContext = newHydeLiquidContext -Document $Document -Context $Context

    $Document.RawContent = Invoke-LiquidTemplate -Template $Document.RawContent -Context $liquidContext -Dialect 'JekyllLiquid' -IncludeRoot (resolveHydeIncludesPath -Context $Context) -CurrentFilePath $Document.SourcePath -RelativeIncludeRoot (resolveHydeRelativeIncludeRoot -Document $Document -Context $Context) -Registry $Context.LiquidRegistry
    Write-Verbose "Rendered Liquid content for '$($Document.RelativePath)'."
}

# Render and apply the layout chain for a document.
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
        $liquidContext = newHydeLiquidContext -Document $Document -Context $Context -AdditionalContext @{
            content = $renderedContent
            layout  = $layoutDocument.FrontMatter
        }

        $renderedContent = Invoke-LiquidTemplate -Template $layoutDocument.RawContent -Context $liquidContext -Dialect 'JekyllLiquid' -IncludeRoot (resolveHydeIncludesPath -Context $Context) -CurrentFilePath $layoutDocument.SourcePath -Registry $Context.LiquidRegistry
    }

    $Document.RenderedContent = $renderedContent
    Write-Verbose "Rendered layout chain '$layoutName' for '$($Document.RelativePath)'."
}

# Parse front matter and apply defaults to a document.
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
                $Document.ExplicitFrontMatterKeys = @($Document.FrontMatter.Keys | ForEach-Object { [string]$_ })
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
    $Document.Tags = @(getHydeDocumentTerms -Document $Document -Keys @('tags', 'tag') -SingularKeys @('tag'))

    $frontMatterCategories = @(getHydeDocumentTerms -Document $Document -Keys @('categories', 'category') -SingularKeys @('category'))
    $pathCategories = @(getHydePostPathCategories -Document $Document)
    $Document.Categories = @(
        @($pathCategories + $frontMatterCategories) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )

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

# Prepare document metadata, hooks, and permalink resolution.
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
    $resolvedOutputPath = resolveHydePluginValue -Context $Context -HookName 'ResolveDocumentOutputPath' -CurrentValue ([string]$resolvedPermalink.OutputRelativePath) -Arguments @{
        Context  = $Context
        Document = $Document
    }

    $document.OutputRelativePath = [string]$resolvedOutputPath
    $document.Url = convertHydeOutputPathToUrl -OutputRelativePath $document.OutputRelativePath

    $Document.IsPrepared = $true
}

# Render a minimal inline-markdown subset for excerpts.
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

# TODO: Handle markdown footnotes




# Convert Markdown content to HTML.
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

# Render a document’s content and apply layouts.
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

# Compute the default output-relative path for a document.
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

    return $outputPath
}

# Compute the output-relative path for a static file.
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

# Write a rendered document to its destination path.
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

# Copy a static file to its destination path.
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
