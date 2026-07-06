#!/usr/bin/env pwsh
# Uninstall Claude Quota (Windows): stop it, drop autostart, remove the app and
# its cache. Leaves your Claude Code credentials/transcripts untouched.
#
#   pwsh -File uninstall.ps1
#   pwsh -File uninstall.ps1 -KeepCache
#
[CmdletBinding()]
param([switch]$KeepCache)

$ErrorActionPreference = 'SilentlyContinue'
$appName = 'ClaudeQuota'
$dest    = Join-Path $env:LOCALAPPDATA "Programs\$appName"
$cache   = Join-Path $env:LOCALAPPDATA 'claude-quota'
$runKey  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

Write-Host "==> Deteniendo..." -ForegroundColor Cyan
Get-Process $appName | Stop-Process -Force
Start-Sleep -Milliseconds 400

Write-Host "==> Quitando autoarranque..." -ForegroundColor Cyan
Remove-ItemProperty -Path $runKey -Name $appName

Write-Host "==> Borrando $dest ..." -ForegroundColor Cyan
Remove-Item $dest -Recurse -Force

if (-not $KeepCache) {
    Write-Host "==> Borrando cache $cache ..." -ForegroundColor Cyan
    Remove-Item $cache -Recurse -Force
}

Write-Host "Desinstalado." -ForegroundColor Green
