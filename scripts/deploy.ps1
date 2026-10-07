# Copies a UE4SS mod folder from this repo into the game's UE4SS Mods folder.
# The player's settings.ini in the deployed folder (written by the mod, not in the repo) is kept.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\deploy.ps1 -GameDir "<Gothic 1 Remake folder>"
#        [-Source mod\G1LockPickHelper]
#        (or set the G1R_GAME_DIR environment variable instead of -GameDir)
param(
    [string]$Source = "mod\G1LockPickHelper",
    [string]$GameDir = $env:G1R_GAME_DIR
)
$ErrorActionPreference = "Stop"
if (-not $GameDir) { throw "Set -GameDir <Gothic 1 Remake folder> or the G1R_GAME_DIR environment variable" }
$repoRoot = Split-Path $PSScriptRoot -Parent
$sourceDir = Join-Path $repoRoot $Source
$modsDir = Join-Path $GameDir "G1R\Binaries\Win64\ue4ss\Mods"
if (-not (Test-Path $sourceDir)) { throw "Source not found: $sourceDir" }
if (-not (Test-Path $modsDir)) { throw "UE4SS Mods folder not found: $modsDir" }
$name = Split-Path $sourceDir -Leaf
$target = Join-Path $modsDir $name
$settings = Join-Path $target "settings.ini"
$kept = $null
if (Test-Path $settings) {
    $kept = [System.IO.Path]::GetTempFileName()
    Copy-Item $settings $kept -Force
}
if (Test-Path $target) { Remove-Item $target -Recurse -Force -Confirm:$false }
Copy-Item $sourceDir $target -Recurse
if ($kept) {
    Copy-Item $kept $settings -Force
    Remove-Item $kept -Force
    Write-Output "Kept settings.ini"
}
Write-Output "Deployed $name -> $target"
