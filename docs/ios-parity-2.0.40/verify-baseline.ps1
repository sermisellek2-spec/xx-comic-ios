[CmdletBinding()]
param(
    [string]$BaselineDirectory = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($BaselineDirectory)) {
    $BaselineDirectory = Join-Path $PSScriptRoot 'baseline'
}
$expectedCommit = '696e80a44ab36b19de6f630565df32978e55a19e'
$expectedArchiveSha = '4a565a34f4f169f651c8e4222ea1a8fb3d5b0cd529de04e4322e53a0b72cf3bb'
$manifestPath = Join-Path $BaselineDirectory 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Missing frozen manifest: $manifestPath"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.schema -ne 'xx-comic.ios-parity.baseline.v1' -or
    $manifest.androidVersion -ne '2.0.40' -or $manifest.androidVersionCode -ne 340 -or
    $manifest.androidReleaseCommit -ne $expectedCommit -or
    $manifest.archive -ne 'android-2.0.40-reference.zip' -or
    $manifest.archiveSha256 -ne $expectedArchiveSha -or $manifest.fileCount -ne 527) {
    throw 'Frozen manifest identity differs from the agreed Android 2.0.40 release.'
}
$archivePath = Join-Path $BaselineDirectory $manifest.archive
if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
    throw "Missing frozen archive. Run in the iOS checkout or copy its full baseline folder: $archivePath"
}
$archiveSha = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($archiveSha -ne $expectedArchiveSha) { throw 'Frozen archive SHA-256 mismatch.' }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$expectedFiles = @{}
foreach ($property in $manifest.files.PSObject.Properties) {
    $expectedFiles.Add($property.Name, [string]$property.Value)
}
if ($expectedFiles.Count -ne 527) { throw 'Manifest file count mismatch.' }
$seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$archive = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    foreach ($entry in $archive.Entries) {
        if ($entry.FullName.EndsWith('/')) { continue }
        $entryName = $entry.FullName
        if ($entryName.StartsWith('/') -or $entryName.Contains('\') -or
            $entryName.Contains(':') -or ($entryName.Split('/') -contains '..')) {
            throw "Unsafe archive path: $entryName"
        }
        if (-not $seen.Add($entryName)) { throw "Duplicate archive entry: $entryName" }
        if (-not $expectedFiles.ContainsKey($entryName)) { throw "Unexpected archive entry: $entryName" }
        $entryStream = $entry.Open()
        $hasher = [System.Security.Cryptography.SHA256]::Create()
        try {
            $actualSha = [System.BitConverter]::ToString($hasher.ComputeHash($entryStream)).Replace('-', '').ToLowerInvariant()
        } finally {
            $hasher.Dispose()
            $entryStream.Dispose()
        }
        if ($actualSha -ne $expectedFiles[$entryName]) { throw "File SHA-256 mismatch: $entryName" }
    }
    if ($seen.Count -ne $expectedFiles.Count) { throw 'Archive has missing manifest files.' }
} finally {
    $archive.Dispose()
}
Write-Output "PASS: Android 2.0.40 / 340; release $expectedCommit; 527 files and archive SHA-256 verified."
