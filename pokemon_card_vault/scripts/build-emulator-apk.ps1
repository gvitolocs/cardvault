param(
    [string]$FlutterPath = 'C:\Users\raffa\develop\flutter\bin\flutter.bat',
    [string]$OutputDirectory = '',
    [string]$Target = 'lib/rebuild/main_mobile_prototype.dart',
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*\.apk$')]
    [string]$ApkFileName = 'pokoin-profile-phone-arm64-Rebuild.apk',
    [ValidateSet('android-x64', 'android-arm64')]
    [string]$TargetPlatform = 'android-arm64',
    [ValidateSet('debug', 'profile')]
    [string]$BuildMode = 'profile'
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$flutterOutputRoot = Join-Path $projectRoot 'build\app\outputs\flutter-apk'
$canonicalOutputRoot = Join-Path $flutterOutputRoot 'Rebuild'
$backupDirectory = Join-Path $projectRoot 'build\emulator-apk-backups'
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = $canonicalOutputRoot
}
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\', '/')
if (![string]::Equals($outputRoot, $canonicalOutputRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "The single-APK workflow only saves to $canonicalOutputRoot."
}
$apkSource = Join-Path $flutterOutputRoot "app-$BuildMode.apk"
$apkDestination = Join-Path $outputRoot $ApkFileName

# Refuse linked output folders before promoting the generated APK.
foreach ($generatedDirectory in @($flutterOutputRoot, $outputRoot, $backupDirectory)) {
    if (Test-Path -LiteralPath $generatedDirectory) {
        $directoryInfo = Get-Item -LiteralPath $generatedDirectory -Force
        if (!$directoryInfo.PSIsContainer -or
            ($directoryInfo.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Expected a regular generated directory: $generatedDirectory"
        }
    }
}
if (!(Test-Path -LiteralPath $FlutterPath -PathType Leaf)) {
    throw "Flutter executable not found: $FlutterPath"
}
if (!(Test-Path -LiteralPath $outputRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
}

Push-Location $projectRoot
try {
    & $FlutterPath build apk "--$BuildMode" --target-platform $TargetPlatform --target $Target
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter APK build failed (exit $LASTEXITCODE). The previous APK is unchanged."
    }
} finally {
    Pop-Location
}
if (!(Test-Path -LiteralPath $apkSource -PathType Leaf)) {
    throw "Build output not found: $apkSource"
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($apkSource)
$expectedAbi = if ($TargetPlatform -eq 'android-arm64') { 'arm64-v8a' } else { 'x86_64' }
try {
    $flutterLibraries = @($archive.Entries |
        Where-Object { $_.FullName -match '^lib/[^/]+/libflutter\.so$' } |
        ForEach-Object FullName)
    if ($flutterLibraries.Count -ne 1 -or
        $flutterLibraries[0] -ne "lib/$expectedAbi/libflutter.so") {
        throw "Unexpected Flutter engine ABI: $($flutterLibraries -join ', '). Destination unchanged."
    }
} finally {
    $archive.Dispose()
}

$sourceHash = (Get-FileHash -LiteralPath $apkSource -Algorithm SHA256).Hash
$apkBaseName = [IO.Path]::GetFileNameWithoutExtension($ApkFileName)
if (Test-Path -LiteralPath $apkDestination -PathType Leaf) {
    $previousHash = (Get-FileHash -LiteralPath $apkDestination -Algorithm SHA256).Hash
    if ($previousHash -ne $sourceHash) {
        New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
        $backupPath = Join-Path $backupDirectory "$apkBaseName-$previousHash.apk"
        if (!(Test-Path -LiteralPath $backupPath)) {
            Copy-Item -LiteralPath $apkDestination -Destination $backupPath
        }
        if ((Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash -ne $previousHash) {
            throw 'Previous APK backup verification failed. Destination unchanged.'
        }
    }
    # Same-volume replacement preserves the previous final file until promotion succeeds.
    [IO.File]::Replace($apkSource, $apkDestination, [NullString]::Value)
} else {
    Move-Item -LiteralPath $apkSource -Destination $apkDestination
}
if ((Get-FileHash -LiteralPath $apkDestination -Algorithm SHA256).Hash -ne $sourceHash) {
    throw 'Destination APK checksum does not match the build output.'
}

# User policy: current APK plus at most three distinct preceding versions.
# Only this helper's hash-named history is eligible; no recursive deletion.
if (Test-Path -LiteralPath $backupDirectory -PathType Container) {
    $seenVersions = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    [void]$seenVersions.Add($sourceHash)
    $keptVersions = 0
    $historyNamePattern = '^' + [regex]::Escape($apkBaseName) + '-([A-Fa-f0-9]{64})\.apk$'
    $historyFiles = @(Get-ChildItem -LiteralPath $backupDirectory -File -Filter "$apkBaseName-*.apk" | Sort-Object LastWriteTime -Descending)
    foreach ($historyFile in $historyFiles) {
        if ($historyFile.Name -notmatch $historyNamePattern) { continue }
        $historyHash = $Matches[1]
        if ($historyFile.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Unexpected historical APK link: $($historyFile.FullName)"
        }
        if ($seenVersions.Contains($historyHash) -or $keptVersions -ge 3) {
            $resolvedHistory = (Resolve-Path -LiteralPath $historyFile.FullName).ProviderPath
            if ((Split-Path -Parent $resolvedHistory) -ne $backupDirectory) {
                throw "Unexpected history cleanup path: $resolvedHistory"
            }
            Remove-Item -LiteralPath $resolvedHistory -Force
        } else {
            if ((Get-FileHash -LiteralPath $historyFile.FullName -Algorithm SHA256).Hash -ne $historyHash) {
                throw "Historical APK checksum mismatch: $($historyFile.FullName)"
            }
            [void]$seenVersions.Add($historyHash)
            $keptVersions++
        }
    }
}
Write-Output "Updated single APK: $apkDestination"
Write-Output "SHA256: $sourceHash"
Write-Output "Size: $((Get-Item -LiteralPath $apkDestination).Length) bytes"
Write-Output 'One current APK exported; history limited to three preceding distinct versions.'
