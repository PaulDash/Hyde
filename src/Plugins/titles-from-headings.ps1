param($Context)

# This built-in plugin fills missing page titles from the first Markdown H1 heading.
@{
    Name = 'titles-from-headings'
    Hooks = @{
        BeforeRenderDocument = {
            param($Invocation)

            $document = $Invocation.Document
            if ($null -eq $document) {
                return
            }

            if (-not [string]::IsNullOrWhiteSpace($document.Title)) {
                return
            }

            $markdownExtensions = getHydeMarkdownExtensions -Settings $Invocation.Context.Settings
            if ($document.Extension -notin $markdownExtensions) {
                return
            }

            $match = [System.Text.RegularExpressions.Regex]::Match(
                $document.RawContent,
                '(?m)^\s*#\s+(.+?)\s*$'
            )

            if (-not $match.Success) {
                return
            }

            # Pull a semantic title from the first Markdown heading and trim a few common inline markdown markers.
            $resolvedTitle = $match.Groups[1].Value.Trim()
            $resolvedTitle = $resolvedTitle -replace '\s+#+\s*$', ''
            $resolvedTitle = $resolvedTitle -replace '\[([^\]]+)\]\([^)]+\)', '$1'
            $resolvedTitle = $resolvedTitle -replace '`([^`]+)`', '$1'
            $resolvedTitle = $resolvedTitle -replace '\*\*([^\*]+)\*\*', '$1'
            $resolvedTitle = $resolvedTitle -replace '__([^_]+)__', '$1'
            $resolvedTitle = $resolvedTitle -replace '(?<!\*)\*([^\*]+)\*(?!\*)', '$1'
            $resolvedTitle = $resolvedTitle -replace '(?<!_)_([^_]+)_(?!_)', '$1'
            $resolvedTitle = $resolvedTitle.Trim()
            if ([string]::IsNullOrWhiteSpace($resolvedTitle)) {
                return
            }

            # Store the title semantically and mirror it into front matter so existing page.title consumers see it.
            $document.Title = $resolvedTitle
            $document.FrontMatter['title'] = $resolvedTitle
        }
    }
}
