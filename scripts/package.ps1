# Builds the release archive: out\LockPickHelper-<version>.zip, to be extracted into the game's G1R\Mods folder.
# Inside: the folder LockPickHelper\ with GothicMod.json, Script\LockPickHelper\ (without UnitTests\, the in-game tests),
# README.txt and LICENSE.txt - so that G1R\Mods\LockPickHelper\GothicMod.json exists after extracting, and the two texts
# stay in the mod's own folder instead of among the other mods'.
# Only what git tracks goes in (git ls-files mod/LockPickHelper, minus UnitTests/), and it refuses to pack while
# mod\LockPickHelper has an uncommitted change or an untracked file: nothing unreviewed, no scratch .as, reaches players.
# The version comes from GothicMod.json (modVersion); LPH::ModVersion in Config.as and README.txt must name the same one.
# It refuses to pack while LPH::DebugAlways (Config.as) is true: that switch forces the debug lines on for the in-game
# checks and must be false in a release. -AllowDebugAlways packs anyway, as out\LockPickHelper-<version>-debug.zip (an
# archive for trying out, not for release); the release name is only for DebugAlways false.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\package.ps1 [-AllowDebugAlways]
param(
    [switch]$AllowDebugAlways
)
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent
$mod = Join-Path $repoRoot "mod\LockPickHelper"
$scriptDir = Join-Path $mod "Script\LockPickHelper"

# The package is what git tracks: an uncommitted edit or an untracked file under mod\ must not reach the players.
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "git is needed: the package is made from the files it tracks" }
$dirty = @(& git -C $repoRoot status --porcelain -- mod/LockPickHelper LICENSE)
if ($LASTEXITCODE -ne 0) { throw "git status failed" }
if ($dirty) {
    throw ("mod\LockPickHelper (or LICENSE) has uncommitted or untracked files; commit or remove them first:`n" + ($dirty -join "`n"))
}
$tracked = @(& git -C $repoRoot -c core.quotepath=false ls-files -- mod/LockPickHelper)
if ($LASTEXITCODE -ne 0) { throw "git ls-files failed" }

$descriptor = Get-Content (Join-Path $mod "GothicMod.json") -Raw -Encoding UTF8 | ConvertFrom-Json
if ($descriptor.name -ne "LockPickHelper") { throw "GothicMod.json: name must be LockPickHelper" }
$version = [string]$descriptor.modVersion
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "GothicMod.json: modVersion '$version' is not x.y.z" }

$config = Get-Content (Join-Path $scriptDir "Config.as") -Raw -Encoding UTF8
if ($config -notmatch 'const FString ModVersion = "([^"]+)";') { throw "Config.as has no LPH::ModVersion" }
if ($Matches[1] -ne $version) { throw "Config.as says version $($Matches[1]), GothicMod.json says $version" }
if ($config -notmatch 'const bool DebugAlways = (true|false);') { throw "Config.as has no LPH::DebugAlways" }
$debugAlways = ($Matches[1] -eq "true")
if ($debugAlways) {
    if (-not $AllowDebugAlways) {
        throw "Config.as: LPH::DebugAlways is true. Set it to false for a release (or pass -AllowDebugAlways)"
    }
    Write-Warning "LPH::DebugAlways is true: this archive writes the debug lines always. Not for release."
}
$readme = Get-Content (Join-Path $mod "README.txt") -Raw -Encoding UTF8
if ($readme -notmatch [regex]::Escape("LockPick Helper $version ")) { throw "README.txt does not name version $version" }

# The stage: the tracked files of the mod's folder without the tests, and the license as LICENSE.txt.
$stage = Join-Path $repoRoot "out\package"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force -Confirm:$false }
$target = Join-Path $stage "LockPickHelper"
New-Item -ItemType Directory -Force $target | Out-Null
$prefix = "mod/LockPickHelper/"
foreach ($file in $tracked) {
    if (-not $file.StartsWith($prefix)) { throw "git lists a file outside ${prefix}: $file" }
    $relative = $file.Substring($prefix.Length)
    if ($relative.StartsWith("Script/LockPickHelper/UnitTests/")) { continue }
    $destination = Join-Path $target $relative.Replace('/', '\')
    New-Item -ItemType Directory -Force (Split-Path $destination -Parent) | Out-Null
    Copy-Item (Join-Path $repoRoot $file.Replace('/', '\')) $destination
}
Copy-Item (Join-Path $repoRoot "LICENSE") (Join-Path $target "LICENSE.txt")
# The two texts are for Notepad: Windows line breaks and UTF-8 without a byte order mark, whatever the checkout gave.
foreach ($text in @("README.txt", "LICENSE.txt")) {
    $path = Join-Path $target $text
    $raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($path, ($raw -replace "`r?`n", "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
}

# What goes in is checked, not assumed: the files a mod needs, nothing of the tests, nothing that is not text.
foreach ($needed in @("GothicMod.json", "README.txt", "LICENSE.txt", "Script\LockPickHelper\Controller.as",
        "Script\LockPickHelper\Mod.as", "Script\LockPickHelper\LockGraphs.as", "Script\LockPickHelper\Settings.as",
        "Script\LockPickHelper\LockPickExtension.as")) {
    if (-not (Test-Path (Join-Path $target $needed))) { throw "The package has no $needed" }
}
$skipped = @(Get-ChildItem $target -Recurse -Directory | Where-Object { $_.Name -in @("UnitTests", "Test", "Tests", "Dev") })
if ($skipped) { throw "The package holds a tests folder: $($skipped.FullName -join ', ')" }
$strange = @(Get-ChildItem $target -Recurse -File | Where-Object { $_.Extension -notin @(".as", ".json", ".txt") })
if ($strange) { throw "The package holds files that are not .as, .json or .txt: $($strange.FullName -join ', ')" }

# Entries with forward slashes (Compress-Archive in Windows PowerShell writes backslashes).
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$zipName = if ($debugAlways) { "LockPickHelper-$version-debug.zip" } else { "LockPickHelper-$version.zip" }
$zip = Join-Path $repoRoot "out\$zipName"
if (Test-Path $zip) { Remove-Item $zip -Force -Confirm:$false }
$archive = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    Get-ChildItem $stage -Recurse -File | Sort-Object FullName | ForEach-Object {
        $entry = $_.FullName.Substring($stage.Length + 1).Replace('\', '/')
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, $_.FullName, $entry, [System.IO.Compression.CompressionLevel]::Optimal)
    }
} finally {
    $archive.Dispose()
}
Write-Output "Packaged $zip"
