#Requires -Version 5.1
#Requires -Modules powershell-yaml

<#PSScriptInfo
.VERSION 0.2.3
.GUID abebebd5-6f8f-4d36-b3c1-e6313b9eac6f
.AUTHOR Paul Wojcicki-Jarocki
.COPYRIGHT © 2026 Paul Dash
.LICENSEURI https://github.com/PaulDash/Hyde/raw/main/LICENSE
.PROJECTURI https://github.com/PaulDash/Hyde
.ICONURI https://github.com/PaulDash/Hyde/raw/main/res/Icon_32x32.png
.TAGS PowerShell static-site-generator jekyll markdown yaml
.RELEASENOTES Added manifest-based module entry, exported Hyde command, collection permalinks, module-first command routing, lower-camel-case private helper names, moved command help onto the module surface, and simplified the wrapper script.
#>

[CmdletBinding()]
param(
    # Keep the wrapper permissive and let the module command perform command-specific validation.
    [Parameter(Position = 0)]
    [string]$Command,
    [string]$Source,
    [string]$Destination,
    [string]$Environment,
    [switch]$Quiet
)

begin {
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Load the module manifest so the module can act as the real entry point.
$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'Hyde.psd1'

# Reuse an existing Hyde module instance in the current session.
$loadedHydeModule = Get-Module |
    Where-Object {
        $_.Path -and $_.Path.Equals($modulePath, [System.StringComparison]::OrdinalIgnoreCase)
    } |
    Select-Object -First 1

if (-not $loadedHydeModule) {
    Import-Module $modulePath
}

# Forward the parsed wrapper arguments to the module command so the module remains the primary surface area.
$commandParameters = @{}
if ($PSBoundParameters.ContainsKey('Command')) {
    $commandParameters['Command'] = $Command
}

if ($PSBoundParameters.ContainsKey('Source')) {
    $commandParameters['Source'] = $Source
}

if ($PSBoundParameters.ContainsKey('Destination')) {
    $commandParameters['Destination'] = $Destination
}

if ($PSBoundParameters.ContainsKey('Environment')) {
    $commandParameters['Environment'] = $Environment
}

if ($PSBoundParameters.ContainsKey('Quiet')) {
    $commandParameters['Quiet'] = $Quiet
}

if ($VerbosePreference -eq 'Continue') {
    Hyde @commandParameters -Verbose
} else {
    Hyde @commandParameters
}
}

# TODO: Implement `New` site scaffolding
# TODO: Add posts
# TODO: implement Layout inheritance by pre-parsing files in _layouts
