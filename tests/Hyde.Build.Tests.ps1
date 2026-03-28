Describe 'Hyde build pipeline' {
    BeforeAll {
        # Import the module once so each test can call the public entry points directly.
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $modulePath = Join-Path -Path $projectRoot -ChildPath 'src\Hyde.psm1'
        $entryScriptPath = Join-Path -Path $projectRoot -ChildPath 'src\Hyde.ps1'
        Import-Module $modulePath

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
        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath

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

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath
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
        $verboseRecords = @(Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath -Verbose 4>&1)
        $verboseText = $verboseRecords | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message }

        $verboseText | Should -Contain "Building site from '$siteRoot' to '$destinationRoot'."
        $verboseText | Should -Contain "Rendering document 1 of 1: 'index.md'."
        $verboseText | Should -Contain "Copying static file 1 of 1: 'assets/site.css' to 'assets/site.css'."
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

        Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath | Out-Null
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

        Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath | Out-Null
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

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath
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

        Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath | Out-Null
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

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath
        $document = $context.Documents | Where-Object { $_.RelativePath -eq 'index.md' }
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'welcome\index.html') -Raw

        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'welcome\index.html') | Should -BeTrue
        $document.Url | Should -Be '/welcome/'
        $indexOutput | Should -Match '<p>/welcome/</p>'
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

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath
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

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath
        $collectionDocument = $context.Documents | Where-Object { $_.CollectionName -eq 'staff' }
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw

        $collectionDocument.Kind | Should -Be 'CollectionDocument'
        $collectionDocument.WriteOutput | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'staff\jane.html') | Should -BeTrue
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

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath
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

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath

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

        Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath | Out-Null
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'notes-index.html') -Raw

        $indexOutput | Should -Match '<li><a href="/notes/welcome\.html">Welcome Note</a></li>'
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

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath
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

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw
        $postUrls = @($context.Site.posts | ForEach-Object { $_.Url })

        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath '2026\03\28\newer-post.html') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath '2026\03\27\older-post.html') | Should -BeTrue
        $postUrls[0] | Should -Be '/2026/03/28/newer-post.html'
        $postUrls[1] | Should -Be '/2026/03/27/older-post.html'
        $indexOutput | Should -Match 'Newer Post\|/2026/03/28/newer-post\.html'
        $indexOutput | Should -Match 'Older Post\|/2026/03/27/older-post\.html'
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

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath

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

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath
        $draftDocument = $context.Documents | Where-Object { $_.RelativePath -eq '_drafts/preview.md' }

        $draftDocument.IsDraft | Should -BeTrue
        $draftDocument.CollectionName | Should -Be 'posts'
        $draftDocument.Published | Should -BeTrue
        $context.Site.posts.Count | Should -Be 1
        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath $draftDocument.OutputRelativePath.Replace('/', '\')) | Should -BeTrue
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

        Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath | Out-Null
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw

        $indexOutput | Should -Match '<aside>Hello / Home</aside>'
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

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath
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

        Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath | Out-Null
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

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath

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

        Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath | Out-Null
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw

        $indexOutput | Should -Match '<li>1 Home</li>'
        $indexOutput | Should -Match '<li>2 About</li>'
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

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath
        $guideOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'docs\guide.html') -Raw
        $overrideOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'docs\override.html') -Raw
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

        $context = Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath
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
            Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath | Out-Null
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
            Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath | Out-Null
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
            Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath | Out-Null
        } | Should -Throw -ExpectedMessage "*Build failed while preparing document*broken.md*Unsupported value for front matter setting 'published'*"
    }
}
