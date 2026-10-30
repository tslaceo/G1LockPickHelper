# Copies the Modkit package from this repo into the game's Mods folder (the whole package, UnitTests/ included), after
# removing the old copy. Refuses while the game is running: it holds the scripts. If the old copy holds a file the
# package does not know and that is not a .as under Script\ (an id file the game may write after a Workshop upload), it
# stops and names the file instead of deleting it. This is the development copy (tests, the working tree's debug switch):
# never upload to the Workshop from it - install-release.ps1 puts the release build into the game for that.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\deploy.ps1 -GameDir "<Gothic 1 Remake folder>"
#        [-Source mod\LockPickHelper]
#        (or set the G1R_GAME_DIR environment variable instead of -GameDir)
param(
    [string]$Source = "mod\LockPickHelper",
    [string]$GameDir = $env:G1R_GAME_DIR
)
$ErrorActionPreference = "Stop"
if (-not $GameDir) { throw "Set -GameDir <Gothic 1 Remake folder> or the G1R_GAME_DIR environment variable" }
$repoRoot = Split-Path $PSScriptRoot -Parent
$sourceDir = Join-Path $repoRoot $Source
$modsDir = Join-Path $GameDir "G1R\Mods"
if (-not (Test-Path (Join-Path $sourceDir "GothicMod.json"))) { throw "Not a mod package (no GothicMod.json): $sourceDir" }
if (-not (Test-Path $modsDir)) { throw "Mods folder not found: $modsDir" }
if (Get-Process -Name "G1R-Win64-Shipping" -ErrorAction SilentlyContinue) {
    throw "The game is running: close it before deploying"
}
$name = Split-Path $sourceDir -Leaf
$target = Join-Path $modsDir $name
if (Test-Path $target) {
    # The old copy is removed wholesale: stop first on a file the package does not know (an id file the game may write
    # after a Workshop upload, say). Known: the package's own files, any .as under Script\ (UnitTests\ of an older
    # copy, a script renamed since) and the archive's README.txt and LICENSE.txt (a release build in the folder).
    $sourceFull = (Resolve-Path $sourceDir).Path
    $targetFull = (Resolve-Path $target).Path
    $known = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in Get-ChildItem $sourceFull -Recurse -File -Force) { [void]$known.Add($file.FullName.Substring($sourceFull.Length + 1)) }
    foreach ($file in @("README.txt", "LICENSE.txt")) { [void]$known.Add($file) }
    $unknown = @(Get-ChildItem $targetFull -Recurse -File -Force | ForEach-Object { $_.FullName.Substring($targetFull.Length + 1) } |
        Where-Object { -not $known.Contains($_) -and -not ($_ -like "Script\*.as") })
    if ($unknown) {
        throw ("$target holds files that are not in the package and are not scripts; nothing was deleted. " +
            "Look at them (an id file of the Workshop upload? then it belongs in the repo) and remove them by hand:`n" +
            ($unknown -join "`n"))
    }
    Remove-Item $target -Recurse -Force -Confirm:$false
}
Copy-Item $sourceDir $target -Recurse
Write-Output "Deployed $name -> $target"
