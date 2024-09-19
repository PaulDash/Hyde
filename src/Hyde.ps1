#Requires -Version 5.1
#Requires -Modules powershell-yaml

<#PSScriptInfo
.VERSION 0.0.1.2
.GUID abebebd5-6f8f-4d36-b3c1-e6313b9eac6f
.AUTHOR Paul Dash
.COPYRIGHT © 2024 Paul Dash
.LICENSEURI https://github.com/PaulDash/Hyde/raw/main/LICENSE
.PROJECTURI https://github.com/PaulDash/Hyde
.ICONURI https://github.com/PaulDash/Hyde/raw/main/res/Icon_32x32.png
#>

<#
.SYNOPSIS
PowerShell static site generator. The ugly Mr. Hyde to the popular Jekyll.
.DESCRIPTION
PowerShell static site generator. Created as a fun project to only generate my own private webpage, but useful as an example when teaching about PowerShell.
#>

################################################################################
# Hi, I'm Mr. Hyde, the ugly PowerShell face of the smart Ruby-based Dr. Jekyll.

[CmdletBinding()]
param(
    # Chooses main action to run during this invocation.
    [Parameter(Position=0)]
    [ValidateSet("New","Build","Clean","Help")]
    [string]$Command,

    # Root location for files to be read.
    [string]$Source,

    # Location where generated site will be written.
    [string]$Destination,
    
    # Value referenced in files during build process.
    [Parameter(ParameterSetName='Build')]
    [alias('JEKYLL_ENV','HYDE_ENV')]
    [string]$Environment = 'development',

    [switch]$Quiet

)

Set-StrictMode -Version 'latest'
$ErrorActionPreference = 'Stop'

# Consider output mode quiet / normal / verbose
if ($PSBoundParameters.ContainsKey('Quiet') -and $VerbosePreference -eq 'Continue') {
    throw "It doesn't make sense to ask for verbose output AND to keep quiet!"
} elseif (-not $Quiet) {
    $InformationPreference = 'Continue'
}

# Process command and decide what to do
switch ($Command) {
    'New'   { "This will create a new site scaffold."; throw "Not implemented yet!" }
    'Build' { }
    'Clean' { "This will remove all generated files."; throw "Not implemented yet!" }
    'Help'  { Get-Help -Name $PSCommandPath}
    Default { throw "Nothing else is implemented yet!"; exit }
}

#region Helper Functions
function GetFullFilePath {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Location,
        # Used for checking validity of location that is yet to be created.
        [switch]$MayNotExist
    )
    try {
        if (Test-Path $Location -PathType Container) {
            # We know it's there
            $Path = (Get-Item $Location).ResolvedTarget
            Write-Verbose "Able to find existing directory at '$Path'."
        } elseif ($MayNotExist -and (Test-Path $Location -PathType Container -IsValid)) {
            # At least it's path is valid
            $Path = Join-Path (Get-Item (Split-Path $Location)).ResolvedTarget (Split-Path $Location -Leaf)
            Write-Verbose "Able to validate location for '$Path'."
        } else {
            throw "Could not validate path for '$Location'."
        }
    } catch {
        throw "Could not resolve target path of '$Location'."
    }

    return $Path
}

function ReadConfigurationFile {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    try {
        if (Test-Path $Path -PathType Leaf) {
            $Content = Get-Content $Path | ConvertFrom-Yaml
            Write-Verbose "Loaded $($Content.count) settings from '$Path'."
            return $Content
        } else {
            throw "Could not validate location of configuration file '$Path'!"
        }
    } catch {
        throw "Could not parse configuration file '$Path'!"
    }
}

function MergeConfiguration {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$Existing,
        [Parameter(Mandatory=$true)]
        [hashtable]$Difference
    )

    foreach ($Key in $Difference.Keys) {
        if ($Existing.ContainsKey($Key)) {
            if ($Existing[$Key] -is [hashtable] -and $Difference[$Key] -is [hashtable]) {
                # Recurse to properly handle data structures
                MergeConfiguration $Existing[$Key] $Difference[$Key]
            } else {
                $Existing[$Key] = $Difference[$Key]
            }
        } else {
            $Existing.Add($Key, $Difference[$Key])
        }
    }

    # No need to return $Existing
    # as $Existing [hashtable] is sent by reference
}

#endregion

# Set application level and site variables.
#region Configure Variables

# Internally defined variables
$HYDE_CONFIGURATION_FILENAME = 'globalConfig.yaml'
$SITE_CONFIGURATION_FILENAME = '_config.yml'
$DATA_FILES_LOCATION         = '/_data'
$SUPPORTED_DATA_FILES        = '*.yml', '*.yaml' #, '*.json', '*.tsv', '*.csv'
$SUPPORTED_CONTENT_FILES     = '*.htm', '*.html' ,'*.markdown', '*.md', '*.textile'
$EXCLUDED_NAMES              = '.*', '_*', '#*', '~*'

# TODO: maybe load environment value from $ENV:JEKYLL_ENV
$hyde = @{'version' = ((Get-PSScriptFileInfo $PSCommandPath).ScriptMetadataComment.Version.Version.ToString());
          'environment' = $Environment
        }

Write-Information "Running HYDE version $($hyde.version)."
Write-Verbose     "Proceeding with command '$Command'."

# Parse global configuration file
# as per https://jekyllrb.com/docs/configuration/default/
$Settings = ReadConfigurationFile -Path (Join-Path (Split-Path $PSCommandPath) $HYDE_CONFIGURATION_FILENAME)

# Override some settings based on command parameters
if ($PSBoundParameters.ContainsKey('Source')) {
    $Settings.source = $Source }
if ($PSBoundParameters.ContainsKey('Destination')) {
    $Settings.destination = $Destination }

# Set actual paths being used by commands
$SourcePath      = GetFullFilePath -Location $Settings.source
$DestinationPath = GetFullFilePath -Location $Settings.destination -MayNotExist

Remove-Variable -Name Source, Destination

# Parse _config.yml in project's root
# site defaults and overwrite Settings
$site = ReadConfigurationFile -Path (Join-Path $SourcePath -ChildPath $SITE_CONFIGURATION_FILENAME)

# TODO: add support for multiple configuration files
#MergeConfiguration -Existing $site -Difference $anotherSiteConfiguration

# Read settings from "Data Files"
if (Test-Path (Join-Path $SourcePath $DATA_FILES_LOCATION) -PathType Container) {
    $DataFiles = Get-ChildItem -Path (Join-Path $SourcePath $DATA_FILES_LOCATION '\*') -Include $SUPPORTED_DATA_FILES
    if (-not $site.ContainsKey('data')) {
        $site.Add('data', @{})
    }
    Write-Verbose "Found $($DataFiles.Count) data files."
    foreach ($DataFile in $DataFiles) {
        $DataConfigurationName = $DataFile.BaseName
        switch -Regex ($DataFile.Extension) {
            "y(a)?ml" { $DataConfiguration = ReadConfigurationFile -Path $DataFile }
            Default   { throw "Data File format for '$DataFile' is not supported." }
        }
        if (-not $site.data.ContainsKey($DataConfigurationName)) {
            if ($DataConfiguration -is [hashtable]) {
                # child object needs to be a [hashtable]
                $site.data.Add($DataConfigurationName, @{})
                MergeConfiguration -Existing $site.data.$DataConfigurationName -Difference $DataConfiguration 
            } elseif ($DataConfiguration -is [array]) {
                # child object needs to be an [array]
                $site.data.Add($DataConfigurationName, @())
                $site.data.$DataConfigurationName += $DataConfiguration
            }
        }
        Write-Verbose "Merged configuration from '$DataFile'."
    }
}

# TODO
################################################################################
# Read in theme info into ThemeVariables
################################################################################

# TODO
################################################################################
# Read in "Front Matter Defaults" from $site.defaults
# respecting the scope defined there, including path and
# currently only supporting "pages" type
################################################################################

#endregion

#region Enumerate Files

# Add runtime-generated values
$site.Add('time',  (Get-Date))
$site.Add('pages', (New-Object System.Collections.ArrayList))
$site.Add('posts', (New-Object System.Collections.ArrayList))
$site.Add('static_files', (New-Object System.Collections.ArrayList))


# Add names with extensions to exclusion list
foreach ($Exclusion in $EXCLUDED_NAMES) {
    $EXCLUDED_NAMES += "$Exclusion.*"
}
# Use this list specifically for directories
$ExcludedDirectories = $EXCLUDED_NAMES
# Build excluded directories list from Site Variables
if ($site.ContainsKey('exclude')) {
    foreach ($Exclusion in $site.exclude) {
        if ($Exclusion.StartsWith('/')) {
            $ExcludedDirectories += $Exclusion.TrimStart('/')
        }
    }
    Write-Verbose "Added directory exclusions from site configuration."
}

$ContentDirectories = @(Get-Item -Path $SourcePath)
$ContentDirectories += Get-ChildItem -Path $SourcePath -Recurse -Directory -Exclude $ExcludedDirectories
# TODO: add directories explicitly listed in site configuration

Write-Information "Starting to process $($ContentDirectories.count) site directories..."

# Use this list specifically for files
$ExcludedFiles = $EXCLUDED_NAMES
# Build excluded files list from Site Variables
if ($site.ContainsKey('exclude')) {
    foreach ($Exclusion in $site.exclude) {
        if (-not $Exclusion.StartsWith('/')) {
            $ExcludedFiles += $Exclusion
        }
    }
    Write-Verbose "Added file exclusions from site configuration."
}

foreach ($Directory in $ContentDirectories) {

    # Same directory needs to be created at Destination
    $ComputedDirectoryPath = [System.IO.Path]::GetRelativePath($SourcePath, $Directory)
    New-Item -Path (Join-Path $DestinationPath $ComputedDirectoryPath) -ItemType Directory > $null

    $ContentFiles = Get-ChildItem -Path "$Directory\*" -File -Exclude $ExcludedFiles
    # TODO: add files explicitly listed in site configuration

    foreach ($File in $ContentFiles) {
        if ($File.Extension -in $SUPPORTED_CONTENT_FILES.TrimStart('*')) {
            # add file to PAGES list
            $site.pages.Add($File) > $null
        } else {
            # add file to Static Files list
            $ComputedPath = [System.IO.Path]::GetRelativePath($SourcePath, $File.FullName)
            $StaticFileMetadata = @{'path' = '/' + $ComputedPath.Replace('\','/');
                                    'modified_time' = $File.LastWriteTime;
                                    'name'     = $File.Name;
                                    'basename' = $File.BaseName;
                                    'extname'  = $File.Extension }
            $site.static_files.Add($StaticFileMetadata) > $null
            
            # TODO: add properties from "Front Matter Defaults"

            # Perform file copy
            # TODO: refactor Static File operations into own function
            Copy-Item -Path $File -Destination (Join-Path $DestinationPath $ComputedPath) -Force
        }
    }
}

#endregion


# loop through PAGES

# loop through POSTS in _posts directory
    
    # Read "Front Matter" defaults from cache

    # read "Front Matter" YAML and
    # save to PageVariables hash table
    # if not defined, this is a "Static File", just copy over

    # check if file is to be "published"
    # if not, don't process
    # TODO: add support for "unpublished" pages

    # Add runtime-generated values
 #   $page.lastmodifieddate = Get-ChildItem $File.LastWriteTime

    # consider "Includes" from _includes directory

    # read "Layout"
    # TODO: implement Layout inheritance by pre-parsing files in _layouts

    # for processing, superimpose PageVariables on Settings

    # create output file at same location or
    # one defined in "permalink"
    # which has "Placeholders" to modify the location through variables

Write-Information "Finished in $(((Get-Date) - $site.time).Seconds) seconds."