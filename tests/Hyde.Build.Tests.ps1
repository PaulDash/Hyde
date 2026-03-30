Describe 'Hyde build pipeline' {
    BeforeAll {
        # Import the module once so each test can call the public entry points directly.
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

    It 'builds markdown and html pages with front matter and copies static files' {
        # Create a minimal site fixture entirely under TestDrive.
        $siteRoot = Join-Path -Path $TestDrive -ChildPath 'site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'output'
        $assetsDirectory = Join-Path -Path $siteRoot -ChildPath 'assets'

        [void](New-Item -Path $siteRoot -ItemType Directory -Force)
        [void](New-Item -Path $assetsDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
exclude:
  - ignored.txt
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
title: Home
---
# Hello

This is **Hyde**.

- one
- two
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'about.html') -Encoding UTF8 -Value @'
---
title: About
---
<main><p>About Hyde</p></main>
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'ignored.txt') -Encoding UTF8 -Value 'ignore me'
        Set-Content -LiteralPath (Join-Path -Path $assetsDirectory -ChildPath 'site.css') -Encoding UTF8 -Value 'body { color: black; }'

        # Run the real build command so the test exercises the full public pipeline.
        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development

        # Assert both on-disk output and the in-memory context the build returns.
        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'about.html') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'assets\site.css') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'ignored.txt') | Should -BeFalse

        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw
        $aboutOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'about.html') -Raw

        $indexOutput | Should -Match '<h1>Hello</h1>'
        $indexOutput | Should -Match '<p>This is <strong>Hyde</strong>\.</p>'
        $indexOutput | Should -Match '<ul><li>one</li><li>two</li></ul>'
        $aboutOutput | Should -Match '<main><p>About Hyde</p></main>'

        $context.Documents.Count | Should -Be 2
        $context.Documents[0].FrontMatter.title | Should -Not -BeNullOrEmpty
        $context.StaticFiles.Count | Should -Be 1
    }

    It 'does not write pages marked published false' {
        $siteRoot = New-TestSiteDirectory -Name 'site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'output'

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
title: Home
---
# Hello
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'draft.md') -Encoding UTF8 -Value @'
---
title: Draft
published: false
---
# Hidden
'@

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development
        $draftDocument = $context.Documents | Where-Object { $_.BaseName -eq 'draft' }

        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'draft.html') | Should -BeFalse
        $draftDocument.Published | Should -BeFalse
    }

    It 'emits verbose output for build stages' {
        $siteRoot = New-TestSiteDirectory -Name 'verbose-build-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'verbose-build-output'
        $assetsDirectory = Join-Path -Path $siteRoot -ChildPath 'assets'

        [void](New-Item -Path $assetsDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
title: Home
---
# Hello
'@

        Set-Content -LiteralPath (Join-Path -Path $assetsDirectory -ChildPath 'site.css') -Encoding UTF8 -Value 'body { color: black; }'

        # Capture the verbose stream to verify that Hyde reports the main build phases.
        $verboseRecords = @(Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development -Verbose 4>&1)
        $verboseText = $verboseRecords | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message }

        $verboseText | Should -Contain "Building site from '$siteRoot' to '$destinationRoot'."
        $verboseText | Should -Contain "Rendering document 1 of 1: 'index.md'."
        $verboseText | Should -Contain "Copying static file 1 of 1: 'assets/site.css' to 'assets/site.css'."
    }

    It 'supports WhatIf without writing generated output' {
        $siteRoot = New-TestSiteDirectory -Name 'build-whatif-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'build-whatif-output'

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
title: Home
---
# Hello
'@

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development -WhatIf

        $context.Documents.Count | Should -Be 1
        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') | Should -BeFalse
    }

    It 'renders Liquid in document content by default' {
        $siteRoot = New-TestSiteDirectory -Name 'content-liquid-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'content-liquid-output'

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
title: Home
---
# {{ page.title | upcase }}
'@

        Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development | Out-Null
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw

        $indexOutput | Should -Match '<h1>HOME</h1>'
    }

    It 'skips Liquid rendering when render_with_liquid is false' {
        $siteRoot = New-TestSiteDirectory -Name 'no-content-liquid-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'no-content-liquid-output'
        $layoutsDirectory = Join-Path -Path $siteRoot -ChildPath '_layouts'

        [void](New-Item -Path $layoutsDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        Set-Content -LiteralPath (Join-Path -Path $layoutsDirectory -ChildPath 'default.html') -Encoding UTF8 -Value @'
<main>{{ content }}</main>
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
title: Home
layout: default
render_with_liquid: false
---
# {{ page.title | upcase }}
'@

        Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development | Out-Null
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw

        $indexOutput | Should -Match '<main><h1>\{\{ page.title \| upcase \}\}</h1></main>'
    }

    It 'applies a single-level layout using Liquid objects tags and filters' {
        $siteRoot = New-TestSiteDirectory -Name 'layout-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'layout-output'
        $layoutsDirectory = Join-Path -Path $siteRoot -ChildPath '_layouts'

        [void](New-Item -Path $layoutsDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        Set-Content -LiteralPath (Join-Path -Path $layoutsDirectory -ChildPath 'default.html') -Encoding UTF8 -Value @'
---
layout_title: Wrapper
---
<html>
<head><title>{{ page.title | upcase }}</title></head>
<body>
{% if site.title %}<header>{{ site.title }}</header>{% endif %}
<main>{{ content }}</main>
<footer>{{ layout.layout_title }}</footer>
</body>
</html>
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
title: Home
layout: default
---
# Hello
'@

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw

        $indexOutput | Should -Match '<title>HOME</title>'
        $indexOutput | Should -Match '<header>Test Site</header>'
        $indexOutput | Should -Match '<main><h1>Hello</h1></main>'
        $indexOutput | Should -Match '<footer>Wrapper</footer>'
        $context.Documents.Count | Should -Be 1
    }

    It 'applies parent layouts by using the pre-parsed layout inheritance chain' {
        $siteRoot = New-TestSiteDirectory -Name 'layout-inheritance-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'layout-inheritance-output'
        $layoutsDirectory = Join-Path -Path $siteRoot -ChildPath '_layouts'

        [void](New-Item -Path $layoutsDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        Set-Content -LiteralPath (Join-Path -Path $layoutsDirectory -ChildPath 'base.html') -Encoding UTF8 -Value @'
<html><body><div class="base">{{ content }}</div></body></html>
'@

        Set-Content -LiteralPath (Join-Path -Path $layoutsDirectory -ChildPath 'notes.html') -Encoding UTF8 -Value @'
---
layout: base
section_name: Notes
---
<section><h1>{{ layout.section_name }}</h1>{{ content }}</section>
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
title: Home
layout: notes
---
# Hello
'@

        Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development | Out-Null
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw

        $indexOutput | Should -Match '<div class="base"><section><h1>Notes</h1><h1>Hello</h1></section>\s*</div>'
    }

    It 'writes pages to a front matter permalink and exposes the permalink URL' {
        $siteRoot = New-TestSiteDirectory -Name 'page-permalink-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'page-permalink-output'

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
title: Home
permalink: /welcome/
---
{{ page.url }}
'@

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development
        $document = $context.Documents | Where-Object { $_.RelativePath -eq 'index.md' }
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'welcome\index.html') -Raw

        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'welcome\index.html') | Should -BeTrue
        $document.Url | Should -Be '/welcome/'
        $indexOutput | Should -Match '<p>/welcome/</p>'
    }

    It 'applies the global permalink pattern to pages while ignoring unavailable placeholders' {
        $siteRoot = New-TestSiteDirectory -Name 'global-page-permalink-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'global-page-permalink-output'

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
permalink: /:categories/:year/:month/:day/:title:output_ext
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'about-me.md') -Encoding UTF8 -Value @'
---
title: About Me
---
{{ page.url }}
'@

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development
        $document = $context.Documents | Where-Object { $_.RelativePath -eq 'about-me.md' }
        $pageOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'about-me.html') -Raw

        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'about-me.html') | Should -BeTrue
        $document.Url | Should -Be '/about-me.html'
        $pageOutput | Should -Match '<p>/about-me\.html</p>'
    }

    It 'ignores page permalink values supplied through front matter defaults' {
        $siteRoot = New-TestSiteDirectory -Name 'page-default-permalink-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'page-default-permalink-output'

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
defaults:
  - scope:
      path: ""
      type: pages
    values:
      permalink: /ignored-by-defaults/
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
title: Home
---
{{ page.url }}
'@

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development
        $document = $context.Documents | Where-Object { $_.RelativePath -eq 'index.md' }
        $pageOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw

        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'ignored-by-defaults\index.html') | Should -BeFalse
        $document.Url | Should -Be '/index.html'
        $pageOutput | Should -Match '<p>/index\.html</p>'
    }

    It 'can populate document titles from the first markdown heading through the titles-from-headings plugin' {
        $siteRoot = New-TestSiteDirectory -Name 'titles-from-headings-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'titles-from-headings-output'
        $layoutsDirectory = Join-Path -Path $siteRoot -ChildPath '_layouts'

        [void](New-Item -Path $layoutsDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
plugins:
  - titles-from-headings
'@

        Set-Content -LiteralPath (Join-Path -Path $layoutsDirectory -ChildPath 'default.html') -Encoding UTF8 -Value @'
<html>
<head><title>{{ page.title }}</title></head>
<body>{{ content }}</body>
</html>
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
layout: default
---
# Plugin Title

Body text.
'@

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development
        $document = $context.Documents | Where-Object { $_.RelativePath -eq 'index.md' }
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw

        $document.Title | Should -Be 'Plugin Title'
        $document.FrontMatter.title | Should -Be 'Plugin Title'
        $indexOutput | Should -Match '<title>Plugin Title</title>'
    }

    It 'discovers configured collections and writes output when the collection enables output' {
        $siteRoot = New-TestSiteDirectory -Name 'collections-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'collections-output'
        $collectionDirectory = Join-Path -Path $siteRoot -ChildPath '_staff'

        [void](New-Item -Path $collectionDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
collections:
  staff:
    output: true
'@

        Set-Content -LiteralPath (Join-Path -Path $collectionDirectory -ChildPath 'jane.md') -Encoding UTF8 -Value @'
---
title: Jane
---
# Jane
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.html') -Encoding UTF8 -Value @'
Staff count: {{ site.staff.size }} / {{ site.collections.staff.docs.size }}
'@

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development
        $collectionDocument = $context.Documents | Where-Object { $_.CollectionName -eq 'staff' }
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw

        $collectionDocument.Kind | Should -Be 'CollectionDocument'
        $collectionDocument.WriteOutput | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'jane.html') | Should -BeTrue
        $context.Site.collections.staff.docs.Count | Should -Be 1
        $context.Site.staff.Count | Should -Be 1
        $indexOutput | Should -Match 'Staff count: 1 / 1'
    }

    It 'does not write collection documents when the collection output setting is false' {
        $siteRoot = New-TestSiteDirectory -Name 'collections-no-output-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'collections-no-output-output'
        $collectionDirectory = Join-Path -Path $siteRoot -ChildPath '_recipes'

        [void](New-Item -Path $collectionDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
collections:
  recipes:
    output: false
'@

        Set-Content -LiteralPath (Join-Path -Path $collectionDirectory -ChildPath 'toast.md') -Encoding UTF8 -Value @'
---
title: Toast
---
# Toast
'@

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development
        $collectionDocument = $context.Documents | Where-Object { $_.CollectionName -eq 'recipes' }

        $collectionDocument.WriteOutput | Should -BeFalse
        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'recipes\toast.html') | Should -BeFalse
        $context.Site.collections.recipes.docs.Count | Should -Be 1
        $context.Site.recipes.Count | Should -Be 1
    }

    It 'applies exclude rules to collection documents including source-prefixed paths' {
        $siteContainer = New-TestSiteDirectory -Name 'collections-exclude-site'
        $siteRoot = Join-Path -Path $siteContainer -ChildPath 'src'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'collections-exclude-output'
        $collectionDirectory = Join-Path -Path $siteRoot -ChildPath '_notes'

        [void](New-Item -Path $siteRoot -ItemType Directory -Force)
        [void](New-Item -Path $collectionDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
exclude:
  - src/_notes/README.md
collections:
  notes:
    output: true
'@

        Set-Content -LiteralPath (Join-Path -Path $collectionDirectory -ChildPath 'README.md') -Encoding UTF8 -Value @'
---
---
# Internal Notes
'@

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development

        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'notes\\README.html') | Should -BeFalse
        ($context.Documents | Where-Object { $_.RelativePath -eq '_notes/README.md' }).Count | Should -Be 0
        $context.Site.collections.notes.docs.Count | Should -Be 0
        $context.Site.notes.Count | Should -Be 0
    }

    It 'exposes prepared collection titles to Liquid loops before the collection documents are rendered' {
        $siteRoot = New-TestSiteDirectory -Name 'collections-title-loop-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'collections-title-loop-output'
        $collectionDirectory = Join-Path -Path $siteRoot -ChildPath '_notes'

        [void](New-Item -Path $collectionDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
plugins:
  - titles-from-headings
collections:
  notes:
    output: true
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'notes-index.md') -Encoding UTF8 -Value @'
---
title: Notes Index
---
<ul>
{% for note in site.notes %}
  <li><a href="{{ note.url }}">{{ note.title }}</a></li>
{% endfor %}
</ul>
'@

        Set-Content -LiteralPath (Join-Path -Path $collectionDirectory -ChildPath 'welcome.md') -Encoding UTF8 -Value @'
---
---
# Welcome Note
'@

        Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development | Out-Null
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'notes-index.html') -Raw

        $indexOutput | Should -Match '<li><a href="/welcome\.html">Welcome Note</a></li>'
    }

    It 'writes collection documents to a collection permalink that uses the semantic title slug' {
        $siteRoot = New-TestSiteDirectory -Name 'collection-permalink-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'collection-permalink-output'
        $collectionDirectory = Join-Path -Path $siteRoot -ChildPath '_notes'

        [void](New-Item -Path $collectionDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
plugins:
  - titles-from-headings
collections:
  notes:
    output: true
    permalink: /notes/:title/
'@

        Set-Content -LiteralPath (Join-Path -Path $collectionDirectory -ChildPath 'dns-client.md') -Encoding UTF8 -Value @'
---
---
# DNS Client
'@

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development
        $document = $context.Documents | Where-Object { $_.RelativePath -eq '_notes/dns-client.md' }

        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'notes\dns-client\index.html') | Should -BeTrue
        $document.Url | Should -Be '/notes/dns-client/'
        $document.OutputRelativePath | Should -Be 'notes/dns-client/index.html'
    }

    It 'discovers dated posts, sorts site.posts, and applies the default post permalink workflow' {
        $siteRoot = New-TestSiteDirectory -Name 'posts-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'posts-output'
        $postsDirectory = Join-Path -Path $siteRoot -ChildPath '_posts'

        [void](New-Item -Path $postsDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
title: Home
---
{% for post in site.posts %}
- {{ post.title }}|{{ post.url }}
{% endfor %}
'@

        Set-Content -LiteralPath (Join-Path -Path $postsDirectory -ChildPath '2026-03-27-older-post.md') -Encoding UTF8 -Value @'
---
title: Older Post
---
# Older
'@

        Set-Content -LiteralPath (Join-Path -Path $postsDirectory -ChildPath '2026-03-28-newer-post.md') -Encoding UTF8 -Value @'
---
title: Newer Post
---
# Newer
'@

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw
        $postUrls = @($context.Site.posts | ForEach-Object { $_.Url })

        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath '2026\03\28\newer-post.html') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath '2026\03\27\older-post.html') | Should -BeTrue
        $postUrls[0] | Should -Be '/2026/03/28/newer-post.html'
        $postUrls[1] | Should -Be '/2026/03/27/older-post.html'
        $indexOutput | Should -Match 'Newer Post\|/2026/03/28/newer-post\.html'
        $indexOutput | Should -Match 'Older Post\|/2026/03/27/older-post\.html'
    }

    It 'paginates posts for an HTML index page and exposes the Jekyll paginator object' {
        $siteRoot = New-TestSiteDirectory -Name 'paginated-posts-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'paginated-posts-output'
        $postsDirectory = Join-Path -Path $siteRoot -ChildPath '_posts'

        [void](New-Item -Path $postsDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
paginate: 2
paginate_path: /page:num/
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.html') -Encoding UTF8 -Value @'
<section class="page">{{ paginator.page }}/{{ paginator.total_pages }}</section>
<section class="counts">{{ paginator.per_page }}|{{ paginator.total_posts }}</section>
<section class="prev">{% if paginator.previous_page %}{{ paginator.previous_page }}|{{ paginator.previous_page_path }}{% else %}none{% endif %}</section>
<section class="next">{% if paginator.next_page %}{{ paginator.next_page }}|{{ paginator.next_page_path }}{% else %}none{% endif %}</section>
{% for post in paginator.posts %}
<article>{{ post.title }}</article>
{% endfor %}
'@

        foreach ($postNumber in 1..5) {
            $postDate = Get-Date '2026-03-20'
            $postDate = $postDate.AddDays($postNumber)
            Set-Content -LiteralPath (Join-Path -Path $postsDirectory -ChildPath ('{0}-post-{1}.md' -f $postDate.ToString('yyyy-MM-dd'), $postNumber)) -Encoding UTF8 -Value @"
---
title: Post $postNumber
---
# Post $postNumber
"@
        }

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development
        $pageOne = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw
        $pageTwo = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'page2\index.html') -Raw
        $pageThree = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'page3\index.html') -Raw
        $paginatedDocuments = @($context.Documents | Where-Object { $_.RelativePath -eq 'index.html' })

        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'page1\index.html') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'page2\index.html') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'page3\index.html') | Should -BeTrue
        $pageOne | Should -Match '<section class="page">1/3</section>'
        $pageOne | Should -Match '<section class="prev">none</section>'
        $pageOne | Should -Match '<section class="next">2\|/page2/</section>'
        $pageOne | Should -Match '<article>Post 5</article>'
        $pageOne | Should -Match '<article>Post 4</article>'
        $pageTwo | Should -Match '<section class="page">2/3</section>'
        $pageTwo | Should -Match '<section class="prev">1\|/index\.html</section>'
        $pageTwo | Should -Match '<section class="next">3\|/page3/</section>'
        $pageTwo | Should -Match '<article>Post 3</article>'
        $pageTwo | Should -Match '<article>Post 2</article>'
        $pageThree | Should -Match '<section class="page">3/3</section>'
        $pageThree | Should -Match '<section class="prev">2\|/page2/</section>'
        $pageThree | Should -Match '<section class="next">none</section>'
        $pageThree | Should -Match '<article>Post 1</article>'
        $paginatedDocuments.Count | Should -Be 3
        $paginatedDocuments[0].LiquidData.paginator.total_posts | Should -Be 5
        $paginatedDocuments[1].OutputRelativePath | Should -Be 'page2/index.html'
        $paginatedDocuments[2].OutputRelativePath | Should -Be 'page3/index.html'
    }

    It 'paginates a subdirectory index page by nesting paginate_path under that page path' {
        $siteRoot = New-TestSiteDirectory -Name 'subdirectory-paginated-posts-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'subdirectory-paginated-posts-output'
        $postsDirectory = Join-Path -Path $siteRoot -ChildPath '_posts'
        $blogDirectory = Join-Path -Path $siteRoot -ChildPath 'blog'

        [void](New-Item -Path $postsDirectory -ItemType Directory -Force)
        [void](New-Item -Path $blogDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
paginate: 2
paginate_path: /page:num/
'@

        Set-Content -LiteralPath (Join-Path -Path $blogDirectory -ChildPath 'index.html') -Encoding UTF8 -Value @'
{{ paginator.page }}|{{ paginator.previous_page_path }}|{{ paginator.next_page_path }}
{% for post in paginator.posts %}
{{ post.title }}
{% endfor %}
'@

        foreach ($postNumber in 1..3) {
            $postDate = Get-Date '2026-03-10'
            $postDate = $postDate.AddDays($postNumber)
            Set-Content -LiteralPath (Join-Path -Path $postsDirectory -ChildPath ('{0}-entry-{1}.md' -f $postDate.ToString('yyyy-MM-dd'), $postNumber)) -Encoding UTF8 -Value @"
---
title: Entry $postNumber
---
# Entry $postNumber
"@
        }

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development
        $pageOne = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'blog\index.html') -Raw
        $pageTwo = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'blog\page2\index.html') -Raw

        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'blog\page2\index.html') | Should -BeTrue
        ($context.Documents | Where-Object { $_.RelativePath -eq 'blog/index.html' }).Count | Should -Be 2
        $pageOne | Should -Match '1\|\|/blog/page2/'
        $pageTwo | Should -Match '2\|/blog/\|'
    }

    It 'does not paginate markdown index pages because pagination only applies to HTML index files' {
        $siteRoot = New-TestSiteDirectory -Name 'markdown-pagination-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'markdown-pagination-output'
        $postsDirectory = Join-Path -Path $siteRoot -ChildPath '_posts'

        [void](New-Item -Path $postsDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
paginate: 1
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
title: Home
---
{{ paginator.page }}
'@

        foreach ($postNumber in 1..2) {
            Set-Content -LiteralPath (Join-Path -Path $postsDirectory -ChildPath ('2026-03-2{0}-entry-{0}.md' -f $postNumber)) -Encoding UTF8 -Value @"
---
title: Entry $postNumber
---
# Entry $postNumber
"@
        }

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw
        $indexDocument = $context.Documents | Where-Object { $_.RelativePath -eq 'index.md' }

        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'page2\index.html') | Should -BeFalse
        $indexOutput.Trim() | Should -Be ''
        $indexDocument.LiquidData.ContainsKey('paginator') | Should -BeFalse
    }

    It 'supports Jekyll built-in post permalink styles ordinal weekdate and none' {
        $siteRoot = New-TestSiteDirectory -Name 'post-permalink-styles-site'
        $ordinalDestinationRoot = Join-Path -Path $TestDrive -ChildPath 'post-permalink-ordinal-output'
        $weekdateDestinationRoot = Join-Path -Path $TestDrive -ChildPath 'post-permalink-weekdate-output'
        $noneDestinationRoot = Join-Path -Path $TestDrive -ChildPath 'post-permalink-none-output'
        $postsDirectory = Join-Path -Path $siteRoot -ChildPath '_posts'

        [void](New-Item -Path $postsDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $postsDirectory -ChildPath '2026-03-29-style-post.md') -Encoding UTF8 -Value @'
---
title: Style Post
---
# Style Post
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
permalink: ordinal
'@
        $ordinalContext = Publish-StaticSite -Source $siteRoot -Destination $ordinalDestinationRoot -Environment development
        ($ordinalContext.Site.posts[0].Url) | Should -Be '/2026/088/style-post.html'
        Test-Path -LiteralPath (Join-Path -Path $ordinalDestinationRoot -ChildPath '2026\088\style-post.html') | Should -BeTrue

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
permalink: weekdate
'@
        $weekdateContext = Publish-StaticSite -Source $siteRoot -Destination $weekdateDestinationRoot -Environment development
        ($weekdateContext.Site.posts[0].Url) | Should -Be '/2026/W13/Sun/style-post.html'
        Test-Path -LiteralPath (Join-Path -Path $weekdateDestinationRoot -ChildPath '2026\W13\Sun\style-post.html') | Should -BeTrue

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
permalink: none
'@
        $noneContext = Publish-StaticSite -Source $siteRoot -Destination $noneDestinationRoot -Environment development
        ($noneContext.Site.posts[0].Url) | Should -Be '/style-post.html'
        Test-Path -LiteralPath (Join-Path -Path $noneDestinationRoot -ChildPath 'style-post.html') | Should -BeTrue
    }

    It 'supports expanded Jekyll permalink placeholders for posts and collections' {
        $siteRoot = New-TestSiteDirectory -Name 'expanded-permalink-placeholders-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'expanded-permalink-placeholders-output'
        $postsDirectory = Join-Path -Path $siteRoot -ChildPath 'Work 2 Progress\_posts'
        $collectionDirectory = Join-Path -Path $siteRoot -ChildPath '_notes\deep'

        [void](New-Item -Path $postsDirectory -ItemType Directory -Force)
        [void](New-Item -Path $collectionDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
future: true
collections:
  notes:
    output: true
    permalink: /:collection/:path/:basename/:name/:title/:slug:output_ext
'@

        Set-Content -LiteralPath (Join-Path -Path $postsDirectory -ChildPath '2026-03-29-Mixed Case.md') -Encoding UTF8 -Value @'
---
title: Permalink Tokens
slug: Custom Slug
date: 2026-03-29 14:05:06
categories:
  - Alpha Beta
permalink: /:slugified_categories/:short_year/:short_month/:long_month/:day/:i_day/:y_day/:w_year/:week/:w_day/:short_day/:long_day/:hour/:minute/:second/:title/:slug:output_ext
---
# Tokens
'@

        Set-Content -LiteralPath (Join-Path -Path $collectionDirectory -ChildPath 'Deep Note.md') -Encoding UTF8 -Value @'
---
slug: Custom Note
---
# Deep Note
'@

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development
        $postDocument = $context.Site.posts[0]
        $noteDocument = $context.Documents | Where-Object { $_.RelativePath -eq '_notes/deep/Deep Note.md' }

        $postDocument.Url | Should -Be '/work-2-progress/alpha-beta/26/Mar/March/29/29/088/2026/13/7/Sun/Sunday/14/05/06/Custom-Slug/custom-slug.html'
        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'work-2-progress\alpha-beta\26\Mar\March\29\29\088\2026\13\7\Sun\Sunday\14\05\06\Custom-Slug\custom-slug.html') | Should -BeTrue

        $noteDocument.Url | Should -Be '/notes/deep/Deep Note/Deep Note/deep-note/Custom-Note/custom-note.html'
        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'notes\deep\Deep Note\Deep Note\deep-note\Custom-Note\custom-note.html') | Should -BeTrue
    }

    It 'filters future posts unless future is enabled' {
        $siteRoot = New-TestSiteDirectory -Name 'future-posts-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'future-posts-output'
        $postsDirectory = Join-Path -Path $siteRoot -ChildPath '_posts'
        $futureDate = (Get-Date).AddDays(2)

        [void](New-Item -Path $postsDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        Set-Content -LiteralPath (Join-Path -Path $postsDirectory -ChildPath ('{0}-future-post.md' -f $futureDate.ToString('yyyy-MM-dd'))) -Encoding UTF8 -Value @'
---
title: Future Post
---
# Future
'@

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development

        $context.Site.posts.Count | Should -Be 0
        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath ('{0}\future-post.html' -f $futureDate.ToString('yyyy\\MM\\dd'))) | Should -BeFalse
    }

    It 'can publish drafts from _drafts when show_drafts is enabled' {
        $siteRoot = New-TestSiteDirectory -Name 'draft-posts-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'draft-posts-output'
        $draftsDirectory = Join-Path -Path $siteRoot -ChildPath '_drafts'

        [void](New-Item -Path $draftsDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
show_drafts: true
'@

        Set-Content -LiteralPath (Join-Path -Path $draftsDirectory -ChildPath 'preview.md') -Encoding UTF8 -Value @'
---
title: Preview Draft
---
# Preview
'@

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development
        $draftDocument = $context.Documents | Where-Object { $_.RelativePath -eq '_drafts/preview.md' }

        $draftDocument.IsDraft | Should -BeTrue
        $draftDocument.CollectionName | Should -Be 'posts'
        $draftDocument.Published | Should -BeTrue
        $context.Site.posts.Count | Should -Be 1
        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath $draftDocument.OutputRelativePath.Replace('/', '\')) | Should -BeTrue
    }

    It 'matches Jekyll-style tag and category behavior for posts' {
        $siteRoot = New-TestSiteDirectory -Name 'taxonomy-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'taxonomy-output'
        $postsDirectory = Join-Path -Path $siteRoot -ChildPath 'guides\reference\_posts'

        [void](New-Item -Path $postsDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
title: Home
---
Tags: {{ site.tags.powershell.size }}
Categories: {{ site.categories.guides.size }}
{% for post in site.tags.powershell %}{{ post.title }}{% endfor %}
'@

        Set-Content -LiteralPath (Join-Path -Path $postsDirectory -ChildPath '2026-03-28-liquid-taxonomies.md') -Encoding UTF8 -Value @'
---
title: Liquid Taxonomies
tag: powershell
category: reference docs
---
# Taxonomies
'@

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development
        $postDocument = $context.Documents | Where-Object { $_.BaseName -eq '2026-03-28-liquid-taxonomies' }
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw

        $postDocument.Tags.Count | Should -Be 1
        $postDocument.Tags | Should -Contain 'powershell'
        $postDocument.Categories | Should -Contain 'guides'
        $postDocument.Categories | Should -Contain 'reference'
        $postDocument.Categories | Should -Contain 'reference docs'
        $context.Site.tags.powershell.Count | Should -Be 1
        $context.Site.categories.guides.Count | Should -Be 1
        $context.Site.tags.powershell[0].Title | Should -Be 'Liquid Taxonomies'
        $context.Site.categories.reference.Count | Should -Be 1
        $context.Site.tags.Keys | Should -Contain 'powershell'
        $context.Site.categories.Keys | Should -Contain 'guides'
        $indexOutput | Should -Match 'Tags: 1'
        $indexOutput | Should -Match 'Categories: 1'
        $indexOutput | Should -Match 'Liquid Taxonomies'
    }

    It 'renders Jekyll includes from the includes directory' {
        $siteRoot = New-TestSiteDirectory -Name 'include-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'include-output'
        $includesDirectory = Join-Path -Path $siteRoot -ChildPath '_includes'

        [void](New-Item -Path $includesDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        Set-Content -LiteralPath (Join-Path -Path $includesDirectory -ChildPath 'notice.html') -Encoding UTF8 -Value @'
<aside>{{ include.message }} / {{ page.title }}</aside>
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
title: Home
---
{% include notice.html message="Hello" %}
'@

        Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development | Out-Null
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw

        $indexOutput | Should -Match '<aside>Hello / Home</aside>'
    }

    It 'renders include_relative from within a post and keeps it inside the matching _posts tree' {
        $siteRoot = New-TestSiteDirectory -Name 'include-relative-post-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'include-relative-post-output'
        $postsDirectory = Join-Path -Path $siteRoot -ChildPath 'guides\_posts'
        $snippetDirectory = Join-Path -Path $postsDirectory -ChildPath 'snippets'

        [void](New-Item -Path $snippetDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        Set-Content -LiteralPath (Join-Path -Path $postsDirectory -ChildPath '2026-03-29-include-relative.md') -Encoding UTF8 -Value @'
---
title: Include Relative Post
---
Before
{% include_relative snippets/card.md %}
After
'@

        Set-Content -LiteralPath (Join-Path -Path $snippetDirectory -ChildPath 'card.md') -Encoding UTF8 -Value @'
Included snippet
'@

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development
        $postDocument = $context.Documents | Where-Object { $_.RelativePath -eq 'guides/_posts/2026-03-29-include-relative.md' }
        $postOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath $postDocument.OutputRelativePath.Replace('/', '\')) -Raw

        $postOutput | Should -Match '<p>Before Included snippet</p>\s*<p>After</p>'
    }

    It 'rejects include_relative paths that resolve outside the post _posts tree' {
        $siteRoot = New-TestSiteDirectory -Name 'include-relative-escape-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'include-relative-escape-output'
        $postsDirectory = Join-Path -Path $siteRoot -ChildPath '_posts'

        [void](New-Item -Path $postsDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'outside.md') -Encoding UTF8 -Value 'Outside'
        Set-Content -LiteralPath (Join-Path -Path $postsDirectory -ChildPath '2026-03-29-escape.md') -Encoding UTF8 -Value @'
---
title: Escape Post
---
{% include_relative ../outside.md %}
'@

        {
            Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development | Out-Null
        } | Should -Throw -ExpectedMessage '*include_relative*outside the allowed relative include root*'
    }

    It 'rejects include_relative from non-post documents' {
        $siteRoot = New-TestSiteDirectory -Name 'include-relative-page-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'include-relative-page-output'

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'snippet.md') -Encoding UTF8 -Value 'Snippet'
        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
title: Home
---
{% include_relative snippet.md %}
'@

        {
            Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development | Out-Null
        } | Should -Throw -ExpectedMessage '*include_relative*no relative include root is configured*'
    }

    It 'loads the built-in seo plugin and renders title description and canonical tags' {
        $siteRoot = New-TestSiteDirectory -Name 'plugin-seo-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'plugin-seo-output'

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
description: Site Description
url: https://example.com
baseurl: /docs
plugins:
  - jekyll-seo-tag
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.html') -Encoding UTF8 -Value @'
---
title: Home
description: Page Description
---
{% seo %}
'@

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw

        $indexOutput | Should -Match '<title>Home \| Test Site</title>'
        $indexOutput | Should -Match '<meta name="description" content="Page Description">'
        $indexOutput | Should -Match '<link rel="canonical" href="https://example.com/docs/index\.html">'
        $context.LoadedPlugins.Name | Should -Contain 'seo-tag'
    }

    It 'loads a plugin that changes document output paths' {
        $siteRoot = New-TestSiteDirectory -Name 'plugin-output-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'plugin-output-output'
        $pluginsDirectory = Join-Path -Path $siteRoot -ChildPath '_plugins'

        [void](New-Item -Path $pluginsDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        Set-Content -LiteralPath (Join-Path -Path $pluginsDirectory -ChildPath 'lastmod.ps1') -Encoding UTF8 -Value @'
param($Context)

@{
    Name = 'lastmod'
    Hooks = @{
        ResolveDocumentOutputPath = {
            param($CurrentValue, $Invocation)

            $lastWriteTime = (Get-Item -LiteralPath $Invocation.Document.SourcePath).LastWriteTimeUtc
            return ('archive/{0}/{1}' -f $lastWriteTime.ToString('yyyyMMdd'), $CurrentValue)
        }
    }
}
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
title: Home
---
# Hello
'@

        Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development | Out-Null
        $expectedDateSegment = (Get-Item -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md')).LastWriteTimeUtc.ToString('yyyyMMdd')
        $outputPath = Join-Path -Path $destinationRoot -ChildPath "archive\$expectedDateSegment\index.html"

        Test-Path -LiteralPath $outputPath | Should -BeTrue
    }

    It 'translates jekyll-prefixed plugin names to matching Hyde plugin files' {
        $siteRoot = New-TestSiteDirectory -Name 'plugin-translation-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'plugin-translation-output'
        $pluginsDirectory = Join-Path -Path $siteRoot -ChildPath '_plugins'

        [void](New-Item -Path $pluginsDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
plugins:
  - jekyll-lastmod
'@

        Set-Content -LiteralPath (Join-Path -Path $pluginsDirectory -ChildPath 'hyde-lastmod.ps1') -Encoding UTF8 -Value @'
param($Context)

@{
    Name = 'hyde-lastmod'
    Hooks = @{
        ResolveDocumentOutputPath = {
            param($CurrentValue, $Invocation)

            return ('translated/{0}' -f $CurrentValue)
        }
    }
}
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
title: Home
---
# Hello
'@

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development

        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'translated\index.html') | Should -BeTrue
        $context.LoadedPlugins.Name | Should -Contain 'hyde-lastmod'
    }

    It 'renders Liquid for loops against site data' {
        $siteRoot = New-TestSiteDirectory -Name 'for-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'for-output'
        $dataDirectory = Join-Path -Path $siteRoot -ChildPath '_data'

        [void](New-Item -Path $dataDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        Set-Content -LiteralPath (Join-Path -Path $dataDirectory -ChildPath 'nav.yml') -Encoding UTF8 -Value @'
- Home
- About
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
title: Home
---
{% for item in site.data.nav %}
- {{ forloop.index }} {{ item }}
{% endfor %}
'@

        Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development | Out-Null
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw

        $indexOutput | Should -Match '<li>1 Home</li>'
        $indexOutput | Should -Match '<li>2 About</li>'
    }

    It 'loads recursive _data folders into nested site.data paths' {
        $siteRoot = New-TestSiteDirectory -Name 'nested-data-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'nested-data-output'
        $nestedDataDirectory = Join-Path -Path $siteRoot -ChildPath '_data\team'

        [void](New-Item -Path $nestedDataDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        Set-Content -LiteralPath (Join-Path -Path $nestedDataDirectory -ChildPath 'people.yml') -Encoding UTF8 -Value @'
- name: Jane
- name: John
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
title: Home
---
Count: {{ site.data.team.people.size }}
First: {{ site.data.team.people.first.name }}
'@

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw

        $context.Site.data.team.people.Count | Should -Be 2
        $indexOutput | Should -Match 'Count: 2'
        $indexOutput | Should -Match 'First: Jane'
    }

    It 'loads JSON CSV and TSV data files into site.data' {
        $siteRoot = New-TestSiteDirectory -Name 'multi-format-data-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'multi-format-data-output'
        $dataDirectory = Join-Path -Path $siteRoot -ChildPath '_data'

        [void](New-Item -Path $dataDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        Set-Content -LiteralPath (Join-Path -Path $dataDirectory -ChildPath 'profile.json') -Encoding UTF8 -Value @'
{
  "name": "Jane",
  "role": "Writer"
}
'@

        Set-Content -LiteralPath (Join-Path -Path $dataDirectory -ChildPath 'authors.csv') -Encoding UTF8 -Value @'
name,role
Jane,Writer
John,Editor
'@

        Set-Content -LiteralPath (Join-Path -Path $dataDirectory -ChildPath 'topics.tsv') -Encoding UTF8 -Value "name`tlevel`nPowerShell`tAdvanced`nLiquid`tIntermediate`n"

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
title: Home
---
JSON: {{ site.data.profile.name }} / {{ site.data.profile.role }}
CSV: {{ site.data.authors.first.name }} / {{ site.data.authors.last.role }}
TSV: {{ site.data.topics.first.name }} / {{ site.data.topics.last.level }}
'@

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw

        $context.Site.data.profile.name | Should -Be 'Jane'
        $context.Site.data.authors.Count | Should -Be 2
        $context.Site.data.topics.Count | Should -Be 2
        $indexOutput | Should -Match 'JSON: Jane / Writer'
        $indexOutput | Should -Match 'CSV: Jane / Editor'
        $indexOutput | Should -Match 'TSV: PowerShell / Intermediate'
    }

    It 'reports collisions between nested _data namespaces and existing data keys' {
        $siteRoot = New-TestSiteDirectory -Name 'data-collision-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'data-collision-output'
        $nestedDataDirectory = Join-Path -Path $siteRoot -ChildPath '_data\team'

        [void](New-Item -Path $nestedDataDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_data\team.yml') -Encoding UTF8 -Value @'
Jane
'@

        Set-Content -LiteralPath (Join-Path -Path $nestedDataDirectory -ChildPath 'people.yml') -Encoding UTF8 -Value @'
- name: Jane
'@

        {
            Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development | Out-Null
        } | Should -Throw -ExpectedMessage '*conflicts with existing site.data entry*'
    }

    It 'reports invalid YAML in _data files with the failing file path' {
        $siteRoot = New-TestSiteDirectory -Name 'invalid-data-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'invalid-data-output'
        $dataDirectory = Join-Path -Path $siteRoot -ChildPath '_data'

        [void](New-Item -Path $dataDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        Set-Content -LiteralPath (Join-Path -Path $dataDirectory -ChildPath 'broken.yml') -Encoding UTF8 -Value @'
items: [broken
'@

        {
            Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development | Out-Null
        } | Should -Throw -ExpectedMessage '*Could not import data file*broken.yml*'
    }

    It 'reports invalid JSON in _data files with the failing file path' {
        $siteRoot = New-TestSiteDirectory -Name 'invalid-json-data-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'invalid-json-data-output'
        $dataDirectory = Join-Path -Path $siteRoot -ChildPath '_data'

        [void](New-Item -Path $dataDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@

        Set-Content -LiteralPath (Join-Path -Path $dataDirectory -ChildPath 'broken.json') -Encoding UTF8 -Value @'
{ "name": "Jane"
'@

        {
            Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development | Out-Null
        } | Should -Throw -ExpectedMessage '*Could not import data file*broken.json*'
    }

    It 'applies front matter defaults by path and page type while allowing explicit front matter to win' {
        $siteRoot = New-TestSiteDirectory -Name 'defaults-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'defaults-output'
        $layoutsDirectory = Join-Path -Path $siteRoot -ChildPath '_layouts'
        $docsDirectory = Join-Path -Path $siteRoot -ChildPath 'docs'

        [void](New-Item -Path $layoutsDirectory -ItemType Directory -Force)
        [void](New-Item -Path $docsDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
defaults:
  - scope:
      path: ""
      type: "pages"
    values:
      layout: default
      render_with_liquid: false
      title: Generic Title
  - scope:
      path: "docs"
      type: "pages"
    values:
      title: Docs Default
'@

        Set-Content -LiteralPath (Join-Path -Path $layoutsDirectory -ChildPath 'default.html') -Encoding UTF8 -Value @'
<html><head><title>{{ page.title }}</title></head><body>{{ content }}</body></html>
'@

        Set-Content -LiteralPath (Join-Path -Path $docsDirectory -ChildPath 'guide.md') -Encoding UTF8 -Value @'
---
---
# {{ page.title }}
'@

        Set-Content -LiteralPath (Join-Path -Path $docsDirectory -ChildPath 'override.md') -Encoding UTF8 -Value @'
---
title: Custom Title
render_with_liquid: true
---
# {{ page.title }}
'@

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development
        $guideOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'guide.html') -Raw
        $overrideOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'override.html') -Raw
        $guideDocument = $context.Documents | Where-Object { $_.BaseName -eq 'guide' }
        $overrideDocument = $context.Documents | Where-Object { $_.BaseName -eq 'override' }

        $guideOutput | Should -Match '<title>Docs Default</title>'
        $guideOutput | Should -Match '<h1>\{\{ page.title \}\}</h1>'
        $guideDocument.RenderWithLiquid | Should -BeFalse
        $guideDocument.FrontMatter.layout | Should -Be 'default'
        $guideDocument.FrontMatter.title | Should -Be 'Docs Default'

        $overrideOutput | Should -Match '<title>Custom Title</title>'
        $overrideOutput | Should -Match '<h1>Custom Title</h1>'
        $overrideDocument.RenderWithLiquid | Should -BeTrue
        $overrideDocument.FrontMatter.layout | Should -Be 'default'
        $overrideDocument.FrontMatter.title | Should -Be 'Custom Title'
    }

    It 'applies front matter defaults to static file metadata' {
        $siteRoot = New-TestSiteDirectory -Name 'static-defaults-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'static-defaults-output'
        $imageDirectory = Join-Path -Path $siteRoot -ChildPath 'assets\img'

        [void](New-Item -Path $imageDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
defaults:
  - scope:
      path: "assets/img"
    values:
      image: true
'@

        Set-Content -LiteralPath (Join-Path -Path $imageDirectory -ChildPath 'logo.txt') -Encoding UTF8 -Value 'logo'

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development
        $staticFile = $context.StaticFiles | Where-Object { $_.BaseName -eq 'logo' }

        $staticFile.Metadata.image | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'assets\img\logo.txt') | Should -BeTrue
    }

    It 'reports invalid site configuration with context' {
        $siteRoot = New-TestSiteDirectory -Name 'bad-config-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'bad-config-output'
        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
broken: [unterminated
'@

        {
            Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development | Out-Null
        } | Should -Throw -ExpectedMessage '*Build failed while initializing site context*Could not parse configuration file*'
    }

    It 'reports invalid front matter with document context' {
        $siteRoot = New-TestSiteDirectory -Name 'bad-front-matter-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'bad-front-matter-output'
        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@
        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'broken.md') -Encoding UTF8 -Value @'
---
title: [unterminated
---
# Broken
'@

        {
            Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development | Out-Null
        } | Should -Throw -ExpectedMessage '*Build failed while preparing document*broken.md*Could not parse front matter*'
    }

    It 'reports invalid published values with document context' {
        $siteRoot = New-TestSiteDirectory -Name 'bad-published-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'bad-published-output'
        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
'@
        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'broken.md') -Encoding UTF8 -Value @'
---
title: Broken
published: maybe
---
# Broken
'@

        {
            Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development | Out-Null
        } | Should -Throw -ExpectedMessage "*Build failed while preparing document*broken.md*Unsupported value for front matter setting 'published'*"
    }
}
