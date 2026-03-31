#!/usr/bin/env pwsh

# Test that libsass-converter works without Test-LibSassPartial scope errors
Import-Module .\src\Hyde.psd1

$testSite = Join-Path $env:TEMP 'hyde-test-libsass'
$testDest = Join-Path $env:TEMP 'hyde-test-libsass-out'

if (Test-Path $testSite) { Remove-Item $testSite -Recurse -Force }
if (Test-Path $testDest) { Remove-Item $testDest -Recurse -Force }

Write-Host "Creating test site at $testSite..."
[void](New-Item $testSite -ItemType Directory)
[void](New-Item (Join-Path $testSite 'assets') -ItemType Directory)

# Create config without explicit plugins (should not load libsass)
Set-Content (Join-Path $testSite '_config.yml') 'title: Test Site'
Set-Content (Join-Path $testSite 'index.md') @'
---
title: Home
---
# Hello World
'@
Set-Content (Join-Path $testSite 'assets\test.scss') @'
$color: blue;
body { color: $color; }
'@

Write-Host "Running build without libsass plugin configured..."
try {
    Publish-StaticSite -Source $testSite -Destination "$testDest-1" -Environment development
    Write-Host "✓ Build succeeded without libsass plugin"
    $scssFile = Get-Item "$testDest-1\assets\test.scss" -ErrorAction SilentlyContinue
    if ($scssFile) {
        Write-Host "✓ SCSS file copied as-is (plugin not loaded)"
    }
}
catch {
    Write-Host "✗ Build failed: $_"
    exit 1
}

# Now create a site with libsass configured
Write-Host "`nCreating test site with libsass plugin..."
if (Test-Path $testSite) { Remove-Item $testSite -Recurse -Force }
[void](New-Item $testSite -ItemType Directory)
[void](New-Item (Join-Path $testSite 'assets') -ItemType Directory)

Set-Content (Join-Path $testSite '_config.yml') @'
title: Test Site
plugins:
  - libsass-converter
'@
Set-Content (Join-Path $testSite 'index.md') @'
---
title: Home
---
# Hello World
'@
Set-Content (Join-Path $testSite 'assets\main.scss') @'
$color: #333;
body { color: $color; }
'@
Set-Content (Join-Path $testSite 'assets\_partial.scss') @'
$font-size: 14px;
'@

Write-Host "Running build with libsass plugin configured..."
try {
    Publish-StaticSite -Source $testSite -Destination "$testDest-2" -Environment development -Verbose *>&1 | Where-Object { $_ -match 'libsass|VERBOSE|error|Error' }

    # Verify outputs
    $cssFile = Get-Item "$testDest-2\assets\main.css" -ErrorAction SilentlyContinue
    $scssFile = Get-Item "$testDest-2\assets\main.scss" -ErrorAction SilentlyContinue
    $partialFile = Get-Item "$testDest-2\assets\_partial.scss" -ErrorAction SilentlyContinue

    if ($cssFile) {
        Write-Host "✓ SCSS compiled to CSS"
        $content = Get-Content $cssFile.FullName -Raw
        if ($content -match 'body') {
            Write-Host "✓ Compiled CSS has expected content"
        }
    } else {
        Write-Host "✗ CSS file not found"
        exit 1
    }

    if ($scssFile) {
        Write-Host "✗ Original SCSS file should not exist (CancelCopy)"
        exit 1
    } else {
        Write-Host "✓ Original SCSS file was not copied (CancelCopy worked)"
    }

    if ($partialFile) {
        Write-Host "✗ Partial file should not exist"
        exit 1
    } else {
        Write-Host "✓ Partial file was not emitted"
    }
}
catch {
    if ($_ -match 'Test-LibSassPartial') {
        Write-Host "✗ Test-LibSassPartial scope error found!"
        exit 1
    }
    Write-Host "✗ Build failed: $_"
    exit 1
}

Write-Host "`n✓ All tests passed!"
