#Requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Import-Module Pester -MinimumVersion 5.0.0 -ErrorAction Stop

$configuration = New-PesterConfiguration
$configuration.Run.Path = @(
    (Join-Path -Path $PSScriptRoot -ChildPath 'Hyde.Liquid.Tests.ps1')
    (Join-Path -Path $PSScriptRoot -ChildPath 'Hyde.Build.Tests.ps1')
    (Join-Path -Path $PSScriptRoot -ChildPath 'Hyde.Clean.Tests.ps1')
    (Join-Path -Path $PSScriptRoot -ChildPath 'Hyde.Doctor.Tests.ps1')
    (Join-Path -Path $PSScriptRoot -ChildPath 'Hyde.Script.Tests.ps1')
)
$configuration.Output.Verbosity = 'Detailed'
# Keep filesystem isolation enabled, but disable TestRegistry
# because Codex sandbox blocks registry writes.
$configuration.TestDrive.Enabled = $true
$configuration.TestRegistry.Enabled = $false

Invoke-Pester -Configuration $configuration
