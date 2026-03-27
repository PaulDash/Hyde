param($Context)

# This built-in plugin provides a small Hyde equivalent of the Jekyll SEO Tag plugin.
@{
    Name = 'seo-tag'
    Liquid = @{
        Tags = @{
            seo = {
                param($Invocation)

                # The SEO tag derives values from page metadata first, then falls back to site metadata.
                $site = & $Invocation.Helpers.ResolveVariable 'site'
                $page = & $Invocation.Helpers.ResolveVariable 'page'

                $siteTitle = if ($null -ne $site -and $site.ContainsKey('title')) { [string]$site.title } else { '' }
                $siteDescription = if ($null -ne $site -and $site.ContainsKey('description')) { [string]$site.description } else { '' }
                $pageTitle = if ($null -ne $page -and $page.ContainsKey('title')) { [string]$page.title } else { '' }
                $pageDescription = if ($null -ne $page -and $page.ContainsKey('description')) { [string]$page.description } else { '' }
                $pageUrl = if ($null -ne $page -and $page.ContainsKey('url')) { [string]$page.url } else { '' }
                $siteUrl = if ($null -ne $site -and $site.ContainsKey('url')) { [string]$site.url } else { '' }
                $baseUrl = if ($null -ne $site -and $site.ContainsKey('baseurl')) { [string]$site.baseurl } else { '' }

                $fullTitle = if ([string]::IsNullOrWhiteSpace($pageTitle)) {
                    $siteTitle
                } elseif ([string]::IsNullOrWhiteSpace($siteTitle)) {
                    $pageTitle
                } else {
                    "$pageTitle | $siteTitle"
                }

                $description = if (-not [string]::IsNullOrWhiteSpace($pageDescription)) {
                    $pageDescription
                } else {
                    $siteDescription
                }

                $canonicalUrl = ''
                if (-not [string]::IsNullOrWhiteSpace($pageUrl)) {
                    $basePath = if ([string]::IsNullOrWhiteSpace($baseUrl)) {
                        $pageUrl
                    } else {
                        ($baseUrl.TrimEnd('/') + '/' + $pageUrl.TrimStart('/'))
                    }

                    $canonicalUrl = if ([string]::IsNullOrWhiteSpace($siteUrl)) {
                        $basePath
                    } else {
                        ($siteUrl.TrimEnd('/') + '/' + $basePath.TrimStart('/'))
                    }
                }

                $html = New-Object System.Collections.ArrayList
                if (-not [string]::IsNullOrWhiteSpace($fullTitle)) {
                    [void]$html.Add("<title>$([System.Net.WebUtility]::HtmlEncode($fullTitle))</title>")
                }

                if (-not [string]::IsNullOrWhiteSpace($description)) {
                    [void]$html.Add('<meta name="description" content="' + [System.Net.WebUtility]::HtmlEncode($description) + '">')
                }

                if (-not [string]::IsNullOrWhiteSpace($canonicalUrl)) {
                    [void]$html.Add('<link rel="canonical" href="' + [System.Net.WebUtility]::HtmlEncode($canonicalUrl) + '">')
                }

                # TODO: JSON-LD Site and post metadata for richer indexing
                # TODO: Open Graph title, description, site title, and URL (for Facebook, LinkedIn, etc.)
                # TODO: Twitter Summary Card metadata

                return ($html -join [Environment]::NewLine)
            }
        }
    }
}
