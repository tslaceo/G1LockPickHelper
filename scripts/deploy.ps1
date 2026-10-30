# Copies the Modkit package from this repo into the game's Mods folder (the whole package, Tests/ included), after
# removing the old copy. Refuses while the game is running: it holds the scripts.
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
if (Test-Path $target) { Remove-Item $target -Recurse -Force -Confirm:$false }
Copy-Item $sourceDir $target -Recurse
Write-Output "Deployed $name -> $target"
