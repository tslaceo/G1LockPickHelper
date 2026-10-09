# Builds the archive for Nexus: out\G1LockPickHelper-<version>.zip, to be extracted into the game folder.
# The version comes from main.lua (local VERSION = "x.y.z"); README.txt must name the same version.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\package.ps1
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent
$mod = Join-Path $repoRoot "mod\G1LockPickHelper"
$scripts = Join-Path $mod "Scripts"

$main = Get-Content (Join-Path $scripts "main.lua") -Raw -Encoding UTF8
if ($main -match 'local VERSION = "(\d+\.\d+\.\d+)"') { $version = $Matches[1] } else { throw "main.lua has no VERSION" }
$settings = Get-Content (Join-Path $scripts "settings.lua") -Raw -Encoding UTF8
if ($settings -notmatch 'key = "debug", kind = "bool", default = false') {
    throw "settings.lua: [general] debug must default to false"
}
$readme = Get-Content (Join-Path $mod "README.txt") -Raw -Encoding UTF8
if ($readme -notmatch [regex]::Escape("G1LockPickHelper $version ")) { throw "README.txt does not name version $version" }

$expected = @(
    "autosolve.lua", "config.lua", "i18n.lua", "input_fix.lua", "lang\en.lua", "lang\ru.lua",
    "lock_reader.lua", "lockdb.lua", "lockgraphs.lua", "main.lua", "menu.lua", "overlay.lua", "pad.lua",
    "settings.lua", "solver.lua", "tracker.lua", "view.lua"
) | Sort-Object
$actual = @(Get-ChildItem $scripts -Recurse -File | ForEach-Object { $_.FullName.Substring($scripts.Length + 1) }) |
    Sort-Object
$diff = Compare-Object $expected $actual
if ($diff) { throw "Scripts does not hold exactly the shipped files:`n$($diff | Out-String)" }

$stage = Join-Path $repoRoot "out\package"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force -Confirm:$false }
$target = Join-Path $stage "G1R\Binaries\Win64\ue4ss\Mods\G1LockPickHelper"
New-Item -ItemType Directory -Force $target | Out-Null
Copy-Item (Join-Path $mod "enabled.txt") $target
Copy-Item (Join-Path $mod "README.txt") $target
Copy-Item (Join-Path $repoRoot "LICENSE") (Join-Path $target "LICENSE.txt")
Copy-Item $scripts (Join-Path $target "Scripts") -Recurse

# Entries with forward slashes (Compress-Archive in Windows PowerShell writes backslashes).
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$zip = Join-Path $repoRoot "out\G1LockPickHelper-$version.zip"
if (Test-Path $zip) { Remove-Item $zip -Force -Confirm:$false }
$archive = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    Get-ChildItem $stage -Recurse -File | ForEach-Object {
        $entry = $_.FullName.Substring($stage.Length + 1).Replace('\', '/')
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, $_.FullName, $entry, [System.IO.Compression.CompressionLevel]::Optimal)
    }
} finally {
    $archive.Dispose()
}
Write-Output "Packaged $zip"
