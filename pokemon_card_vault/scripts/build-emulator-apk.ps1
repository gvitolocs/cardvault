param(
    [string]$FlutterPath = 'C:\Users\raffa\develop\flutter\bin\flutter.bat',
    [string]$OutputDirectory = 'C:\Users\raffa\ApkProjects\pokoin-debug-emulator-x86_64'
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$apkSource = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-debug.apk'
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
$apkDestination = Join-Path $outputRoot 'pokoin-debug-emulator-x86_64.apk'

if (!(Test-Path -LiteralPath $FlutterPath -PathType Leaf)) {
    throw "Flutter executable not found: $FlutterPath"
}
if (!(Test-Path -LiteralPath $outputRoot -PathType Container)) {
    throw "APK destination directory not found: $outputRoot"
}

Push-Location $projectRoot
try {
    & $FlutterPath build apk --debug --target-platform android-x64
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
try {
    $flutterLibraries = @($archive.Entries |
        Where-Object { $_.FullName -match '^lib/[^/]+/libflutter\.so$' } |
        ForEach-Object FullName)
    if ($flutterLibraries.Count -ne 1 -or
        $flutterLibraries[0] -ne 'lib/x86_64/libflutter.so') {
        throw "Unexpected Flutter engine ABI: $($flutterLibraries -join ', '). Destination unchanged."
    }
} finally {
    $archive.Dispose()
}

$sourceHash = (Get-FileHash -LiteralPath $apkSource -Algorithm SHA256).Hash
if (Test-Path -LiteralPath $apkDestination -PathType Leaf) {
    $previousHash = (Get-FileHash -LiteralPath $apkDestination -Algorithm SHA256).Hash
    if ($previousHash -ne $sourceHash) {
        $backupDirectory = Join-Path $projectRoot 'build\emulator-apk-backups'
        New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
        $backupPath = Join-Path $backupDirectory "pokoin-debug-emulator-x86_64-$previousHash.apk"
        if (!(Test-Path -LiteralPath $backupPath)) {
            Copy-Item -LiteralPath $apkDestination -Destination $backupPath
        }
        if ((Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash -ne $previousHash) {
            throw 'Backup verification failed. Destination unchanged.'
        }
        Write-Output "Previous APK saved: $backupPath"
    }
}

Copy-Item -LiteralPath $apkSource -Destination $apkDestination -Force
if ((Get-FileHash -LiteralPath $apkDestination -Algorithm SHA256).Hash -ne $sourceHash) {
    throw 'Destination APK checksum does not match the build output.'
}
Write-Output "Updated APK: $apkDestination"
Write-Output "SHA256: $sourceHash"
Write-Output "Size: $((Get-Item -LiteralPath $apkDestination).Length) bytes"
