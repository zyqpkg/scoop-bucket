# Regenerates README.md from bucket manifests. Used by .github/workflows/checkver.yml.
# Usage: pwsh .github\scripts\update-readme.ps1
param(
    [string]$BucketDir = (Join-Path $PSScriptRoot '..' '..' 'bucket'),
    [string]$OutputPath = (Join-Path $PSScriptRoot '..' '..' 'README.md')
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

# One-pass map of last commit date per bucket manifest (git log is newest-first).
$dateMap = @{}
$currentDate = $null
git -C $repoRoot log --format='%ad' --date=short --name-only -- bucket/ | ForEach-Object {
    if ($_ -match '^\d{4}-\d{2}-\d{2}$') {
        $currentDate = $_
    }
    elseif ($_ -match '^bucket/(?<name>.+)$' -and $currentDate -and -not $dateMap.ContainsKey($Matches['name'])) {
        $dateMap[$Matches['name']] = $currentDate
    }
}
$today = Get-Date -Format 'yyyy-MM-dd'

$appData = Get-ChildItem -Path $BucketDir -Filter '*.json' | ForEach-Object {
    $manifest = Get-Content $_.FullName -Raw | ConvertFrom-Json

    $desc = if ($manifest.description) { $manifest.description -replace '\|', '\|' } else { '' }
    if ($desc.Length -gt 60) { $desc = $desc.Substring(0, 57) + '...' }

    $homepage = if ($manifest.homepage) { $manifest.homepage } else { '' }
    if ($homepage) {
        try {
            $homepageLabel = ([uri]$homepage).Host -replace '^www\.', ''
        } catch {
            $homepageLabel = $homepage
        }
    } else {
        $homepageLabel = ''
    }

    $lastUpdated = if ($dateMap.ContainsKey($_.Name)) { $dateMap[$_.Name] } else { $today }

    [PSCustomObject]@{
        App           = $_.BaseName
        Name          = $_.Name
        Desc          = $desc
        Version       = $manifest.version
        Homepage      = $homepage
        HomepageLabel = $homepageLabel
        LastUpdated   = $lastUpdated
    }
}

$rows = $appData | Sort-Object -Property @{ Expression = 'LastUpdated'; Descending = $true }, @{ Expression = 'App' } | ForEach-Object {
    "| [$($_.App)](bucket/$($_.Name)) | $($_.Desc) | $($_.Version) | [$($_.HomepageLabel)]($($_.Homepage)) | $($_.LastUpdated) |"
}
$table = $rows -join "`n"

$readme = @"
# zyqpkg scoop bucket

A personal [Scoop](https://scoop.sh/) bucket for Windows apps not available in official buckets.

## Add this bucket

``````powershell
scoop bucket add zyqpkg https://github.com/zyqpkg/scoop-bucket
``````

## Install an app

``````powershell
scoop install zyqpkg/<app-name>
``````

## Apps

| App | Description | Version | Homepage | Last Updated |
|-----|-------------|---------|----------|--------------|
$table
"@

Set-Content -Path $OutputPath -Value $readme -Encoding UTF8
