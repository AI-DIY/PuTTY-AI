param(
    [string]$BuildDirectory = "",
    [string]$OutputDirectory = "",
    [string]$Version = "1.0.0"
)

$ErrorActionPreference = "Stop"
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
if (-not $BuildDirectory) {
    $BuildDirectory = Join-Path $root "build\Release"
}
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $root "package"
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Version must use major.minor.patch format"
}

$BuildDirectory = [IO.Path]::GetFullPath($BuildDirectory)
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$stageName = "PuTTY-AI-windows-x64"
$stageDirectory = [IO.Path]::GetFullPath(
    (Join-Path $OutputDirectory $stageName))
$zipPath = Join-Path $OutputDirectory "PuTTY-AI-v$Version-windows-x64.zip"
$outputPrefix = $OutputDirectory.TrimEnd(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $stageDirectory.StartsWith(
        $outputPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Package staging directory is outside the output directory"
}

$exePath = Join-Path $BuildDirectory "putty.exe"
if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
    throw "Built executable was not found: $exePath"
}
$versionInfo = (Get-Item -LiteralPath $exePath).VersionInfo
if ($versionInfo.ProductVersion -ne $Version) {
    throw "Executable version '$($versionInfo.ProductVersion)' does not match '$Version'"
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} `
    "Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) {
    throw "Visual Studio Installer was not found"
}
$vsRoot = & $vswhere -latest -products * `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -property installationPath
if (-not $vsRoot) {
    throw "Visual Studio C++ Build Tools were not found"
}
$redistRoot = Join-Path $vsRoot "VC\Redist\MSVC"
$vcRuntime = Get-ChildItem -LiteralPath $redistRoot -Directory |
    Sort-Object Name -Descending |
    ForEach-Object {
        Join-Path $_.FullName "x64\Microsoft.VC143.CRT\vcruntime140.dll"
    } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1
if (-not $vcRuntime) {
    throw "x64 vcruntime140.dll was not found"
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
if (Test-Path -LiteralPath $stageDirectory) {
    Remove-Item -LiteralPath $stageDirectory -Recurse -Force
}
New-Item -ItemType Directory -Path $stageDirectory | Out-Null

Copy-Item -LiteralPath $exePath -Destination $stageDirectory
Copy-Item -LiteralPath $vcRuntime -Destination $stageDirectory
Copy-Item -LiteralPath (Join-Path $root "readme.md") `
    -Destination (Join-Path $stageDirectory "README.md")
Copy-Item -LiteralPath (Join-Path $root "LICENSE") `
    -Destination (Join-Path $stageDirectory "PROJECT-LICENSE.txt")
Copy-Item -LiteralPath (Join-Path $root "putty-src\LICENCE") `
    -Destination (Join-Path $stageDirectory "PUTTY-LICENCE.txt")
Copy-Item -LiteralPath (Join-Path $root "THIRD-PARTY-NOTICES.md") `
    -Destination $stageDirectory
Copy-Item -LiteralPath (Join-Path $root "RELEASE_NOTES.md") `
    -Destination (Join-Path $stageDirectory "RELEASE-NOTES.md")

$fileHashes = @("putty.exe", "vcruntime140.dll") | ForEach-Object {
    $hash = Get-FileHash -Algorithm SHA256 `
        -LiteralPath (Join-Path $stageDirectory $_)
    "$($hash.Hash.ToLowerInvariant()) *$_"
}
[IO.File]::WriteAllLines(
    (Join-Path $stageDirectory "SHA256SUMS.txt"),
    $fileHashes,
    [Text.UTF8Encoding]::new($false))

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -LiteralPath $stageDirectory -DestinationPath $zipPath `
    -CompressionLevel Optimal
$zipHash = Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath
[IO.File]::WriteAllLines(
    (Join-Path $OutputDirectory "SHA256SUMS.txt"),
    @("$($zipHash.Hash.ToLowerInvariant()) *$([IO.Path]::GetFileName($zipPath))"),
    [Text.UTF8Encoding]::new($false))

Write-Output $zipPath
