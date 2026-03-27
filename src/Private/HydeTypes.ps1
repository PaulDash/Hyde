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
    [hashtable]$FrontMatter
    [string]$RawContent
    [string]$RenderedContent
    [bool]$Published

    HydeDocument([string]$kind, [string]$sourcePath, [string]$relativePath) : base($kind, $sourcePath, $relativePath) {
        $this.FrontMatter = @{}
        $this.RawContent = ''
        $this.RenderedContent = ''
        $this.Published = $true
    }
}

class HydeStaticFile : HydeContentItem {
    HydeStaticFile([string]$sourcePath, [string]$relativePath) : base('StaticFile', $sourcePath, $relativePath) {
    }
}

class HydeBuildContext {
    [string]$Version
    [string]$Environment
    [hashtable]$Settings
    [hashtable]$Site
    [string]$SourcePath
    [string]$DestinationPath
    [System.Collections.ArrayList]$Documents
    [System.Collections.ArrayList]$StaticFiles

    HydeBuildContext() {
        $this.Settings = @{}
        $this.Site = @{}
        $this.Documents = New-Object System.Collections.ArrayList
        $this.StaticFiles = New-Object System.Collections.ArrayList
    }

    [void] AddDocument([HydeDocument]$document) {
        [void]$this.Documents.Add($document)
        [void]$this.Site.pages.Add($document)
    }

    [void] AddStaticFile([HydeStaticFile]$staticFile) {
        [void]$this.StaticFiles.Add($staticFile)
        [void]$this.Site.static_files.Add($staticFile)
    }
}
