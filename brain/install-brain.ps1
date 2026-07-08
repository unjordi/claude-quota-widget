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

# ── PATH: asegurar que 'bash' quede en el PATH de USUARIO (persistente) ──
# Git for Windows / winget ponen git.exe (Git\cmd) en el PATH, pero NO bash.exe (vive en Git\bin).
# Claude Code corre los hooks con "shell":"bash" -> si bash no está en el PATH, los guardrails NO
# aplican. Añadimos Git\bin (bash.exe) al PATH de usuario; NO añadimos Git\usr\bin (evita que
# find/sort de Unix ensombrezcan los de Windows) — bash resuelve sus coreutils solo al arrancar.
$gitBin = Split-Path -Parent $bashExe
$userPath = [Environment]::GetEnvironmentVariable('PATH','User')
if ($null -eq $userPath) { $userPath = '' }
if (($userPath -split ';') -notcontains $gitBin) {
  Write-Host "==> claude-brain: agrego '$gitBin' al PATH de usuario (Claude Code necesita 'bash' para los hooks)"
  [Environment]::SetEnvironmentVariable('PATH', ($userPath.TrimEnd(';') + ';' + $gitBin), 'User')
  $env:PATH = $env:PATH.TrimEnd(';') + ';' + $gitBin   # visible ya en esta sesión
  $script:pathChanged = $true
}

# ── Auto-sanar CRLF: Git for Windows (core.autocrlf=true) clona los .sh con CRLF y bash muere con el \r ──
# El .gitattributes del repo lo previene en clones FUTUROS, pero un clon ya existente (o con config
# rara) sigue con CRLF. Aquí quitamos los CR (byte 0x0D) de TODO .sh del repo antes de correr bash,
# byte a byte para no meter BOM ni tocar la codificación. Idempotente (si ya está en LF, no hace nada).
$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$fixed = 0
Get-ChildItem -Path $RepoRoot -Recurse -Filter *.sh -File -ErrorAction SilentlyContinue | ForEach-Object {
  $bytes = [IO.File]::ReadAllBytes($_.FullName)
  if ($bytes -contains 13) {
    [IO.File]::WriteAllBytes($_.FullName, [byte[]]($bytes | Where-Object { $_ -ne 13 }))
    $fixed++
  }
}
if ($fixed -gt 0) { Write-Host "==> claude-brain: normalicé a LF $fixed script(s) .sh que venían con CRLF (fix Git-for-Windows)" }

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
$rc = $LASTEXITCODE
if ($script:pathChanged) {
  Write-Host ""
  Write-Host "NOTA: agregué 'bash' al PATH de usuario. Para que Claude Code (y tu terminal) lo vean,"
  Write-Host "  ABRE UNA TERMINAL NUEVA (o reinicia Claude Code). En la actual ya quedó disponible."
}
exit $rc
