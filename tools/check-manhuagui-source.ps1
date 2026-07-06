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

$sourcePath = Join-Path $root "app\src\main\java\com\xxcomic\source\ManhuaguiComicSource.java"
if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw "ManhuaguiComicSource.java missing"
}

Assert-Contains "app\src\main\java\com\xxcomic\source\SourceConfig.java" "SourceConfig manhuagui"
Assert-Contains "app\src\main\java\com\xxcomic\MainActivity.java" "manhuaguiClient"
Assert-Contains "app\src\main\java\com\xxcomic\MainActivity.java" "SourceConfig.manhuagui"
Assert-Contains "app\src\main\java\com\xxcomic\source\ManhuaguiComicSource.java" "BCOVER_BLOCK_PATTERN"
Assert-Contains "app\src\main\java\com\xxcomic\source\ManhuaguiComicSource.java" "data-original"
Assert-Contains "app\src\main\java\com\xxcomic\source\ManhuaguiComicSource.java" "getHeaderField(`"Location`")"
Assert-Contains "app\src\main\java\com\xxcomic\source\ManhuaguiComicSource.java" "normalizeRedirectUrl"
Assert-Contains "app\src\main\java\com\xxcomic\source\ManhuaguiComicSource.java" "http://`" + config.domain"
Assert-Contains "app\src\main\java\com\xxcomic\source\ManhuaguiComicSource.java" "cf.mhgui.com/cpic/b/"
Assert-Contains "app\src\main\java\com\xxcomic\source\ManhuaguiComicSource.java" "validImgDataFromScript"
Assert-Contains "app\src\main\java\com\xxcomic\source\ManhuaguiComicSource.java" "matchingBrace"
Assert-Contains "app\src\main\java\com\xxcomic\source\ManhuaguiComicSource.java" "isValidImgData"
Assert-Contains "app\src\main\java\com\xxcomic\source\ManhuaguiComicSource.java" "normalizeLooseJsonObject"
Assert-Contains "app\src\main\java\com\xxcomic\source\ManhuaguiComicSource.java" "chapterConfigMissingMessage"
Assert-Contains "app\src\main\java\com\xxcomic\source\ManhuaguiComicSource.java" "fetch(url, 15000, 30000)"
Assert-Contains "app\src\main\java\com\xxcomic\source\ManhuaguiComicSource.java" "(?:\\\\.|(?!\\1)[\\s\\S])*"
Assert-Contains "app\src\main\java\com\xxcomic\source\ManhuaguiComicSource.java" "IMG_DATA_MARKERS"
Assert-Contains "app\src\main\java\com\xxcomic\source\ManhuaguiComicSource.java" "imgData\""]"
Assert-Contains "app\src\main\java\com\xxcomic\source\ManhuaguiComicSource.java" "packerMatches"
Assert-Contains "app\src\main\java\com\xxcomic\source\ManhuaguiComicSource.java" "unpackedSnippet"
Assert-Contains "app\src\main\java\com\xxcomic\source\ManhuaguiComicSource.java" "splitPackerDict"
Assert-Contains "app\src\main\java\com\xxcomic\source\ManhuaguiComicSource.java" "Math.max(args.count, dict.length)"
Assert-Contains "app\src\main\java\com\xxcomic\source\ManhuaguiComicSource.java" "canonicalImgData"
Assert-Contains "app\src\main\java\com\xxcomic\source\ManhuaguiComicSource.java" "looksLikeFiles"
Assert-Contains "app\src\main\java\com\xxcomic\source\ManhuaguiComicSource.java" "looksLikePath"
Assert-Contains "app\src\main\java\com\xxcomic\source\ManhuaguiComicSource.java" "replaceAll(`"^/+`", `"`")"
Assert-Contains "app\src\main\java\com\xxcomic\source\ManhuaguiComicSource.java" "replaceAll(`"/+$`", `"`")"
Assert-Contains "app\src\main\java\com\xxcomic\source\ManhuaguiComicSource.java" "numericChapterId"

Write-Output "manhuagui source wiring ok"
