Describe 'Hyde seo-tag plugin' {
    BeforeAll {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $moduleManifestPath = Join-Path -Path $projectRoot -ChildPath 'src\Hyde.psd1'
        Import-Module $moduleManifestPath -Force

        function New-TestSiteDirectory {
            param(
                [Parameter(Mandatory = $true)]
                [string]$Name
            )

            $path = Join-Path -Path $TestDrive -ChildPath $Name
            [void](New-Item -Path $path -ItemType Directory -Force)
            return $path
        }
    }

    It 'loads the built-in seo plugin and renders title description canonical and social tags from site and page metadata' {
        $siteRoot = New-TestSiteDirectory -Name 'plugin-seo-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'plugin-seo-output'

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
tagline: Helpful Tagline
description: Site Description
url: https://example.com
baseurl: /docs
locale: en_GB
twitter:
  username: hydesite
  card: summary_large_image
facebook:
  app_id: fb-app-1
  publisher: https://facebook.com/hyde
  admins:
    - admin-1
logo: /assets/logo.png
social:
  name: Hyde Project
  links:
    - https://twitter.com/hydesite
    - https://github.com/example/hyde
google_site_verification: google-token
webmaster_verifications:
  bing: bing-token
  yandex: yandex-token
plugins:
  - jekyll-seo-tag
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.html') -Encoding UTF8 -Value @'
---
title: Home
description: Page Description
image: /assets/page-pic.jpg
---
{% seo %}
'@

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw

        $indexOutput | Should -Match '<title>Home \| Test Site</title>'
        $indexOutput | Should -Match '<meta name="description" content="Page Description">'
        $indexOutput | Should -Match '<link rel="canonical" href="https://example.com/docs/index\.html">'
        $indexOutput | Should -Match '<meta property="og:locale" content="en_GB">'
        $indexOutput | Should -Match '<meta property="og:image" content="https://example.com/docs/assets/page-pic\.jpg">'
        $indexOutput | Should -Match '<meta name="twitter:card" content="summary_large_image">'
        $indexOutput | Should -Match '<meta name="twitter:site" content="@hydesite">'
        $indexOutput | Should -Match '<meta property="fb:app_id" content="fb-app-1">'
        $indexOutput | Should -Match '<meta property="article:publisher" content="https://facebook\.com/hyde">'
        $indexOutput | Should -Match '<meta name="google-site-verification" content="google-token">'
        $indexOutput | Should -Match '<meta name="msvalidate\.01" content="bing-token">'
        $indexOutput | Should -Match '<meta name="yandex-verification" content="yandex-token">'
        $indexOutput | Should -Match '"@type":"Organization"'
        $indexOutput | Should -Match '"sameAs":\["https://twitter\.com/hydesite","https://github\.com/example/hyde"\]'
        $indexOutput | Should -Match '"logo":"https://example\.com/docs/assets/logo\.png"'
        $context.LoadedPlugins.Name | Should -Contain 'seo-tag'
    }

    It 'uses site title and tagline when page title is absent' {
        $siteRoot = New-TestSiteDirectory -Name 'plugin-seo-tagline-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'plugin-seo-tagline-output'

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
tagline: Helpful Tagline
description: Site Description
plugins:
  - jekyll-seo-tag
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.html') -Encoding UTF8 -Value '{% seo %}'

        Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development | Out-Null
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw

        $indexOutput | Should -Match '<title>Test Site \| Helpful Tagline</title>'
        $indexOutput | Should -Match '<meta name="description" content="Site Description">'
    }

    It 'uses page-level locale and author in preference to site-level values' {
        $siteRoot = New-TestSiteDirectory -Name 'plugin-seo-page-override-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'plugin-seo-page-override-output'

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
url: https://example.com
author:
  name: Site Author
locale: en_US
plugins:
  - jekyll-seo-tag
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'about.html') -Encoding UTF8 -Value @'
---
title: About
locale: fr_FR
author:
  name: Page Author
---
{% seo %}
'@

        Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development | Out-Null
        $pageOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'about.html') -Raw

        $pageOutput | Should -Match '<meta name="author" content="Page Author">'
        $pageOutput | Should -Match '<meta property="og:locale" content="fr_FR">'
        $pageOutput | Should -Match '"author":\{"@type":"Person","name":"Page Author"\}'
    }

    It 'uses page image and article type for posts' {
        $siteRoot = New-TestSiteDirectory -Name 'plugin-seo-post-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'plugin-seo-post-output'
        $postsDirectory = Join-Path -Path $siteRoot -ChildPath '_posts'

        [void](New-Item -Path $postsDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
url: https://example.com
plugins:
  - jekyll-seo-tag
'@

        Set-Content -LiteralPath (Join-Path -Path $postsDirectory -ChildPath '2026-03-30-seo-post.md') -Encoding UTF8 -Value @'
---
title: SEO Post
description: Post Description
image: /assets/post-image.png
---
{% seo %}
'@

        Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development | Out-Null
        $postOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath '2026\03\30\seo-post.html') -Raw

        $postOutput | Should -Match '<meta property="og:type" content="article">'
        $postOutput | Should -Match '<meta property="og:image" content="https://example.com/assets/post-image\.png">'
        $postOutput | Should -Match '<meta name="twitter:image" content="https://example.com/assets/post-image\.png">'
        $postOutput | Should -Match '"@type":"Article"'
    }
}
