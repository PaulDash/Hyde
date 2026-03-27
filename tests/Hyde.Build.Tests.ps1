Describe 'Hyde build pipeline' {
    BeforeAll {
        # Import the module once so each test can call the public entry points directly.
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $modulePath = Join-Path -Path $projectRoot -ChildPath 'src\Hyde.psm1'
        $entryScriptPath = Join-Path -Path $projectRoot -ChildPath 'src\Hyde.ps1'
        Import-Module $modulePath -Force

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
        } | Should -Throw -ExpectedMessage '*Build failed while processing document*broken.md*Could not parse front matter*'
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
        } | Should -Throw -ExpectedMessage "*Build failed while processing document*broken.md*Unsupported value for front matter setting 'published'*"
    }
}
