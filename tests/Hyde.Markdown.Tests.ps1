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

- [ ] Open task
- [x] Done task

1. [ ] Ordered open
2. [x] Ordered done

---

Inline image: ![Alt text](/assets/pic.png "Picture")

Strikethrough: ~~legacy~~ text.

Bare URL: https://example.com/docs?x=1.

| Name | Score | Status |
| :--- | ---: | :---: |
| Alpha | 10 | Ready |
| Beta | 20 | Done |

Escaped punctuation: \*not italic\* and \[literal\]
'@

        Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development | Out-Null
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw

        $indexOutput | Should -Match '<h1 id="hash-heading">Hash Heading</h1>'
        $indexOutput | Should -Match '<h1 id="hash-heading-2">Hash Heading</h1>'
        $indexOutput | Should -Match '<h2 id="setext-heading">Setext heading</h2>'
        $indexOutput | Should -Match '<br />'
        $indexOutput | Should -Match '<blockquote>'
        $indexOutput | Should -Match '<ol><li>First ordered</li><li>Second ordered</li></ol>'
        $indexOutput | Should -Match '<ul><li>One unordered</li><li>Two unordered</li></ul>'
        $indexOutput | Should -Match '<ul class="task-list"><li class="task-list-item"><input type="checkbox" disabled /> Open task</li><li class="task-list-item"><input type="checkbox" checked disabled /> Done task</li></ul>'
        $indexOutput | Should -Match '<ol class="task-list"><li class="task-list-item"><input type="checkbox" disabled /> Ordered open</li><li class="task-list-item"><input type="checkbox" checked disabled /> Ordered done</li></ol>'
        $indexOutput | Should -Match '<hr />'
        $indexOutput | Should -Match '<img src="/assets/pic\.png" alt="Alt text" title="Picture" />'
        $indexOutput | Should -Match '<del>legacy</del>'
        $indexOutput | Should -Match '<a href="https://example\.com/docs\?x=1">https://example\.com/docs\?x=1</a>\.'
        $indexOutput | Should -Match '<table><thead><tr><th style="text-align: left;">Name</th><th style="text-align: right;">Score</th><th style="text-align: center;">Status</th></tr></thead><tbody><tr><td style="text-align: left;">Alpha</td><td style="text-align: right;">10</td><td style="text-align: center;">Ready</td></tr><tr><td style="text-align: left;">Beta</td><td style="text-align: right;">20</td><td style="text-align: center;">Done</td></tr></tbody></table>'
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

    It 'renders subscript and superscript inline spans' {
        $siteRoot = New-TestSiteDirectory -Name 'markdown-sub-sup-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'markdown-sub-sup-output'
        $layoutsDirectory = Join-Path -Path $siteRoot -ChildPath '_layouts'

        [void](New-Item -Path $layoutsDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value ''

        Set-Content -LiteralPath (Join-Path -Path $layoutsDirectory -ChildPath 'default.html') -Encoding UTF8 -Value '<main>{{ content }}</main>'

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
layout: default
---
Water is H~2~O.

E = mc^2^.
'@

        Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development | Out-Null
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw

        $indexOutput | Should -Match 'H<sub>2</sub>O'
        $indexOutput | Should -Match 'mc<sup>2</sup>'
    }

    It 'renders abbreviation definitions and wraps occurrences in <abbr> elements' {
        $siteRoot = New-TestSiteDirectory -Name 'markdown-abbr-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'markdown-abbr-output'
        $layoutsDirectory = Join-Path -Path $siteRoot -ChildPath '_layouts'

        [void](New-Item -Path $layoutsDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value ''

        Set-Content -LiteralPath (Join-Path -Path $layoutsDirectory -ChildPath 'default.html') -Encoding UTF8 -Value '<main>{{ content }}</main>'

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
layout: default
---
The HTML spec defines CSS rules.

*[HTML]: HyperText Markup Language
*[CSS]: Cascading Style Sheets
'@

        Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development | Out-Null
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw

        $indexOutput | Should -Match '<abbr title="HyperText Markup Language">HTML</abbr>'
        $indexOutput | Should -Match '<abbr title="Cascading Style Sheets">CSS</abbr>'
        $indexOutput | Should -Not -Match '\*\[HTML\]'
    }

    It 'renders definition lists with terms and definitions' {
        $siteRoot = New-TestSiteDirectory -Name 'markdown-dl-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'markdown-dl-output'
        $layoutsDirectory = Join-Path -Path $siteRoot -ChildPath '_layouts'

        [void](New-Item -Path $layoutsDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value ''

        Set-Content -LiteralPath (Join-Path -Path $layoutsDirectory -ChildPath 'default.html') -Encoding UTF8 -Value '<main>{{ content }}</main>'

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
layout: default
---
Apple
: A fruit
: Also a tech company

Orange
: A citrus fruit
'@

        Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development | Out-Null
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw

        $indexOutput | Should -Match '<dl>'
        $indexOutput | Should -Match '<dt>Apple</dt>'
        $indexOutput | Should -Match '<dd>A fruit</dd>'
        $indexOutput | Should -Match '<dd>Also a tech company</dd>'
        $indexOutput | Should -Match '<dt>Orange</dt>'
        $indexOutput | Should -Match '<dd>A citrus fruit</dd>'
    }

    It 'renders a table with a caption line above it' {
        $siteRoot = New-TestSiteDirectory -Name 'markdown-caption-site'
        $destinationRoot = Join-Path -Path $TestDrive -ChildPath 'markdown-caption-output'
        $layoutsDirectory = Join-Path -Path $siteRoot -ChildPath '_layouts'

        [void](New-Item -Path $layoutsDirectory -ItemType Directory -Force)

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath '_config.yml') -Encoding UTF8 -Value ''

        Set-Content -LiteralPath (Join-Path -Path $layoutsDirectory -ChildPath 'default.html') -Encoding UTF8 -Value '<main>{{ content }}</main>'

        Set-Content -LiteralPath (Join-Path -Path $siteRoot -ChildPath 'index.md') -Encoding UTF8 -Value @'
---
layout: default
---
[Quarterly Results]
| Quarter | Revenue |
| ------- | ------- |
| Q1      | 100     |
| Q2      | 200     |
'@

        Publish-StaticSite -Source $siteRoot -Destination $destinationRoot -Environment development | Out-Null
        $indexOutput = Get-Content -LiteralPath (Join-Path -Path $destinationRoot -ChildPath 'index.html') -Raw

        $indexOutput | Should -Match '<table><caption>Quarterly Results</caption><thead>'
        $indexOutput | Should -Match '<th>Quarter</th>'
        $indexOutput | Should -Match '<td>Q1</td>'
    }
}
