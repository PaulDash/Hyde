param($Context)

# This built-in plugin provides a compact Hyde equivalent of the Jekyll SEO Tag plugin.
$null = $Context
@{
    Name = 'seo-tag'
    Liquid = @{
        Tags = @{
            seo = {
                param($Invocation)

                function Get-SeoValue {
                    param(
                        $InputObject,
                        [string]$Name
                    )

                    if ($null -eq $InputObject) {
                        return $null
                    }

                    if ($InputObject -is [hashtable] -and $InputObject.ContainsKey($Name)) {
                        return $InputObject[$Name]
                    }

                    $property = $InputObject.PSObject.Properties[$Name]
                    if ($null -ne $property) {
                        return $property.Value
                    }

                    return $null
                }

                function Get-SeoString {
                    param($Value)

                    if ($null -eq $Value) {
                        return ''
                    }

                    return [string]$Value
                }

                function Get-SeoAuthorName {
                    param($Author)

                    if ($null -eq $Author) {
                        return ''
                    }

                    if ($Author -is [string]) {
                        return $Author
                    }

                    $name = Get-SeoValue -InputObject $Author -Name 'name'
                    if (-not [string]::IsNullOrWhiteSpace([string]$name)) {
                        return [string]$name
                    }

                    return ''
                }

                function Resolve-SeoAbsoluteUrl {
                    param(
                        [string]$Value,
                        [string]$SiteUrl,
                        [string]$BaseUrl = ''
                    )

                    if ([string]::IsNullOrWhiteSpace($Value)) {
                        return ''
                    }

                    if ([System.Uri]::IsWellFormedUriString($Value, [System.UriKind]::Absolute)) {
                        return $Value
                    }

                    $normalizedPath = $Value.Trim()
                    if ([string]::IsNullOrWhiteSpace($SiteUrl)) {
                        return $normalizedPath
                    }

                    $combinedPath = if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
                        $normalizedPath
                    } else {
                        $BaseUrl.TrimEnd('/') + '/' + $normalizedPath.TrimStart('/')
                    }

                    return $SiteUrl.TrimEnd('/') + '/' + $combinedPath.TrimStart('/')
                }

                function Add-SeoMetaTag {
                    param(
                        [System.Collections.ArrayList]$Collection,
                        [string]$Name,
                        [string]$Content,
                        [string]$AttributeName = 'name'
                    )

                    if (-not [string]::IsNullOrWhiteSpace($Content)) {
                        [void]$Collection.Add('<meta ' + $AttributeName + '="' + [System.Net.WebUtility]::HtmlEncode($Name) + '" content="' + [System.Net.WebUtility]::HtmlEncode($Content) + '">')
                    }
                }

                # The SEO tag derives values from page metadata first, then falls back to site metadata.
                $site = & $Invocation.Helpers.ResolveVariable 'site'
                $page = & $Invocation.Helpers.ResolveVariable 'page'

                $siteTitle = Get-SeoString (Get-SeoValue -InputObject $site -Name 'title')
                $siteTagline = Get-SeoString (Get-SeoValue -InputObject $site -Name 'tagline')
                $siteDescription = Get-SeoString (Get-SeoValue -InputObject $site -Name 'description')
                $pageTitle = Get-SeoString (Get-SeoValue -InputObject $page -Name 'title')
                $pageDescription = Get-SeoString (Get-SeoValue -InputObject $page -Name 'description')
                $pageUrl = Get-SeoString (Get-SeoValue -InputObject $page -Name 'url')
                $baseUrl = Get-SeoString (Get-SeoValue -InputObject $site -Name 'baseurl')
                $siteUrl = Get-SeoString (Get-SeoValue -InputObject $site -Name 'url')
                if ([string]::IsNullOrWhiteSpace($siteUrl)) {
                    $github = Get-SeoValue -InputObject $site -Name 'github'
                    $siteUrl = Get-SeoString (Get-SeoValue -InputObject $github -Name 'url')
                }

                $pageImage = Get-SeoString (Get-SeoValue -InputObject $page -Name 'image')
                $siteLogo = Get-SeoString (Get-SeoValue -InputObject $site -Name 'logo')
                $siteTwitter = Get-SeoValue -InputObject $site -Name 'twitter'
                $siteFacebook = Get-SeoValue -InputObject $site -Name 'facebook'
                $siteSocial = Get-SeoValue -InputObject $site -Name 'social'
                $pageAuthor = Get-SeoValue -InputObject $page -Name 'author'
                $siteAuthor = Get-SeoValue -InputObject $site -Name 'author'
                $authorName = Get-SeoAuthorName -Author $(if ($null -ne $pageAuthor) { $pageAuthor } else { $siteAuthor })
                $locale = Get-SeoString (Get-SeoValue -InputObject $page -Name 'locale')
                if ([string]::IsNullOrWhiteSpace($locale)) {
                    $locale = Get-SeoString (Get-SeoValue -InputObject $page -Name 'lang')
                }
                if ([string]::IsNullOrWhiteSpace($locale)) {
                    $locale = Get-SeoString (Get-SeoValue -InputObject $site -Name 'locale')
                }
                if ([string]::IsNullOrWhiteSpace($locale)) {
                    $locale = Get-SeoString (Get-SeoValue -InputObject $site -Name 'lang')
                }
                if ([string]::IsNullOrWhiteSpace($locale)) {
                    $locale = 'en_US'
                }

                $fullTitle = if (-not [string]::IsNullOrWhiteSpace($pageTitle) -and -not [string]::IsNullOrWhiteSpace($siteTitle)) {
                    "$pageTitle | $siteTitle"
                } elseif (-not [string]::IsNullOrWhiteSpace($pageTitle)) {
                    $pageTitle
                } elseif (-not [string]::IsNullOrWhiteSpace($siteTitle) -and -not [string]::IsNullOrWhiteSpace($siteTagline)) {
                    "$siteTitle | $siteTagline"
                } elseif (-not [string]::IsNullOrWhiteSpace($siteTitle) -and -not [string]::IsNullOrWhiteSpace($siteDescription)) {
                    "$siteTitle | $siteDescription"
                } else {
                    $siteTitle
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
                        $baseUrl.TrimEnd('/') + '/' + $pageUrl.TrimStart('/')
                    }

                    $canonicalUrl = if ([string]::IsNullOrWhiteSpace($siteUrl)) {
                        $basePath
                    } else {
                        $siteUrl.TrimEnd('/') + '/' + $basePath.TrimStart('/')
                    }
                }

                $absoluteImageUrl = Resolve-SeoAbsoluteUrl -Value $pageImage -SiteUrl $siteUrl -BaseUrl $baseUrl
                $absoluteLogoUrl = Resolve-SeoAbsoluteUrl -Value $siteLogo -SiteUrl $siteUrl -BaseUrl $baseUrl
                $twitterCard = Get-SeoString (Get-SeoValue -InputObject $siteTwitter -Name 'card')
                if ([string]::IsNullOrWhiteSpace($twitterCard)) {
                    $twitterCard = 'summary'
                }

                $twitterUsername = Get-SeoString (Get-SeoValue -InputObject $siteTwitter -Name 'username')
                if (-not [string]::IsNullOrWhiteSpace($twitterUsername) -and -not $twitterUsername.StartsWith('@')) {
                    $twitterUsername = '@' + $twitterUsername.TrimStart('@')
                }

                $html = New-Object System.Collections.ArrayList
                if (-not [string]::IsNullOrWhiteSpace($fullTitle)) {
                    [void]$html.Add("<title>$([System.Net.WebUtility]::HtmlEncode($fullTitle))</title>")
                }

                Add-SeoMetaTag -Collection $html -Name 'description' -Content $description

                if (-not [string]::IsNullOrWhiteSpace($canonicalUrl)) {
                    [void]$html.Add('<link rel="canonical" href="' + [System.Net.WebUtility]::HtmlEncode($canonicalUrl) + '">')
                }

                Add-SeoMetaTag -Collection $html -Name 'author' -Content $authorName
                Add-SeoMetaTag -Collection $html -Name 'google-site-verification' -Content (Get-SeoString (Get-SeoValue -InputObject $site -Name 'google_site_verification'))

                $webmasterVerifications = Get-SeoValue -InputObject $site -Name 'webmaster_verifications'
                Add-SeoMetaTag -Collection $html -Name 'google-site-verification' -Content (Get-SeoString (Get-SeoValue -InputObject $webmasterVerifications -Name 'google'))
                Add-SeoMetaTag -Collection $html -Name 'msvalidate.01' -Content (Get-SeoString (Get-SeoValue -InputObject $webmasterVerifications -Name 'bing'))
                Add-SeoMetaTag -Collection $html -Name 'alexaVerifyID' -Content (Get-SeoString (Get-SeoValue -InputObject $webmasterVerifications -Name 'alexa'))
                Add-SeoMetaTag -Collection $html -Name 'yandex-verification' -Content (Get-SeoString (Get-SeoValue -InputObject $webmasterVerifications -Name 'yandex'))
                Add-SeoMetaTag -Collection $html -Name 'baidu-site-verification' -Content (Get-SeoString (Get-SeoValue -InputObject $webmasterVerifications -Name 'baidu'))
                Add-SeoMetaTag -Collection $html -Name 'facebook-domain-verification' -Content (Get-SeoString (Get-SeoValue -InputObject $webmasterVerifications -Name 'facebook'))

                # JSON-LD: site and page metadata
                $jsonLdGraph = New-Object System.Collections.ArrayList

                if (-not [string]::IsNullOrWhiteSpace($siteUrl)) {
                    [void]$jsonLdGraph.Add(@{
                        "@type" = 'WebSite'
                        "url" = $siteUrl
                        "name" = $siteTitle
                        "description" = $siteDescription
                    })
                }

                $organizationLinks = Get-SeoValue -InputObject $siteSocial -Name 'links'
                if ($organizationLinks -is [System.Collections.IEnumerable] -and $organizationLinks -isnot [string]) {
                    $organizationLinks = @($organizationLinks)
                } else {
                    $organizationLinks = @()
                }

                if (-not [string]::IsNullOrWhiteSpace($siteTitle) -and (
                        -not [string]::IsNullOrWhiteSpace($absoluteLogoUrl) -or
                        $organizationLinks.Count -gt 0 -or
                        -not [string]::IsNullOrWhiteSpace((Get-SeoString (Get-SeoValue -InputObject $siteSocial -Name 'name')))
                    )) {
                    $organization = @{
                        "@type" = 'Organization'
                        "name" = if (-not [string]::IsNullOrWhiteSpace((Get-SeoString (Get-SeoValue -InputObject $siteSocial -Name 'name')))) { Get-SeoString (Get-SeoValue -InputObject $siteSocial -Name 'name') } else { $siteTitle }
                    }

                    if (-not [string]::IsNullOrWhiteSpace($siteUrl)) {
                        $organization['url'] = $siteUrl
                    }

                    if (-not [string]::IsNullOrWhiteSpace($absoluteLogoUrl)) {
                        $organization['logo'] = $absoluteLogoUrl
                    }

                    if ($organizationLinks.Count -gt 0) {
                        $organization['sameAs'] = $organizationLinks
                    }

                    [void]$jsonLdGraph.Add($organization)
                }

                if (-not [string]::IsNullOrWhiteSpace($canonicalUrl)) {
                    $webPage = @{
                        "@type" = if ((Get-SeoString (Get-SeoValue -InputObject $page -Name 'collection')) -eq 'posts') { 'Article' } else { 'WebPage' }
                        "url" = $canonicalUrl
                        "name" = $fullTitle
                        "description" = $description
                        "inLanguage" = $locale
                    }

                    if (-not [string]::IsNullOrWhiteSpace($absoluteImageUrl)) {
                        $webPage['image'] = $absoluteImageUrl
                    }

                    if (-not [string]::IsNullOrWhiteSpace($authorName)) {
                        $webPage['author'] = @{
                            "@type" = 'Person'
                            "name" = $authorName
                        }
                    }

                    [void]$jsonLdGraph.Add($webPage)
                }

                if ($jsonLdGraph.Count -gt 0) {
                    $jsonLdPayload = @{
                        "@context" = 'https://schema.org'
                        "@graph" = @($jsonLdGraph)
                    }

                    $jsonLdString = $jsonLdPayload | ConvertTo-Json -Depth 8 -Compress
                    [void]$html.Add('<script type="application/ld+json">' + $jsonLdString + '</script>')
                }

                # Open Graph metadata
                $ogTitle = $fullTitle
                $ogDescription = $description
                $ogUrl = if (-not [string]::IsNullOrWhiteSpace($canonicalUrl)) { $canonicalUrl } else { '' }

                Add-SeoMetaTag -Collection $html -Name 'og:title' -Content $ogTitle -AttributeName 'property'
                Add-SeoMetaTag -Collection $html -Name 'og:description' -Content $ogDescription -AttributeName 'property'
                Add-SeoMetaTag -Collection $html -Name 'og:site_name' -Content $siteTitle -AttributeName 'property'
                Add-SeoMetaTag -Collection $html -Name 'og:url' -Content $ogUrl -AttributeName 'property'
                Add-SeoMetaTag -Collection $html -Name 'og:locale' -Content $locale -AttributeName 'property'
                Add-SeoMetaTag -Collection $html -Name 'og:image' -Content $absoluteImageUrl -AttributeName 'property'
                [void]$html.Add('<meta property="og:type" content="' + $(if ((Get-SeoString (Get-SeoValue -InputObject $page -Name 'collection')) -eq 'posts') { 'article' } else { 'website' }) + '">')

                # Twitter Summary Card metadata
                Add-SeoMetaTag -Collection $html -Name 'twitter:card' -Content $twitterCard
                Add-SeoMetaTag -Collection $html -Name 'twitter:title' -Content $ogTitle
                Add-SeoMetaTag -Collection $html -Name 'twitter:description' -Content $ogDescription
                Add-SeoMetaTag -Collection $html -Name 'twitter:url' -Content $ogUrl
                Add-SeoMetaTag -Collection $html -Name 'twitter:site' -Content $twitterUsername
                Add-SeoMetaTag -Collection $html -Name 'twitter:image' -Content $absoluteImageUrl

                # Facebook insights metadata
                Add-SeoMetaTag -Collection $html -Name 'fb:app_id' -Content (Get-SeoString (Get-SeoValue -InputObject $siteFacebook -Name 'app_id')) -AttributeName 'property'
                Add-SeoMetaTag -Collection $html -Name 'article:publisher' -Content (Get-SeoString (Get-SeoValue -InputObject $siteFacebook -Name 'publisher')) -AttributeName 'property'

                $facebookAdmins = Get-SeoValue -InputObject $siteFacebook -Name 'admins'
                if ($facebookAdmins -is [System.Collections.IEnumerable] -and $facebookAdmins -isnot [string]) {
                    foreach ($facebookAdmin in @($facebookAdmins)) {
                        Add-SeoMetaTag -Collection $html -Name 'fb:admins' -Content (Get-SeoString $facebookAdmin) -AttributeName 'property'
                    }
                } else {
                    Add-SeoMetaTag -Collection $html -Name 'fb:admins' -Content (Get-SeoString $facebookAdmins) -AttributeName 'property'
                }

                return ($html -join [Environment]::NewLine)
            }
        }
    }
}
