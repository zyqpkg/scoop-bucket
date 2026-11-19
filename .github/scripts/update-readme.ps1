# Regenerates README.md from bucket manifests. Used by .github/workflows/checkver.yml.
# Usage: pwsh .github/scripts/update-readme.ps1
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

function Get-DisplayWidth([string]$text) {
    $width = 0
    foreach ($char in $text.ToCharArray()) {
        if ([int]$char -gt 127) { $width += 2 } else { $width += 1 }
    }
    return $width
}

function Truncate-Display([string]$text, [int]$maxWidth) {
    if ([string]::IsNullOrEmpty($text)) { return '' }
    if ((Get-DisplayWidth $text) -le $maxWidth) { return $text }
    $currentWidth = 0
    $sb = [System.Text.StringBuilder]::new()
    foreach ($char in $text.ToCharArray()) {
        $charWidth = if ([int]$char -gt 127) { 2 } else { 1 }
        if ($currentWidth + $charWidth + 3 -gt $maxWidth) {
            $sb.Append('...') | Out-Null
            break
        }
        $sb.Append($char) | Out-Null
        $currentWidth += $charWidth
    }
    return $sb.ToString()
}

$appData = Get-ChildItem -Path $BucketDir -Filter '*.json' | ForEach-Object {
    $manifest = Get-Content $_.FullName -Raw | ConvertFrom-Json

    # 转义或清洗破坏表格结构的管道符与换行符，并按显示宽度对齐截断
    $desc = if ($manifest.description) {
        $clean = $manifest.description -replace '\|', '&#124;' -replace '[\r\n]+', ' '
        Truncate-Display $clean.Trim() 50
    } else { '' }

    $homepage = if ($manifest.homepage) { $manifest.homepage } else { '' }
    $appLink = "[$($_.BaseName)](bucket/$($_.Name))"
    $appCol = if ($homepage) {
        "$appLink [🌐]($homepage)"
    } else {
        $appLink
    }

    # 超长版本号截断，避免不折行字符撑开列宽
    $version = if ($manifest.version) {
        if ($manifest.version.Length -gt 18) {
            $manifest.version.Substring(0, 15) + '...'
        } else {
            $manifest.version
        }
    } else { '' }

    $lastUpdated = if ($dateMap.ContainsKey($_.Name)) { $dateMap[$_.Name] } else { $today }

    [PSCustomObject]@{
        App         = $_.BaseName
        AppCol      = $appCol
        Desc        = $desc
        Version     = $version
        LastUpdated = $lastUpdated
    }
}

$rows = $appData | Sort-Object -Property @{ Expression = 'LastUpdated'; Descending = $true }, @{ Expression = 'App' } | ForEach-Object {
    "| $($_.AppCol) | $($_.Desc) | $($_.Version) | $($_.LastUpdated) |"
}
$table = $rows -join "`n"

$readme = @"
# zyqpkg scoop bucket

A personal [Scoop](https://scoop.sh/) bucket for Windows apps not available in official buckets.

## Add this bucket

````powershell
scoop bucket add zyqpkg https://github.com/zyqpkg/scoop-bucket
````

## Install an app

````powershell
scoop install zyqpkg/<app-name>
````

## Apps

| App | Description | Version | Updated |
|-----|-------------|---------|---------|
$table
"@

Set-Content -Path $OutputPath -Value $readme -Encoding UTF8
