Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-HydeDocumentVariableSlug {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document
    )

    if (-not [string]::IsNullOrWhiteSpace($Document.Slug)) {
        return $Document.Slug
    }

    if (-not [string]::IsNullOrWhiteSpace($Document.BaseName)) {
        $normalizedText = $Document.BaseName.ToLowerInvariant()
        $normalizedText = [System.Text.RegularExpressions.Regex]::Replace($normalizedText, '[^a-z0-9]+', '-')
        return $normalizedText.Trim('-')
    }

    return ''
}

function Get-HydePostNeighbors {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document,

        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    # Jekyll-style `page.previous` and `page.next` semantics using site.posts ordering (newest first).
    $neighbors = @{ previous = $null; next = $null }
    if ($Document.CollectionName -ne 'posts') {
        return $neighbors
    }

    $posts = @($Context.Site.posts)
    for ($i = 0; $i -lt $posts.Count; $i++) {
        $post = $posts[$i]
        if ($post -and $post.SourcePath -ieq $Document.SourcePath) {
            if ($i -lt ($posts.Count - 1)) {
                $neighbors.previous = $posts[$i + 1]
            }

            if ($i -gt 0) {
                $neighbors.next = $posts[$i - 1]
            }

            break
        }
    }

    return $neighbors
}

function New-HydePageVariables {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document,

        [Parameter(Mandatory = $false)]
        [HydeBuildContext]$Context
    )

    # Build the standard `page` variable mapping used by Liquid templates.
    $page = @{}
    foreach ($key in $Document.FrontMatter.Keys) {
        $page[$key] = $Document.FrontMatter[$key]
    }

    if (-not [string]::IsNullOrWhiteSpace($Document.Title)) {
        $page['title'] = $Document.Title
    }

    $page['content'] = $Document.RenderedContent
    $page['collection'] = $Document.CollectionName
    $page['url'] = $Document.Url
    $page['path'] = $Document.RelativePath
    $page['name'] = $Document.Name
    $page['basename'] = $Document.BaseName
    $page['extname'] = $Document.Extension
    $page['slug'] = Get-HydeDocumentVariableSlug -Document $Document
    $page['tags'] = @($Document.Tags)
    $page['categories'] = @($Document.Categories)
    $page['draft'] = $Document.IsDraft

    if ($Document.PostDate -ne [datetime]::MinValue) {
        $page['date'] = $Document.PostDate
    }

    # Add Jekyll-like relative post navigation when available.
    if ($Context -and $Document.CollectionName -eq 'posts') {
        $neighbors = Get-HydePostNeighbors -Document $Document -Context $Context
        $page['previous'] = $neighbors.previous
        $page['next'] = $neighbors.next
    }

    # Excerpt is a commonly referenced Jekyll front matter key; preserve if set.
    if ($Document.FrontMatter.ContainsKey('excerpt')) {
        $page['excerpt'] = $Document.FrontMatter['excerpt']
    }

    return $page
}
