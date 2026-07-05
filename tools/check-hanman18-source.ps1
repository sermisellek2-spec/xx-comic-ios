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

$sourcePath = Join-Path $root "app\src\main\java\com\xxcomic\source\Hanman18ComicSource.java"
if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw "Hanman18ComicSource.java missing"
}

Assert-Contains "app\src\main\java\com\xxcomic\source\SourceConfig.java" "SourceConfig hanman18"
Assert-Contains "app\src\main\java\com\xxcomic\MainActivity.java" "hanman18Client"
Assert-Contains "app\src\main\java\com\xxcomic\MainActivity.java" "SourceConfig.hanman18"

Write-Output "hanman18 source wiring ok"
