# Builds dist\WoW-Chroma-Bridge-<version>.zip, the download end users get, from the wow-chroma
# folder plus the repository's LICENSE and CHANGELOG. The version number comes from the addon's .toc file,
# so bump "## Version" in wow-chroma\ChromaBridge\ChromaBridge.toc before building a release.
#
# Usage (Windows PowerShell 5.1 or PowerShell 7):  .\build.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path $root 'wow-chroma'
$version = ((Select-String -Path "$src\ChromaBridge\ChromaBridge.toc" -Pattern '^## Version:\s*(.+)$').Matches[0].Groups[1].Value).Trim()
$name = "WoW-Chroma-Bridge-$version"
$dist = Join-Path $root 'dist'
$stage = Join-Path $dist $name
$zip = Join-Path $dist "$name.zip"

if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
if (Test-Path $zip) { Remove-Item $zip -Force }
New-Item -ItemType Directory -Force $stage | Out-Null

$files = 'ChromaBridge', 'chroma-bridge.ps1', 'install.ps1', 'Install.bat', 'Uninstall.bat', 'Start Chroma Bridge.bat', 'Stop Chroma Bridge.bat', 'README.md'
foreach ($f in $files) { Copy-Item (Join-Path $src $f) $stage -Recurse }
Copy-Item (Join-Path $root 'LICENSE'), (Join-Path $root 'CHANGELOG.md') $stage

# Zip the folder itself, so extracting gives one tidy "WoW-Chroma-Bridge-x.y.z" folder.
# ZipFile instead of Compress-Archive: Windows PowerShell's Compress-Archive writes backslashes
# in entry names, which some unzip tools treat as part of the file name.
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
try {
  foreach ($file in Get-ChildItem $stage -Recurse -File) {
    $entry = "$name/" + $file.FullName.Substring($stage.Length + 1).Replace('\', '/')
    [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, $entry, [IO.Compression.CompressionLevel]::Optimal)
  }
} finally { $archive.Dispose() }
Remove-Item $stage -Recurse -Force
Get-Item $zip | Select-Object Name, Length
