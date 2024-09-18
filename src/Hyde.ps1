#Requires -Version 5.1
#Requires -Modules powershell-yaml

<#PSScriptInfo
.VERSION 0.0.1
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
    [string]$Source = '.',

    # Location where generated site will be written.
    [string]$Destination = './_site',
    
    # Value referenced in files during build process.
    [Parameter(ParameterSetName='Build')]
    [alias('JEKYLL_ENV','HYDE_ENV')]
    [string]$Environment = 'development'

)

Set-StrictMode -Version 'latest' 

# TODO: refactor into module with individual commands

# process command and decide what to do
switch ($Command) {
    'New'   { "This will create a new site scaffold."; throw "Not implemented yet!" }
    'Build' { "Building your site..."}
    'Clean' { "This will remove all generated files."; throw "Not implemented yet!" }
    'Help'  { Get-Help -Name $PSCommandPath}
    Default { throw "Nothing else is implemented yet!"; exit }
}

# Set application level and site variables.
#region Variables

$HYDE_CONFIGURATION_FILENAME = 'globalConfig.yaml'

# TODO: maybe load environment value from $ENV:JEKYLL_ENV
$hyde = @{'version' = ((Get-PSScriptFileInfo $PSCommandPath).ScriptMetadataComment.Version.Version.ToString());
          'environment' = $Environment
        }
$jekyll = $hyde

# Parse global configuration file
# as per https://jekyllrb.com/docs/configuration/default/
try {
    $hydeConfigurationFilePath = Join-Path -Path (Split-Path $PSCommandPath) -ChildPath $HYDE_CONFIGURATION_FILENAME
    if (Test-Path $hydeConfigurationFilePath -PathType Leaf -ErrorAction Stop) {
        $GlobalVariables = Get-Content $hydeConfigurationFilePath -ErrorAction Stop |
                           ConvertFrom-Yaml -ErrorAction Stop
    } else {
        throw "Could not validate location of global configuration file!"
    }
} catch {
    throw "Could not parse global configuration file!"
}
# Override some settings based on command input
$GlobalVariables.source = $Source
$GlobalVariables.destination = $Destination
# Check that source is valid and exists
try {
    if (Test-Path $Source -PathType Container) {
        $SourcePath = (Get-Item $Source).ResolvedTarget
    } else {
        throw "Could not validate source path '$Source'."
    }
} catch {
    throw "Could not resolve target of source path '$Source'."
}
# Check that destination is valid and its parent exists
try {
    if (Test-Path $Destination -PathType Container -IsValid) {
        $DestinationPath = Join-Path (Get-Item (Split-Path $Destination)).ResolvedTarget (Split-Path $Destination -Leaf)
    } else {
        throw "Could not validate destination path '$Destination'."
    }
} catch {
    throw "Could not resolve target of source path '$Destination'."
}




# parse _config.yml in project's root to read
# site defaults and overwrite GlobalVariables

#endregion


# read in theme info into ThemeVariables

# TODO: add support for "Collections"

# loop through files
    # check if file is to be "published"
    # if not, don't process
    # TODO: add support for "unpublished" pages

    # read "Front Matter" YAML and
    # save to PageVariables hash table
    # if not defined, this is a "Static File" 

    # consider "Includes" from _includes directory


    # read "Layout"
    # TODO: implement Layout inheritance by pre-parsing files in _layouts

    # for processing, superimpose PageVariables on GlobalVariables

    # create output file at same location or
    # one defined in "permalink"
    # which has "Placeholders" to modify the location through variables
