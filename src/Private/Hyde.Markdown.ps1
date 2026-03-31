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
# Convert plain text URLs into anchor tags while skipping existing HTML tags.
function convertHydeBareUrlAutolinks {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text
    )

    $segments = [System.Text.RegularExpressions.Regex]::Split($Text, '(<[^>]+>)')
    $result = New-Object System.Text.StringBuilder
    foreach ($segment in $segments) {
        if ([string]::IsNullOrEmpty($segment)) {
            continue
        }

        if ($segment.StartsWith('<')) {
            [void]$result.Append($segment)
            continue
        }

        $converted = [System.Text.RegularExpressions.Regex]::Replace(
            $segment,
            '(^|[\s\(\[])((?:https?://)[^\s<]+)',
            {
                param($match)

                $prefix = $match.Groups[1].Value
                $url = $match.Groups[2].Value
                $trimmedUrl = $url.TrimEnd('.', ',', ';', ':', '!', '?', ')')
                $suffix = $url.Substring($trimmedUrl.Length)

                if ([string]::IsNullOrWhiteSpace($trimmedUrl)) {
                    return $match.Value
                }

                return "$prefix<a href=`"$trimmedUrl`">$trimmedUrl</a>$suffix"
            }
        )

        [void]$result.Append($converted)
    }

    return $result.ToString()
}

# Create deterministic, unique heading IDs using a slug policy.
function newHydeHeadingSlug {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HeadingHtml,

        [Parameter(Mandatory = $true)]
        [hashtable]$SlugState
    )

    $plainText = [System.Text.RegularExpressions.Regex]::Replace($HeadingHtml, '<[^>]+>', '')
    $plainText = [System.Net.WebUtility]::HtmlDecode($plainText)
    $slug = $plainText.ToLowerInvariant()
    $slug = [System.Text.RegularExpressions.Regex]::Replace($slug, '[^a-z0-9\s-]', '')
    $slug = [System.Text.RegularExpressions.Regex]::Replace($slug, '[\s-]+', '-')
    $slug = $slug.Trim('-')

    if ([string]::IsNullOrWhiteSpace($slug)) {
        $slug = 'section'
    }

    if (-not $SlugState.ContainsKey($slug)) {
        $SlugState[$slug] = 1
        return $slug
    }

    $SlugState[$slug] = [int]$SlugState[$slug] + 1
    return ($slug + '-' + $SlugState[$slug])
}

# Split a markdown table row into trimmed cell values.
function splitHydeMarkdownTableRow {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Row
    )

    $normalized = $Row.Trim()
    if ($normalized.StartsWith('|')) {
        $normalized = $normalized.Substring(1)
    }

    if ($normalized.EndsWith('|')) {
        $normalized = $normalized.Substring(0, $normalized.Length - 1)
    }

    return @($normalized.Split('|') | ForEach-Object { $_.Trim() })
}

# Resolve markdown table alignment markers into HTML alignment values.
function getHydeMarkdownTableAlignments {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DividerLine
    )

    $alignmentCells = splitHydeMarkdownTableRow -Row $DividerLine
    $alignments = New-Object System.Collections.ArrayList
    foreach ($cell in $alignmentCells) {
        $trimmedCell = $cell.Trim()
        $isValid = $trimmedCell -match '^:?-{3,}:?$'
        if (-not $isValid) {
            return @()
        }

        if ($trimmedCell.StartsWith(':') -and $trimmedCell.EndsWith(':')) {
            [void]$alignments.Add('center')
            continue
        }

        if ($trimmedCell.EndsWith(':')) {
            [void]$alignments.Add('right')
            continue
        }

        if ($trimmedCell.StartsWith(':')) {
            [void]$alignments.Add('left')
            continue
        }

        [void]$alignments.Add('')
    }

    return @($alignments.ToArray())
}

# Process inline markdown elements inside a single text span.
function convertHydeInlineMarkdown {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
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

    # Convert strikethrough using double tildes.
    $encoded = [System.Text.RegularExpressions.Regex]::Replace(
        $encoded,
        '(?<!~)~~([^~]+)~~(?!~)',
        '<del>$1</del>'
    )

    # Convert plain URLs into anchors after other inline replacements.
    $encoded = convertHydeBareUrlAutolinks -Text $encoded

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
    $headingSlugState = @{}

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
        $text = [System.Text.RegularExpressions.Regex]::Replace($text, '\n+', ' ')
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

        $hasTaskItems = $false
        $items = New-Object System.Collections.ArrayList
        foreach ($listItem in $listItems.ToArray()) {
            if ($listItem -match '^\[(?<marker>[ xX])\]') {
                $hasTaskItems = $true
                $isChecked = $Matches['marker'] -match '[xX]'
                $taskLabel = if ($listItem.Length -gt 3) { $listItem.Substring(3).TrimStart() } else { '' }
                $taskText = convertHydeInlineMarkdown -Text $taskLabel -FootnoteState $footnoteState
                if ($isChecked) {
                    [void]$items.Add("<li class=`"task-list-item`"><input type=`"checkbox`" checked disabled /> $taskText</li>")
                    continue
                }

                [void]$items.Add("<li class=`"task-list-item`"><input type=`"checkbox`" disabled /> $taskText</li>")
                continue
            }

            [void]$items.Add("<li>$(convertHydeInlineMarkdown -Text $listItem -FootnoteState $footnoteState)</li>")
        }

        if ($hasTaskItems) {
            [void]$blocks.Add("<ul class=`"task-list`">$($items -join '')</ul>")
        } else {
            [void]$blocks.Add("<ul>$($items -join '')</ul>")
        }

        $listItems.Clear()
    }

    # Flush accumulated ordered list lines to a rendered list block.
    function completeHydeOrderedListBuffer {
        if ($orderedListItems.Count -eq 0) {
            return
        }

        $hasTaskItems = $false
        $items = New-Object System.Collections.ArrayList
        foreach ($orderedListItem in $orderedListItems.ToArray()) {
            if ($orderedListItem -match '^\[(?<marker>[ xX])\]') {
                $hasTaskItems = $true
                $isChecked = $Matches['marker'] -match '[xX]'
                $taskLabel = if ($orderedListItem.Length -gt 3) { $orderedListItem.Substring(3).TrimStart() } else { '' }
                $taskText = convertHydeInlineMarkdown -Text $taskLabel -FootnoteState $footnoteState
                if ($isChecked) {
                    [void]$items.Add("<li class=`"task-list-item`"><input type=`"checkbox`" checked disabled /> $taskText</li>")
                    continue
                }

                [void]$items.Add("<li class=`"task-list-item`"><input type=`"checkbox`" disabled /> $taskText</li>")
                continue
            }

            [void]$items.Add("<li>$(convertHydeInlineMarkdown -Text $orderedListItem -FootnoteState $footnoteState)</li>")
        }

        if ($hasTaskItems) {
            [void]$blocks.Add("<ol class=`"task-list`">$($items -join '')</ol>")
        } else {
            [void]$blocks.Add("<ol>$($items -join '')</ol>")
        }

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
                $headingHtml = convertHydeInlineMarkdown -Text $line.Trim() -FootnoteState $footnoteState
                $headingId = newHydeHeadingSlug -HeadingHtml $headingHtml -SlugState $headingSlugState
                [void]$blocks.Add("<h1 id=`"$headingId`">$headingHtml</h1>")
                $index += 2
                continue
            }

            if ($nextLine -match '^\s*-{2,}\s*$') {
                completeHydeParagraphBuffer
                completeHydeListBuffer
                completeHydeOrderedListBuffer
                $headingHtml = convertHydeInlineMarkdown -Text $line.Trim() -FootnoteState $footnoteState
                $headingId = newHydeHeadingSlug -HeadingHtml $headingHtml -SlugState $headingSlugState
                [void]$blocks.Add("<h2 id=`"$headingId`">$headingHtml</h2>")
                $index += 2
                continue
            }
        }

        # Handle markdown tables with a header line plus divider line.
        if (($index + 1 -lt $lines.Count) -and $line.Contains('|')) {
            $dividerLine = [string]$lines[$index + 1]
            $alignments = getHydeMarkdownTableAlignments -DividerLine $dividerLine
            if ($alignments.Count -gt 0) {
                completeHydeParagraphBuffer
                completeHydeListBuffer
                completeHydeOrderedListBuffer

                $headerCells = splitHydeMarkdownTableRow -Row $line
                $maxCellCount = [Math]::Min($headerCells.Count, $alignments.Count)
                $headerHtml = New-Object System.Collections.ArrayList
                for ($cellIndex = 0; $cellIndex -lt $maxCellCount; $cellIndex++) {
                    $alignmentAttribute = if ([string]::IsNullOrWhiteSpace($alignments[$cellIndex])) { '' } else { " style=`"text-align: $($alignments[$cellIndex]);`"" }
                    $cellHtml = convertHydeInlineMarkdown -Text $headerCells[$cellIndex] -FootnoteState $footnoteState
                    [void]$headerHtml.Add("<th$alignmentAttribute>$cellHtml</th>")
                }

                $bodyRows = New-Object System.Collections.ArrayList
                $index += 2
                while ($index -lt $lines.Count) {
                    $rowLine = [string]$lines[$index]
                    if ([string]::IsNullOrWhiteSpace($rowLine) -or -not $rowLine.Contains('|')) {
                        break
                    }

                    $rowCells = splitHydeMarkdownTableRow -Row $rowLine
                    $rowHtml = New-Object System.Collections.ArrayList
                    for ($cellIndex = 0; $cellIndex -lt $maxCellCount; $cellIndex++) {
                        $cellValue = if ($cellIndex -lt $rowCells.Count) { $rowCells[$cellIndex] } else { '' }
                        $alignmentAttribute = if ([string]::IsNullOrWhiteSpace($alignments[$cellIndex])) { '' } else { " style=`"text-align: $($alignments[$cellIndex]);`"" }
                        $cellHtml = convertHydeInlineMarkdown -Text $cellValue -FootnoteState $footnoteState
                        [void]$rowHtml.Add("<td$alignmentAttribute>$cellHtml</td>")
                    }

                    [void]$bodyRows.Add("<tr>$($rowHtml -join '')</tr>")
                    $index++
                }

                $tableBody = if ($bodyRows.Count -gt 0) { "<tbody>$($bodyRows -join '')</tbody>" } else { '' }
                [void]$blocks.Add("<table><thead><tr>$($headerHtml -join '')</tr></thead>$tableBody</table>")
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
            $headingId = newHydeHeadingSlug -HeadingHtml $headingText -SlugState $headingSlugState
            [void]$blocks.Add("<h$level id=`"$headingId`">$headingText</h$level>")
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
