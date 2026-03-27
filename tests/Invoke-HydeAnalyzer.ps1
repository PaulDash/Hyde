#Requires -Version 5.1
#Requires -Modules PSScriptAnalyzer

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Resolve the repository root once so the analyzer can scan every PowerShell source file in src.
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourceRoot = Join-Path -Path $projectRoot -ChildPath 'src'
$analyzerTargets = @(
    Get-ChildItem -Path $sourceRoot -Recurse -Include '*.ps1', '*.psm1' -File |
        Select-Object -ExpandProperty FullName
)

Import-Module PSScriptAnalyzer -ErrorAction Stop

# Analyze each file individually so the script stays compatible with Invoke-ScriptAnalyzer's Path parameter.
$results = foreach ($analyzerTarget in $analyzerTargets) {
    Invoke-ScriptAnalyzer -Path $analyzerTarget -ErrorAction Stop
}

if ($results.Count -eq 0) {
    Write-Host 'PSScriptAnalyzer found no issues.'
    return
}

$results |
    Sort-Object ScriptPath, Line, RuleName |
    Format-Table RuleName, Severity, ScriptName, Line, Message -AutoSize

throw "PSScriptAnalyzer found $($results.Count) issue(s)."
