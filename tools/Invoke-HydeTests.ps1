#Requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Import-Module Pester -MinimumVersion 5.0.0 -ErrorAction Stop

$projectRoot = Split-Path -Path $PSScriptRoot -Parent
$testsRoot = Join-Path -Path $projectRoot -ChildPath 'tests'
if (-not (Test-Path -LiteralPath $testsRoot -PathType Container)) {
    throw "Could not locate test directory at '$testsRoot'."
}

$testPaths = @(Get-ChildItem -LiteralPath $testsRoot -Filter '*.Tests.ps1' -File | Sort-Object -Property Name | Select-Object -ExpandProperty FullName)
if ($testPaths.Count -eq 0) {
    throw "No Pester test files (*.Tests.ps1) were found in '$testsRoot'."
}

$configuration = New-PesterConfiguration
$configuration.Run.Path = $testPaths
$configuration.Output.Verbosity = 'Detailed'
# Keep filesystem isolation enabled, but disable TestRegistry
# because Codex sandbox blocks registry writes.
$configuration.TestDrive.Enabled = $true
$configuration.TestRegistry.Enabled = $false

Invoke-Pester -Configuration $configuration
