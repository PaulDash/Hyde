<#
.SYNOPSIS
Converts inline markdown snippets into HTML.

.DESCRIPTION
Applies a minimal inline markdown pass used by Hyde's lightweight renderer.

The converter intentionally supports a focused subset suitable for generated
paragraph, heading, and list content:
- autolinks enclosed in angle brackets
- inline code
- markdown links
- bold and emphasis markers

It first HTML-encodes input and then applies markdown transformations.

.PARAMETER Text
Inline markdown text to convert.

.OUTPUTS
System.String

.NOTES
This is not a full CommonMark implementation.
#>
# Process inline markdown elements inside a single text span.
function convertHydeInlineMarkdown {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [hashtable]$FootnoteState
    )

    # Encode HTML-sensitive characters before applying markdown substitutions.
    $encoded = [System.Net.WebUtility]::HtmlEncode($Text)

    # Preserve escaped markdown punctuation as literal characters using HTML entities.
    $encoded = [System.Text.RegularExpressions.Regex]::Replace(
        $encoded,
        '\\([\\`*_{}\[\]()#+\-.!|])',
        {
            param($match)

            return ('&#{0};' -f [int][char]$match.Groups[1].Value)
        }
    )

    # Convert angle-bracket autolinks such as <https://example.com>.
    $encoded = [System.Text.RegularExpressions.Regex]::Replace(
        $encoded,
        '&lt;(https?://[^&]+)&gt;',
        '<a href="$1">$1</a>'
    )

    # Convert angle-bracket email autolinks such as <person@example.com>.
    $encoded = [System.Text.RegularExpressions.Regex]::Replace(
        $encoded,
        '&lt;([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})&gt;',
        '<a href="mailto:$1">$1</a>'
    )

    # Convert inline code spans wrapped in backticks.
    $encoded = [System.Text.RegularExpressions.Regex]::Replace(
        $encoded,
        '`([^`]+)`',
        '<code>$1</code>'
    )

    # Convert markdown images with optional titles.
    $encoded = [System.Text.RegularExpressions.Regex]::Replace(
        $encoded,
        '!\[([^\]]*)\]\(([^\s\)]+)(?:\s+&quot;([^&]+)&quot;)?\)',
        {
            param($match)

            $alt = $match.Groups[1].Value
            $src = $match.Groups[2].Value
            $title = if ($match.Groups[3].Success) { $match.Groups[3].Value } else { '' }

            if ([string]::IsNullOrWhiteSpace($title)) {
                return "<img src=`"$src`" alt=`"$alt`" />"
            }

            return "<img src=`"$src`" alt=`"$alt`" title=`"$title`" />"
        }
    )

    # Convert markdown links with optional titles.
    $encoded = [System.Text.RegularExpressions.Regex]::Replace(
        $encoded,
        '\[([^\]]+)\]\(([^\s\)]+)(?:\s+&quot;([^&]+)&quot;)?\)',
        {
            param($match)

            $text = $match.Groups[1].Value
            $href = $match.Groups[2].Value
            $title = if ($match.Groups[3].Success) { $match.Groups[3].Value } else { '' }

            if ([string]::IsNullOrWhiteSpace($title)) {
                return "<a href=`"$href`">$text</a>"
            }

            return "<a href=`"$href`" title=`"$title`">$text</a>"
        }
    )

    # Convert strong+emphasis spans wrapped with three markers.
    $encoded = [System.Text.RegularExpressions.Regex]::Replace(
        $encoded,
        '\*\*\*([^\*]+)\*\*\*',
        '<strong><em>$1</em></strong>'
    )

    # Convert strong emphasis using double asterisks.
    $encoded = [System.Text.RegularExpressions.Regex]::Replace(
        $encoded,
        '\*\*([^\*]+)\*\*',
        '<strong>$1</strong>'
    )

    # Convert strong emphasis using double underscores.
    $encoded = [System.Text.RegularExpressions.Regex]::Replace(
        $encoded,
        '__([^_]+)__',
        '<strong>$1</strong>'
    )

    # Convert emphasis using single asterisks.
    $encoded = [System.Text.RegularExpressions.Regex]::Replace(
        $encoded,
        '(?<!\*)\*([^\*]+)\*(?!\*)',
        '<em>$1</em>'
    )

    # Convert emphasis using single underscores.
    $encoded = [System.Text.RegularExpressions.Regex]::Replace(
        $encoded,
        '(?<!_)_([^_]+)_(?!_)',
        '<em>$1</em>'
    )

    # Convert footnote references such as [^note] into linked superscripts.
    if ($FootnoteState) {
        $encoded = [System.Text.RegularExpressions.Regex]::Replace(
            $encoded,
            '\[\^([^\]\s]+)\]',
            {
                param($match)

                $footnoteId = $match.Groups[1].Value
                if (-not $FootnoteState.IndexById.ContainsKey($footnoteId)) {
                    [void]$FootnoteState.Order.Add($footnoteId)
                    $FootnoteState.IndexById[$footnoteId] = $FootnoteState.Order.Count
                }

                $index = [int]$FootnoteState.IndexById[$footnoteId]
                return "<sup id=`"fnref:$footnoteId`"><a href=`"#fn:$footnoteId`">$index</a></sup>"
            }
        )
    }

    return $encoded
}

# Split markdown into body lines plus extracted footnote definitions.
function splitHydeMarkdownFootnotes {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [string[]]$Lines
    )

    $bodyLines = New-Object System.Collections.ArrayList
    $definitions = @{}
    $index = 0

    while ($index -lt $Lines.Count) {
        $line = [string]$Lines[$index]

        if ($line -match '^\[\^([^\]\s]+)\]:\s*(.*)$') {
            $footnoteId = [string]$Matches[1]
            $definitionLines = New-Object System.Collections.ArrayList
            [void]$definitionLines.Add([string]$Matches[2])
            $index++

            while ($index -lt $Lines.Count) {
                $nextLine = [string]$Lines[$index]
                if ($nextLine -match '^(?: {4}|\t)(.*)$') {
                    [void]$definitionLines.Add([string]$Matches[1])
                    $index++
                    continue
                }

                if ([string]::IsNullOrWhiteSpace($nextLine)) {
                    [void]$definitionLines.Add('')
                    $index++
                    continue
                }

                break
            }

            $definitions[$footnoteId] = [string]::Join("`n", @($definitionLines.ToArray()))
            continue
        }

        [void]$bodyLines.Add($line)
        $index++
    }

    return @{
        BodyLines   = @($bodyLines.ToArray())
        Definitions = $definitions
    }
}

# Render collected footnote definitions as an ordered HTML list.
function convertHydeMarkdownFootnotesToHtml {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$FootnoteState,

        [Parameter(Mandatory = $true)]
        [hashtable]$Definitions
    )

    if ($FootnoteState.Order.Count -eq 0) {
        return ''
    }

    $items = New-Object System.Collections.ArrayList
    foreach ($footnoteId in @($FootnoteState.Order)) {
        $rawDefinition = if ($Definitions.ContainsKey($footnoteId)) { [string]$Definitions[$footnoteId] } else { '' }
        $paragraphs = @(@($rawDefinition -split "(?:`r?`n){2,}") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

        if ($paragraphs.Count -eq 0) {
            $content = ''
        } elseif ($paragraphs.Count -eq 1) {
            $content = "<p>$(convertHydeInlineMarkdown -Text ($paragraphs[0].Trim()))</p>"
        } else {
            $renderedParagraphs = @($paragraphs | ForEach-Object { "<p>$(convertHydeInlineMarkdown -Text ($_.Trim()))</p>" })
            $content = ($renderedParagraphs -join [Environment]::NewLine)
        }

        $content += " <a href=`"#fnref:$footnoteId`" class=`"footnote-backref`">&#8617;</a>"
        [void]$items.Add("<li id=`"fn:$footnoteId`">$content</li>")
    }

    return @"
<section class="footnotes">
<ol>
$($items -join [Environment]::NewLine)
</ol>
</section>
"@
}

<#
.SYNOPSIS
Converts markdown content to HTML.

.DESCRIPTION
Renders a practical markdown subset used by Hyde's built-in renderer.

Block support:
- ATX headings (# through ######)
- unordered lists (-, *, +)
- fenced code blocks using ```
- paragraph blocks
- raw HTML line passthrough

Inline rendering is delegated to convertHydeInlineMarkdown.

.PARAMETER Markdown
Markdown content to convert.

.OUTPUTS
System.String

.NOTES
The implementation is intentionally lightweight and deterministic.
For advanced markdown behavior, use a dedicated markdown processor plugin.
#>
# Convert markdown blocks into HTML output for Hyde documents.
function convertHydeMarkdown {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Markdown,

        [switch]$SkipFootnoteParsing
    )

    # Normalize line endings first so the simple parser behaves the same on all platforms.
    $normalizedContent = ($Markdown -replace "`r`n", "`n") -replace "`r", "`n"
    $lines = @($normalizedContent -split "`n")

    $footnoteDefinitions = @{}
    if (-not $SkipFootnoteParsing) {
        $footnoteSplit = splitHydeMarkdownFootnotes -Lines @($lines)
        $lines = @($footnoteSplit.BodyLines)
        $footnoteDefinitions = $footnoteSplit.Definitions
    }

    $footnoteState = @{
        Order     = New-Object System.Collections.ArrayList
        IndexById = @{}
    }

    $blocks = New-Object System.Collections.ArrayList
    $paragraphLines = New-Object System.Collections.ArrayList
    $listItems = New-Object System.Collections.ArrayList
    $orderedListItems = New-Object System.Collections.ArrayList
    $codeLines = New-Object System.Collections.ArrayList
    $inCodeFence = $false

    # Buffer-based helpers let the parser convert markdown one block at a time.
    # Flush accumulated paragraph lines to a rendered paragraph block.
    function completeHydeParagraphBuffer {
        if ($paragraphLines.Count -eq 0) {
            return
        }

        $text = ($paragraphLines.ToArray() -join "`n").Trim()
        $text = [System.Text.RegularExpressions.Regex]::Replace($text, '( {2,}|\\)\n', '__HYDE_BR__')
        $rendered = convertHydeInlineMarkdown -Text $text -FootnoteState $footnoteState
        $rendered = $rendered.Replace('__HYDE_BR__', '<br />')
        [void]$blocks.Add("<p>$rendered</p>")
        $paragraphLines.Clear()
    }

    # Flush accumulated unordered list lines to a rendered list block.
    function completeHydeListBuffer {
        if ($listItems.Count -eq 0) {
            return
        }

        $items = $listItems.ToArray() | ForEach-Object {
            "<li>$(convertHydeInlineMarkdown -Text $_ -FootnoteState $footnoteState)</li>"
        }

        [void]$blocks.Add("<ul>$($items -join '')</ul>")
        $listItems.Clear()
    }

    # Flush accumulated ordered list lines to a rendered list block.
    function completeHydeOrderedListBuffer {
        if ($orderedListItems.Count -eq 0) {
            return
        }

        $items = $orderedListItems.ToArray() | ForEach-Object {
            "<li>$(convertHydeInlineMarkdown -Text $_ -FootnoteState $footnoteState)</li>"
        }

        [void]$blocks.Add("<ol>$($items -join '')</ol>")
        $orderedListItems.Clear()
    }

    # Flush fenced code content to a rendered code block.
    function completeHydeCodeFenceBuffer {
        if ($codeLines.Count -eq 0) {
            [void]$blocks.Add('<pre><code></code></pre>')
            return
        }

        $code = [System.Net.WebUtility]::HtmlEncode(($codeLines.ToArray() -join "`n"))
        [void]$blocks.Add("<pre><code>$code</code></pre>")
        $codeLines.Clear()
    }

    $index = 0
    while ($index -lt $lines.Count) {
        $line = [string]$lines[$index]

        # Handle fenced code block delimiters.
        if ($line -match '^\s*```') {
            if ($inCodeFence) {
                completeHydeCodeFenceBuffer
                $inCodeFence = $false
            } else {
                completeHydeParagraphBuffer
                completeHydeListBuffer
                completeHydeOrderedListBuffer
                $codeLines.Clear()
                $inCodeFence = $true
            }

            $index++
            continue
        }

        # Keep fenced-code body content untouched until the closing fence.
        if ($inCodeFence) {
            [void]$codeLines.Add($line)
            $index++
            continue
        }

        # Handle indented code blocks that use four leading spaces or one tab.
        if ($line -match '^(?: {4}|\t)(.*)$') {
            completeHydeParagraphBuffer
            completeHydeListBuffer
            completeHydeOrderedListBuffer

            $indentedCodeLines = New-Object System.Collections.ArrayList
            while ($index -lt $lines.Count) {
                $indentedLine = [string]$lines[$index]
                if ($indentedLine -match '^(?: {4}|\t)(.*)$') {
                    [void]$indentedCodeLines.Add([string]$Matches[1])
                    $index++
                    continue
                }

                if ([string]::IsNullOrWhiteSpace($indentedLine)) {
                    [void]$indentedCodeLines.Add('')
                    $index++
                    continue
                }

                break
            }

            $code = [System.Net.WebUtility]::HtmlEncode(($indentedCodeLines.ToArray() -join "`n"))
            [void]$blocks.Add("<pre><code>$code</code></pre>")
            continue
        }

        # Handle blockquotes that start with one or more ">" prefixes.
        if ($line -match '^\s*>\s?(.*)$') {
            completeHydeParagraphBuffer
            completeHydeListBuffer
            completeHydeOrderedListBuffer

            $quoteLines = New-Object System.Collections.ArrayList
            while ($index -lt $lines.Count) {
                $quoteCandidate = [string]$lines[$index]
                if ($quoteCandidate -match '^\s*>\s?(.*)$') {
                    [void]$quoteLines.Add([string]$Matches[1])
                    $index++
                    continue
                }

                if ([string]::IsNullOrWhiteSpace($quoteCandidate)) {
                    [void]$quoteLines.Add('')
                    $index++
                    continue
                }

                break
            }

            $quoteMarkdown = [string]::Join("`n", @($quoteLines.ToArray()))
            $quoteHtml = convertHydeMarkdown -Markdown $quoteMarkdown -SkipFootnoteParsing
            [void]$blocks.Add("<blockquote>$quoteHtml</blockquote>")
            continue
        }

        # Treat blank lines as block separators.
        if ([string]::IsNullOrWhiteSpace($line)) {
            completeHydeParagraphBuffer
            completeHydeListBuffer
            completeHydeOrderedListBuffer
            $index++
            continue
        }

        # Handle Setext-style headings that underline the previous line with === or ---.
        if ($index + 1 -lt $lines.Count) {
            $nextLine = [string]$lines[$index + 1]
            if ($nextLine -match '^\s*=+\s*$') {
                completeHydeParagraphBuffer
                completeHydeListBuffer
                completeHydeOrderedListBuffer
                [void]$blocks.Add("<h1>$(convertHydeInlineMarkdown -Text $line.Trim() -FootnoteState $footnoteState)</h1>")
                $index += 2
                continue
            }

            if ($nextLine -match '^\s*-{2,}\s*$') {
                completeHydeParagraphBuffer
                completeHydeListBuffer
                completeHydeOrderedListBuffer
                [void]$blocks.Add("<h2>$(convertHydeInlineMarkdown -Text $line.Trim() -FootnoteState $footnoteState)</h2>")
                $index += 2
                continue
            }
        }

        # Handle horizontal rules made of three-or-more matching marker runs.
        if ($line -match '^\s{0,3}(?:\*\s*){3,}$' -or $line -match '^\s{0,3}(?:-\s*){3,}$' -or $line -match '^\s{0,3}(?:_\s*){3,}$') {
            completeHydeParagraphBuffer
            completeHydeListBuffer
            completeHydeOrderedListBuffer
            [void]$blocks.Add('<hr />')
            $index++
            continue
        }

        # Handle ATX headings that begin with one-to-six # characters.
        if ($line -match '^(#{1,6})\s+(.*)$') {
            completeHydeParagraphBuffer
            completeHydeListBuffer
            completeHydeOrderedListBuffer
            $level = $Matches[1].Length
            $headingText = convertHydeInlineMarkdown -Text $Matches[2].Trim() -FootnoteState $footnoteState
            [void]$blocks.Add("<h$level>$headingText</h$level>")
            $index++
            continue
        }

        # Handle unordered list entries that begin with -, *, or + markers.
        if ($line -match '^\s*[-*+]\s+(.*)$') {
            completeHydeParagraphBuffer
            completeHydeOrderedListBuffer
            [void]$listItems.Add($Matches[1].Trim())
            $index++
            continue
        }

        # Handle ordered list entries that begin with a number and period.
        if ($line -match '^\s*\d+\.\s+(.*)$') {
            completeHydeParagraphBuffer
            completeHydeListBuffer
            [void]$orderedListItems.Add($Matches[1].Trim())
            $index++
            continue
        }

        # Raw HTML blocks pass straight through instead of being escaped as markdown paragraphs.
        if ($line.TrimStart().StartsWith('<')) {
            completeHydeParagraphBuffer
            completeHydeListBuffer
            completeHydeOrderedListBuffer
            [void]$blocks.Add($line)
            $index++
            continue
        }

        [void]$paragraphLines.Add($line)
        $index++
    }

    if ($inCodeFence) {
        completeHydeCodeFenceBuffer
    } else {
        completeHydeParagraphBuffer
        completeHydeListBuffer
        completeHydeOrderedListBuffer
    }

    $bodyHtml = ($blocks.ToArray() -join [Environment]::NewLine)
    $footnotesHtml = if ($SkipFootnoteParsing) { '' } else { convertHydeMarkdownFootnotesToHtml -FootnoteState $footnoteState -Definitions $footnoteDefinitions }
    if ([string]::IsNullOrWhiteSpace($footnotesHtml)) {
        return $bodyHtml
    }

    if ([string]::IsNullOrWhiteSpace($bodyHtml)) {
        return $footnotesHtml.Trim()
    }

    return ($bodyHtml + [Environment]::NewLine + $footnotesHtml.Trim())
}
