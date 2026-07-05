$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot

function Read-RepoFile($path) {
    Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root $path)
}

function Assert-Contains($path, $needle) {
    $text = Read-RepoFile $path
    if (-not $text.Contains($needle)) {
        throw "$path missing $needle"
    }
}

$sourcePath = Join-Path $root "app\src\main\java\com\xxcomic\source\HiperdexComicSource.java"
if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw "HiperdexComicSource.java missing"
}

Assert-Contains "app\src\main\java\com\xxcomic\source\SourceConfig.java" "SourceConfig hiperdex"
Assert-Contains "app\src\main\java\com\xxcomic\source\SourceConfig.java" "post_type=wp-manga"
Assert-Contains "app\src\main\java\com\xxcomic\MainActivity.java" "hiperdexClient"
Assert-Contains "app\src\main\java\com\xxcomic\MainActivity.java" "SourceConfig.hiperdex"

Write-Output "hiperdex source wiring ok"
