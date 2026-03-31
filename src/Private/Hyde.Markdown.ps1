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
function convertHydeInlineMarkdown {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    # Escape first, then apply a small markdown subset for inline formatting.
    $encoded = [System.Net.WebUtility]::HtmlEncode($Text)

    $encoded = [System.Text.RegularExpressions.Regex]::Replace(
        $encoded,
        '&lt;(https?://[^&]+)&gt;',
        '<a href="$1">$1</a>'
    )

    $encoded = [System.Text.RegularExpressions.Regex]::Replace(
        $encoded,
        '`([^`]+)`',
        '<code>$1</code>'
    )

    $encoded = [System.Text.RegularExpressions.Regex]::Replace(
        $encoded,
        '\[([^\]]+)\]\(([^)]+)\)',
        '<a href="$2">$1</a>'
    )

    $encoded = [System.Text.RegularExpressions.Regex]::Replace(
        $encoded,
        '\*\*([^\*]+)\*\*',
        '<strong>$1</strong>'
    )

    $encoded = [System.Text.RegularExpressions.Regex]::Replace(
        $encoded,
        '__([^_]+)__',
        '<strong>$1</strong>'
    )

    $encoded = [System.Text.RegularExpressions.Regex]::Replace(
        $encoded,
        '(?<!\*)\*([^\*]+)\*(?!\*)',
        '<em>$1</em>'
    )

    $encoded = [System.Text.RegularExpressions.Regex]::Replace(
        $encoded,
        '(?<!_)_([^_]+)_(?!_)',
        '<em>$1</em>'
    )

    return $encoded
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
function convertHydeMarkdown {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Markdown
    )

    # Normalize line endings first so the simple parser behaves the same on all platforms.
    $normalizedContent = ($Markdown -replace "`r`n", "`n") -replace "`r", "`n"
    $lines = $normalizedContent -split "`n"
    $blocks = New-Object System.Collections.ArrayList
    $paragraphLines = New-Object System.Collections.ArrayList
    $listItems = New-Object System.Collections.ArrayList
    $codeLines = New-Object System.Collections.ArrayList
    $inCodeFence = $false

    # Buffer-based helpers let the parser convert markdown one block at a time.
    function completeHydeParagraphBuffer {
        if ($paragraphLines.Count -eq 0) {
            return
        }

        $text = ($paragraphLines.ToArray() -join ' ').Trim()
        [void]$blocks.Add("<p>$(convertHydeInlineMarkdown -Text $text)</p>")
        $paragraphLines.Clear()
    }

    function completeHydeListBuffer {
        if ($listItems.Count -eq 0) {
            return
        }

        $items = $listItems.ToArray() | ForEach-Object {
            "<li>$(convertHydeInlineMarkdown -Text $_)</li>"
        }

        [void]$blocks.Add("<ul>$($items -join '')</ul>")
        $listItems.Clear()
    }

    function completeHydeCodeFenceBuffer {
        if ($codeLines.Count -eq 0) {
            [void]$blocks.Add('<pre><code></code></pre>')
            return
        }

        $code = [System.Net.WebUtility]::HtmlEncode(($codeLines.ToArray() -join "`n"))
        [void]$blocks.Add("<pre><code>$code</code></pre>")
        $codeLines.Clear()
    }

    foreach ($line in $lines) {
        if ($line -match '^\s*```') {
            if ($inCodeFence) {
                completeHydeCodeFenceBuffer
                $inCodeFence = $false
            } else {
                completeHydeParagraphBuffer
                completeHydeListBuffer
                $codeLines.Clear()
                $inCodeFence = $true
            }

            continue
        }

        if ($inCodeFence) {
            [void]$codeLines.Add($line)
            continue
        }

        if ([string]::IsNullOrWhiteSpace($line)) {
            completeHydeParagraphBuffer
            completeHydeListBuffer
            continue
        }

        if ($line -match '^(#{1,6})\s+(.*)$') {
            completeHydeParagraphBuffer
            completeHydeListBuffer
            $level = $Matches[1].Length
            $headingText = convertHydeInlineMarkdown -Text $Matches[2].Trim()
            [void]$blocks.Add("<h$level>$headingText</h$level>")
            continue
        }

        if ($line -match '^\s*[-*+]\s+(.*)$') {
            completeHydeParagraphBuffer
            [void]$listItems.Add($Matches[1].Trim())
            continue
        }

        # Raw HTML blocks pass straight through instead of being escaped as markdown paragraphs.
        if ($line.TrimStart().StartsWith('<')) {
            completeHydeParagraphBuffer
            completeHydeListBuffer
            [void]$blocks.Add($line)
            continue
        }

        [void]$paragraphLines.Add($line.Trim())
    }

    if ($inCodeFence) {
        completeHydeCodeFenceBuffer
    } else {
        completeHydeParagraphBuffer
        completeHydeListBuffer
    }

    return ($blocks.ToArray() -join [Environment]::NewLine)
}

# TODO: Handle markdown footnotes.
