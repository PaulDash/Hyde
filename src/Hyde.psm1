Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module powershell-yaml -ErrorAction Stop
Import-Module (Join-Path -Path (Split-Path -Parent $PSCommandPath) -ChildPath 'Liquid\Hyde.Liquid.psm1')

$moduleRoot = Split-Path -Parent $PSCommandPath

# Load PowerShell classes first so the remaining scripts can reference them.
. (Join-Path -Path $moduleRoot -ChildPath 'Private\HydeTypes.ps1')

# Dot-source private helpers before public commands so exported functions have all dependencies available.
Get-ChildItem -Path (Join-Path -Path $moduleRoot -ChildPath 'Private') -Filter '*.ps1' -Recurse |
    Where-Object { $_.Name -ne 'HydeTypes.ps1' } |
    Sort-Object FullName |
    ForEach-Object { . $_.FullName }

# Dot-source public entry points last, then export only the supported surface area.
Get-ChildItem -Path (Join-Path -Path $moduleRoot -ChildPath 'Public') -Filter '*.ps1' -Recurse |
    Sort-Object FullName |
    ForEach-Object { . $_.FullName }

Export-ModuleMember -Function Publish-StaticSite, Clear-StaticSite, Test-StaticSite
