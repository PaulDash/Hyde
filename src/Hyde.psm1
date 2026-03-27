Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module powershell-yaml -ErrorAction Stop

$moduleRoot = Split-Path -Parent $PSCommandPath

. (Join-Path -Path $moduleRoot -ChildPath 'Private\HydeTypes.ps1')

Get-ChildItem -Path (Join-Path -Path $moduleRoot -ChildPath 'Private') -Filter '*.ps1' -Recurse |
    Where-Object { $_.Name -ne 'HydeTypes.ps1' } |
    Sort-Object FullName |
    ForEach-Object { . $_.FullName }

Get-ChildItem -Path (Join-Path -Path $moduleRoot -ChildPath 'Public') -Filter '*.ps1' -Recurse |
    Sort-Object FullName |
    ForEach-Object { . $_.FullName }

Export-ModuleMember -Function Invoke-HydeBuild, Invoke-HydeClean
