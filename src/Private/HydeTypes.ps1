class HydeContentItem {
    [string]$Kind
    [string]$SourcePath
    [string]$RelativePath
    [string]$OutputRelativePath
    [string]$Url
    [string]$Name
    [string]$BaseName
    [string]$Extension

    HydeContentItem([string]$kind, [string]$sourcePath, [string]$relativePath) {
        # Every discovered site item starts with the same normalized file metadata.
        $this.Kind = $kind
        $this.SourcePath = $sourcePath
        $this.RelativePath = $relativePath.Replace('\', '/')
        $this.OutputRelativePath = $this.RelativePath
        $this.Name = [System.IO.Path]::GetFileName($sourcePath)
        $this.BaseName = [System.IO.Path]::GetFileNameWithoutExtension($sourcePath)
        $this.Extension = [System.IO.Path]::GetExtension($sourcePath).ToLowerInvariant()
        $this.Url = '/' + $this.OutputRelativePath.Replace('\', '/')
    }
}

class HydeDocument : HydeContentItem {
    [string]$CollectionName
    [hashtable]$FrontMatter
    [string]$RawContent
    [string]$RenderedContent
    [string]$Title
    [bool]$Published
    [bool]$WriteOutput
    [bool]$RenderWithLiquid
    [bool]$IsPrepared

    HydeDocument([string]$kind, [string]$sourcePath, [string]$relativePath) : base($kind, $sourcePath, $relativePath) {
        # Documents accumulate front matter, body content, and rendered output as the pipeline runs.
        $this.CollectionName = ''
        $this.FrontMatter = @{}
        $this.RawContent = ''
        $this.RenderedContent = ''
        $this.Title = ''
        $this.Published = $true
        $this.WriteOutput = $true
        $this.RenderWithLiquid = $true
        $this.IsPrepared = $false
    }
}

class HydeStaticFile : HydeContentItem {
    [hashtable]$Metadata

    HydeStaticFile([string]$sourcePath, [string]$relativePath) : base('StaticFile', $sourcePath, $relativePath) {
        # Static files can carry metadata supplied by front matter defaults.
        $this.Metadata = @{}
    }
}

class HydeBuildContext {
    [string]$Version
    [string]$Environment
    [hashtable]$Settings
    [hashtable]$Site
    [string]$SourcePath
    [string]$DestinationPath
    [hashtable]$PluginRegistry
    [hashtable]$LiquidRegistry
    [System.Collections.ArrayList]$Documents
    [System.Collections.ArrayList]$StaticFiles
    [System.Collections.ArrayList]$LoadedPlugins

    HydeBuildContext() {
        # The build context is the shared state bag for one Hyde invocation.
        $this.Settings = @{}
        $this.Site = @{}
        $this.PluginRegistry = @{}
        $this.LiquidRegistry = @{}
        $this.Documents = New-Object System.Collections.ArrayList
        $this.StaticFiles = New-Object System.Collections.ArrayList
        $this.LoadedPlugins = New-Object System.Collections.ArrayList
    }

    [void] AddDocument([HydeDocument]$document) {
        # Keep the strongly-typed list and the site variable surface in sync.
        [void]$this.Documents.Add($document)
        if ($document.Kind -eq 'Page') {
            [void]$this.Site.pages.Add($document)
            return
        }

        if ($document.Kind -eq 'CollectionDocument' -and -not [string]::IsNullOrWhiteSpace($document.CollectionName)) {
            [void]$this.Site.collections[$document.CollectionName].docs.Add($document)
            [void]$this.Site[$document.CollectionName].Add($document)
            if ($document.CollectionName -eq 'posts') {
                [void]$this.Site.posts.Add($document)
            }
        }
    }

    [void] AddStaticFile([HydeStaticFile]$staticFile) {
        # Keep the strongly-typed list and the site variable surface in sync.
        [void]$this.StaticFiles.Add($staticFile)
        [void]$this.Site.static_files.Add($staticFile)
    }
}
