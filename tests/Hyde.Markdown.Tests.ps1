Describe 'Hyde markdown renderer' {
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

    It 'renders core basic-syntax markdown elements' {
        $siteRoot = New-TestSiteDirectory -Name 'markdown-basic-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'markdown-basic-output'
        $layoutsDirectory = Join-Path -Path $siteRoot -ChildPath '_layouts'

        [void](New-Item -Path $layoutsDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
plugins:
  - titles-from-headings
'@

        Set-Content -LiteralPath (Join-Path -Path $layoutsDirectory -ChildPath 'default.html') -Encoding UTF8 -Value @'
<main>{{ content }}</main>
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
layout: default
---
# Hash Heading

Setext heading
-------------

A paragraph with a hard break.\
Next line.

> Quoted line

1. First ordered
2. Second ordered

- One unordered
- Two unordered

---

Inline image: ![Alt text](/assets/pic.png "Picture")

Escaped punctuation: \*not italic\* and \[literal\]
'@

        Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development | Out-Null
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw

        $indexOutput | Should -Match '<h1>Hash Heading</h1>'
        $indexOutput | Should -Match '<h2>Setext heading</h2>'
        $indexOutput | Should -Match '<br />'
        $indexOutput | Should -Match '<blockquote>'
        $indexOutput | Should -Match '<ol><li>First ordered</li><li>Second ordered</li></ol>'
        $indexOutput | Should -Match '<ul><li>One unordered</li><li>Two unordered</li></ul>'
        $indexOutput | Should -Match '<hr />'
        $indexOutput | Should -Match '<img src="/assets/pic\.png" alt="Alt text" title="Picture" />'
        $indexOutput | Should -Match '&#42;not italic&#42;'
        $indexOutput | Should -Match '&#91;literal&#93;'
    }

    It 'renders markdown footnotes with references and back-links' {
        $siteRoot = New-TestSiteDirectory -Name 'markdown-footnotes-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'markdown-footnotes-output'
        $layoutsDirectory = Join-Path -Path $siteRoot -ChildPath '_layouts'

        [void](New-Item -Path $layoutsDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value @'
plugins:
  - titles-from-headings
'@

        Set-Content -LiteralPath (Join-Path -Path $layoutsDirectory -ChildPath 'default.html') -Encoding UTF8 -Value @'
<main>{{ content }}</main>
'@

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
layout: default
---
# Footnotes

A sentence with a note.[^one]

Another note appears here.[^two]

[^one]: First footnote text.

[^two]: Second footnote paragraph one.

    Second footnote paragraph two.
'@

        Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development | Out-Null
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw

        $indexOutput | Should -Match '<sup id="fnref:one"><a href="#fn:one">1</a></sup>'
        $indexOutput | Should -Match '<sup id="fnref:two"><a href="#fn:two">2</a></sup>'
        $indexOutput | Should -Match '<section class="footnotes">'
        $indexOutput | Should -Match '<li id="fn:one">'
        $indexOutput | Should -Match '<li id="fn:two">'
        $indexOutput | Should -Match 'class="footnote-backref"'
    }
}
