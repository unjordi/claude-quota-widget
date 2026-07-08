#!/usr/bin/env pwsh
# install-brain.ps1 — lanzador DELGADO de Windows para el instalador del cerebro (claude-brain).
# Los hooks del cerebro corren bajo BASH en TODAS las plataformas (decisión "bash en todos lados",
# sin drift .sh/.ps1). En Windows eso lo provee Git Bash (viene con Git for Windows). Este script
# NO reimplementa la lógica: solo verifica bash + jq y delega en `bash brain/install-brain.sh`,
# que es idempotente y hace todo el trabajo real (hooks, cableado, skill, dashboard, normas).
# Correr tras clonar:  pwsh -File brain\install-brain.ps1
$ErrorActionPreference = 'Continue'

# ── Dependencia dura: bash (Git Bash en Windows) ──
$bash = Get-Command bash -ErrorAction SilentlyContinue
if (-not $bash) {
  foreach ($p in @("$env:ProgramFiles\Git\bin\bash.exe","${env:ProgramFiles(x86)}\Git\bin\bash.exe","$env:LOCALAPPDATA\Programs\Git\bin\bash.exe")) {
    if (Test-Path $p) { $bash = $p; break }
  }
}
if (-not $bash) {
  Write-Host "ERROR: no encuentro 'bash'. Los hooks del cerebro corren bajo bash en todas las plataformas."
  Write-Host "  En Windows instala Git for Windows (trae Git Bash):  winget install Git.Git"
  Write-Host "  Luego re-corre: pwsh -File brain\install-brain.ps1"
  exit 1
}
$bashExe = if ($bash -is [System.Management.Automation.CommandInfo]) { $bash.Source } else { $bash }

# ── Dependencia de los hooks: jq (sin jq los guards fallan abierto y no puedo cablear settings.json) ──
& $bashExe -lc "command -v jq >/dev/null 2>&1"
if ($LASTEXITCODE -ne 0) {
  Write-Host "ADVERTENCIA: 'jq' no está disponible en bash. Los hooks lo REQUIEREN (sin jq el"
  Write-Host "  git-branch-guard falla abierto y el instalador no cablea el settings.json)."
  Write-Host "  Instálalo: winget install jqlang.jq  (o choco/scoop install jq)"
}

# ── Delegar TODO el trabajo real al instalador .sh (fuente única, idempotente) ──
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Installer = Join-Path $ScriptDir 'install-brain.sh'
if (-not (Test-Path $Installer)) {
  Write-Host "ERROR: no encuentro el instalador $Installer"
  exit 1
}
Write-Host "==> claude-brain: delegando en bash $Installer"
& $bashExe "$Installer"
exit $LASTEXITCODE
