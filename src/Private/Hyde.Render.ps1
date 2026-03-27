function Read-HydeFrontMatter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document,

        [switch]$Strict
    )

    # Read the full source file so we can split the front matter block from the body in one pass.
    $rawFileContent = Get-Content -LiteralPath $Document.SourcePath -Raw
    $Document.FrontMatter = @{}

    if ($rawFileContent.StartsWith("---")) {
        # Match the opening and closing YAML fence at the start of the file.
        $match = [System.Text.RegularExpressions.Regex]::Match(
            $rawFileContent,
            '\A---\s*\r?\n(.*?)\r?\n---\s*(?:\r?\n|$)',
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )

        if (-not $match.Success) {
            throw "Front matter in '$($Document.SourcePath)' is not properly terminated."
        }

        $yamlText = $match.Groups[1].Value
        if (-not [string]::IsNullOrWhiteSpace($yamlText)) {
            try {
                $Document.FrontMatter = ConvertTo-HydeHashtable -InputObject (ConvertFrom-Yaml -Yaml $yamlText)
            } catch {
                throw "Could not parse front matter in '$($Document.SourcePath)'. $($_.Exception.Message)"
            }
        }

        $Document.RawContent = $rawFileContent.Substring($match.Length)
    } else {
        if ($Strict) {
            throw "Strict front matter is enabled but '$($Document.SourcePath)' does not start with front matter."
        }

        $Document.RawContent = $rawFileContent
    }

    # Hyde honors the published flag early so later stages can skip output generation.
    if ($Document.FrontMatter.ContainsKey('published')) {
        $Document.Published = [bool]$Document.FrontMatter.published
    }
}

function Convert-HydeInlineMarkdown {
    [CmdletBinding()]
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

function Convert-HydeMarkdown {
    [CmdletBinding()]
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
    function Flush-HydeParagraph {
        if ($paragraphLines.Count -eq 0) {
            return
        }

        $text = ($paragraphLines.ToArray() -join ' ').Trim()
        [void]$blocks.Add("<p>$(Convert-HydeInlineMarkdown -Text $text)</p>")
        $paragraphLines.Clear()
    }

    function Flush-HydeList {
        if ($listItems.Count -eq 0) {
            return
        }

        $items = $listItems.ToArray() | ForEach-Object {
            "<li>$(Convert-HydeInlineMarkdown -Text $_)</li>"
        }

        [void]$blocks.Add("<ul>$($items -join '')</ul>")
        $listItems.Clear()
    }

    function Flush-HydeCodeFence {
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
                Flush-HydeCodeFence
                $inCodeFence = $false
            } else {
                Flush-HydeParagraph
                Flush-HydeList
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
            Flush-HydeParagraph
            Flush-HydeList
            continue
        }

        if ($line -match '^(#{1,6})\s+(.*)$') {
            Flush-HydeParagraph
            Flush-HydeList
            $level = $Matches[1].Length
            $headingText = Convert-HydeInlineMarkdown -Text $Matches[2].Trim()
            [void]$blocks.Add("<h$level>$headingText</h$level>")
            continue
        }

        if ($line -match '^\s*[-*+]\s+(.*)$') {
            Flush-HydeParagraph
            [void]$listItems.Add($Matches[1].Trim())
            continue
        }

        # Raw HTML blocks pass straight through instead of being escaped as markdown paragraphs.
        if ($line.TrimStart().StartsWith('<')) {
            Flush-HydeParagraph
            Flush-HydeList
            [void]$blocks.Add($line)
            continue
        }

        [void]$paragraphLines.Add($line.Trim())
    }

    if ($inCodeFence) {
        Flush-HydeCodeFence
    } else {
        Flush-HydeParagraph
        Flush-HydeList
    }

    return ($blocks.ToArray() -join [Environment]::NewLine)
}

function Convert-HydeDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document,

        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    # Rendering starts by parsing front matter, then selecting the renderer by file extension.
    $strictFrontMatter = $false
    if ($Context.Settings.ContainsKey('strict_front_matter')) {
        $strictFrontMatter = [bool]$Context.Settings.strict_front_matter
    }

    Read-HydeFrontMatter -Document $Document -Strict:$strictFrontMatter

    if (-not $Document.Published) {
        return
    }

    $markdownExtensions = Get-HydeMarkdownExtensions -Settings $Context.Settings
    if ($Document.Extension -in @('.htm', '.html')) {
        # HTML pages are currently copied through after front matter is stripped.
        $Document.RenderedContent = $Document.RawContent
        return
    }

    if ($Document.Extension -in $markdownExtensions) {
        # Markdown pages are converted into HTML before being written to disk.
        $Document.RenderedContent = Convert-HydeMarkdown -Markdown $Document.RawContent
        return
    }

    throw "No renderer exists for '$($Document.SourcePath)'."
}

function Resolve-HydeDocumentOutputPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document,

        [Parameter(Mandatory = $true)]
        [hashtable]$Settings
    )

    # Markdown sources render to .html while html inputs keep their existing filenames.
    $markdownExtensions = Get-HydeMarkdownExtensions -Settings $Settings
    if ($Document.Extension -in $markdownExtensions) {
        return [System.IO.Path]::ChangeExtension($Document.RelativePath, '.html').Replace('\', '/')
    }

    return $Document.RelativePath.Replace('\', '/')
}

function Write-HydeDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeDocument]$Document,

        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    if (-not $Document.Published) {
        return
    }

    # Materialize the destination tree lazily as each document is written.
    $destinationPath = Join-Path -Path $Context.DestinationPath -ChildPath $Document.OutputRelativePath
    $destinationDirectory = Split-Path -Path $destinationPath -Parent

    if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
        [void](New-Item -Path $destinationDirectory -ItemType Directory -Force)
    }

    Set-Content -LiteralPath $destinationPath -Value $Document.RenderedContent -Encoding UTF8
}

function Copy-HydeStaticFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [HydeStaticFile]$StaticFile,

        [Parameter(Mandatory = $true)]
        [HydeBuildContext]$Context
    )

    # Static files reuse the same output tree logic but skip the rendering step entirely.
    $destinationPath = Join-Path -Path $Context.DestinationPath -ChildPath $StaticFile.OutputRelativePath
    $destinationDirectory = Split-Path -Path $destinationPath -Parent

    if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
        [void](New-Item -Path $destinationDirectory -ItemType Directory -Force)
    }

    Copy-Item -LiteralPath $StaticFile.SourcePath -Destination $destinationPath -Force
}
