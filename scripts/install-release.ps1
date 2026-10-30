# Puts the release archive into the game exactly as a player gets it: removes G1R\Mods\LockPickHelper, extracts
# out\LockPickHelper-<version>.zip (the one package.ps1 built) into G1R\Mods and checks what is there. The Workshop
# uploads the folder G1R\Mods\LockPickHelper as it is, so a Workshop upload must be made from this - never after
# deploy.ps1, which brings UnitTests\ and the debug switch of the working tree.
# Refuses while the game is running (it holds the scripts), a *-debug.zip and an archive whose Config.as says
# DebugAlways = true (all before anything in the game folder is touched). If the folder it would remove
# holds a file that is not in the archive and is not a .as under Script\ (an id file the game may write after a Workshop
# upload, say), it stops and names the file instead of deleting it.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install-release.ps1 -GameDir "<Gothic 1 Remake folder>"
#        [-Zip out\LockPickHelper-<version>.zip]   (relative to the repository root; the version is modVersion of
#        mod\LockPickHelper\GothicMod.json)
#        (or set the G1R_GAME_DIR environment variable instead of -GameDir)
param(
    [string]$Zip,
    [string]$GameDir = $env:G1R_GAME_DIR
)
$ErrorActionPreference = "Stop"
if (-not $GameDir) { throw "Set -GameDir <Gothic 1 Remake folder> or the G1R_GAME_DIR environment variable" }
$repoRoot = Split-Path $PSScriptRoot -Parent
$modsDir = Join-Path $GameDir "G1R\Mods"
if (-not (Test-Path $modsDir)) { throw "Mods folder not found: $modsDir" }
if (Get-Process -Name "G1R-Win64-Shipping" -ErrorAction SilentlyContinue) {
    throw "The game is running: close it before installing"
}

if (-not $Zip) {
    $descriptor = Get-Content (Join-Path $repoRoot "mod\LockPickHelper\GothicMod.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $Zip = "out\LockPickHelper-$([string]$descriptor.modVersion).zip"
}
if (-not [System.IO.Path]::IsPathRooted($Zip)) { $Zip = Join-Path $repoRoot $Zip }
if (-not (Test-Path $Zip)) { throw "No archive: $Zip (build it with scripts\package.ps1)" }
if ((Split-Path $Zip -Leaf) -like "*-debug.zip") { throw "$(Split-Path $Zip -Leaf) is a trial archive (DebugAlways); install a release archive" }

# The archive's own file list, read before anything in the game folder is touched.
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($Zip)
try {
    $entries = @($archive.Entries | Where-Object { $_.Name -ne "" } | ForEach-Object { $_.FullName })
    $configEntry = $archive.GetEntry("LockPickHelper/Script/LockPickHelper/Config.as")
    if ($configEntry) {
        $reader = New-Object System.IO.StreamReader($configEntry.Open(), [System.Text.Encoding]::UTF8)
        try { $archivedConfig = $reader.ReadToEnd() } finally { $reader.Dispose() }
    }
} finally {
    $archive.Dispose()
}
foreach ($entry in $entries) {
    if (-not $entry.StartsWith("LockPickHelper/") -or $entry.Contains("..")) { throw "Unexpected entry in the archive: $entry" }
}
if ($entries -notcontains "LockPickHelper/GothicMod.json") { throw "The archive has no LockPickHelper/GothicMod.json" }
if (-not $configEntry -or $archivedConfig -notmatch 'const bool DebugAlways = false;') {
    throw "Config.as in the archive does not say DebugAlways = false: not a release archive"
}

# The folder is removed wholesale: stop first on a file the archive does not know (and that is not a script).
$target = Join-Path $modsDir "LockPickHelper"
if (Test-Path $target) {
    $targetFull = (Resolve-Path $target).Path
    $known = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $entries) { [void]$known.Add($entry.Substring("LockPickHelper/".Length).Replace('/', '\')) }
    $unknown = @(Get-ChildItem $targetFull -Recurse -File -Force | ForEach-Object { $_.FullName.Substring($targetFull.Length + 1) } |
        Where-Object { -not $known.Contains($_) -and -not ($_ -like "Script\*.as") })
    if ($unknown) {
        throw ("$target holds files that are not in the archive and are not scripts; nothing was deleted. " +
            "Look at them (an id file of the Workshop upload? then it belongs in the repo) and remove them by hand:`n" +
            ($unknown -join "`n"))
    }
    Remove-Item $target -Recurse -Force -Confirm:$false
}
[System.IO.Compression.ZipFile]::ExtractToDirectory($Zip, $modsDir)

# What is there now is checked, not assumed.
if (-not (Test-Path (Join-Path $target "GothicMod.json"))) { throw "After extracting there is no $target\GothicMod.json" }
$config = Get-Content (Join-Path $target "Script\LockPickHelper\Config.as") -Raw -Encoding UTF8
if ($config -notmatch 'const bool DebugAlways = false;') { throw "Config.as in the game folder does not say DebugAlways = false" }
$tests = @(Get-ChildItem $target -Recurse -Directory | Where-Object { $_.Name -in @("UnitTests", "Test", "Tests", "Dev") })
if ($tests) { throw "The game folder holds a tests folder: $($tests.FullName -join ', ')" }
foreach ($text in @("LICENSE.txt", "README.txt")) {
    if (-not (Test-Path (Join-Path $target $text))) { throw "After extracting there is no $text" }
}
$files = @(Get-ChildItem $target -Recurse -File -Force)
if ($files.Count -ne $entries.Count) { throw "The folder holds $($files.Count) files, the archive $($entries.Count)" }

$descriptor = Get-Content (Join-Path $target "GothicMod.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$scripts = @($files | Where-Object { $_.Extension -eq ".as" })
Write-Output "Installed $(Split-Path $Zip -Leaf) -> $target"
Write-Output "  $($descriptor.name) $($descriptor.modVersion): $($files.Count) files, $($scripts.Count) scripts, DebugAlways = false, no tests folder, LICENSE.txt and README.txt present"
