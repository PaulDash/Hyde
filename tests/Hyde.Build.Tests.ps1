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
        $context = Invoke-HydeBuild -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath

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

        $context = Invoke-HydeBuild -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath
        $draftDocument = $context.Documents | Where-Object { $_.BaseName -eq 'draft' }

        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'draft.html') | Should -BeFalse
        $draftDocument.Published | Should -BeFalse
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

        Invoke-HydeBuild -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath | Out-Null
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

        Invoke-HydeBuild -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath | Out-Null
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

        $context = Invoke-HydeBuild -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw

        $indexOutput | Should -Match '<title>HOME</title>'
        $indexOutput | Should -Match '<header>Test Site</header>'
        $indexOutput | Should -Match '<main><h1>Hello</h1></main>'
        $indexOutput | Should -Match '<footer>Wrapper</footer>'
        $context.Documents.Count | Should -Be 1
    }

    It 'reports invalid site configuration with context' {
        $siteRoot = New-TestSiteDirectory -Name 'bad-config-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'bad-config-output'
        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
title: Test Site
broken: [unterminated
'@

        {
            Invoke-HydeBuild -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath | Out-Null
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
            Invoke-HydeBuild -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath | Out-Null
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
            Invoke-HydeBuild -Source $siteRoot -Destination $destinationRoot -Environment development -ScriptPath $entryScriptPath | Out-Null
        } | Should -Throw -ExpectedMessage "*Build failed while processing document*broken.md*Unsupported value for front matter setting 'published'*"
    }
}
