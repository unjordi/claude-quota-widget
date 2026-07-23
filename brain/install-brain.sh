#!/usr/bin/env bash
# install-brain.sh — instalador del CEREBRO GLOBAL compartible de Claude Code (claude-brain).
# "Corre una vez y tu máquina queda con los guardrails, la gobernanza de costo de delegación,
# la skill de cierre, el dashboard y las normas globales." Re-correrlo es SEGURO (idempotente).
#
# Instala GLOBAL (en ~/.claude, aplica a TODOS los repos de esta máquina):
#   (a) HOOKS de tier {global, both} en ~/.claude/hooks/ — la LISTA se DERIVA de brain/hooks/MANIFEST
#       (fuente única; ya no se cura a mano en paralelo con la copia por-repo). Incluye git-branch-guard,
#       merge-squash-guard, confirmar-merge-develop, recordar-dashboard, secret-scan, rama-vieja,
#       proteger-arbol (PreToolUse/Bash), delegacion-gate + limite-gasto (PreToolUse/Task),
#       delegacion-registrar/reporte (PostToolUse/Task), rehidratar-hilo + aviso-contexto (SessionStart/
#       PostToolUse) + libs `delegacion-comun.sh`, `analizar-comando-git.sh`, `detectar-secretos.sh`
#       + agentes-costo.json (config). La lista EXACTA se deriva de brain/hooks/MANIFEST.
#   (b) CABLEADO en ~/.claude/settings.json con "shell":"bash" (idempotente).
#   (c) SKILLS genéricas (cerrar-slice, orquestar-fanout, checkpoint, rehidratar-hilo, turno-nocturno,
#       diagramar, cosechar-sesion, unificar-cerebro) en ~/.claude/skills/. La copia GLOBBEA brain/skills/*/
#       → basta con crear la carpeta de la skill; esta lista es descriptiva.
#   (d) DASHBOARD del cerebro sembrado en la memoria GLOBAL (slug del HOME) si falta.
#   (e) NORMAS globales inyectadas en ~/.claude/CLAUDE.md (bloque con marcador, solo si faltan).
#
# confirmar-merge-develop AHORA es GLOBAL (candado de merges a develop/main con OK explícito): antes
# vivía solo por-repo y por eso faltaba donde el repo no lo traía (un caso real 2026-07-11) → promovido a
# global para que aplique en TODA sesión/clon. NO instala globales los hooks REPO-SCOPED restantes
# (sesion-inicio, dod-verificar): esos viven en brain/hooks/ como FUENTE para
# que cada repo los copie a su .claude/ y los cablee (se cargan solo si la sesión INICIA en el repo).
#
# OS-agnóstico: los hooks corren bajo bash en Mac/Linux/Windows(Git Bash). FAIL-SAFE sin jq (avisa;
# los hooks fallan ABIERTO — no bloquean — hasta que instales jq).
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_HOOKS="$SCRIPT_DIR/hooks"
SRC_SKILLS="$SCRIPT_DIR/skills"
SRC_NORMS="$SCRIPT_DIR/norms"

CLAUDE_DIR="$HOME/.claude"
HOOKS_DIR="$CLAUDE_DIR/hooks"
SKILLS_DIR="$CLAUDE_DIR/skills"
GSET="$CLAUDE_DIR/settings.json"
GCLAUDE="$CLAUDE_DIR/CLAUDE.md"

echo "==> claude-brain: instalando cerebro global en $CLAUDE_DIR"
mkdir -p "$HOOKS_DIR" "$SKILLS_DIR"

# Dependencia de los hooks: jq. Sin jq, el git-branch-guard y el gate de delegación fallan ABIERTO.
if ! command -v jq >/dev/null 2>&1; then
  echo "ADVERTENCIA: 'jq' no está en el PATH. Los hooks del cerebro lo REQUIEREN (sin jq los guards"
  echo "  fallan abierto y no bloquean, y no puedo cablear el settings.json). Instálalo y re-corre:"
  echo "    macOS: brew install jq · Debian/Ubuntu: apt install jq · Windows: winget install jqlang.jq"
fi

# ── (a) Copiar hooks de tier global + la lib compartida ──
# Los de tier {global, both} salen del MANIFEST (fuente única) → esta lista ya NO se cura a mano en
# paralelo con la copia por-repo (antídoto a H2: dos listas divergían). El drift-check de test-brain
# verifica que install/uninstall/sincronizar coincidan con el manifiesto.
if [ -f "$SRC_HOOKS/MANIFEST" ]; then
  GLOBAL_HOOKS="$(awk '$1!~/^#/ && NF>=3 && ($2=="global"||$2=="both"){print $1".sh"}' "$SRC_HOOKS/MANIFEST")"
else
  echo "warn: falta $SRC_HOOKS/MANIFEST; no puedo derivar la lista de hooks globales"; GLOBAL_HOOKS=""
fi
for h in $GLOBAL_HOOKS; do
  if [ -f "$SRC_HOOKS/$h" ]; then
    cp -f "$SRC_HOOKS/$h" "$HOOKS_DIR/$h"
    chmod +x "$HOOKS_DIR/$h"
  else
    echo "warn: falta el hook fuente $h"
  fi
done
# Config de clasificación de costo (la lee delegacion-comun.sh en $HOME/.claude/agentes-costo.json)
if [ -f "$SRC_HOOKS/agentes-costo.json" ]; then
  cp -f "$SRC_HOOKS/agentes-costo.json" "$CLAUDE_DIR/agentes-costo.json"
fi
echo "ok: hooks globales + lib + config de costo copiados a $HOOKS_DIR"

# ── (b) Cablear en settings.json (idempotente) ──
# register_hook <event> <matcher> <comando> <patrón-dedupe>
register_hook() {
  local ev="$1" m="$2" cmd="$3" pat="$4" tmp
  command -v jq >/dev/null 2>&1 || { echo "warn: jq no está; agrega el hook '$pat' a $GSET a mano"; return; }
  [ -f "$GSET" ] || echo '{}' > "$GSET"
  tmp="$(mktemp)" || return
  if jq --arg ev "$ev" --arg m "$m" --arg cmd "$cmd" --arg pat "$pat" '
      .hooks = (.hooks // {}) |
      .hooks[$ev] = (.hooks[$ev] // []) |
      if any(.hooks[$ev][]?; ([.hooks[]?.command] | join(" ")) | test($pat))
      then . else .hooks[$ev] += [ (if $m=="" then {} else {"matcher":$m} end) + {"hooks":[{"type":"command","command":$cmd,"shell":"bash"}]} ] end
    ' "$GSET" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then mv "$tmp" "$GSET"; else rm -f "$tmp"; echo "warn: no pude fusionar hook ($pat)"; fi
}

register_hook PreToolUse  Bash 'bash "$HOME/.claude/hooks/git-branch-guard.sh"'    'git-branch-guard'
register_hook PreToolUse  Bash 'bash "$HOME/.claude/hooks/merge-squash-guard.sh"'  'merge-squash-guard'
register_hook PreToolUse  Bash 'bash "$HOME/.claude/hooks/confirmar-merge-develop.sh"' 'confirmar-merge-develop'
register_hook PreToolUse  Bash 'bash "$HOME/.claude/hooks/recordar-dashboard.sh"'  'recordar-dashboard'
register_hook PreToolUse  Bash 'bash "$HOME/.claude/hooks/secret-scan.sh"'         'secret-scan'
register_hook PreToolUse  Bash 'bash "$HOME/.claude/hooks/rama-vieja.sh"'          'rama-vieja'
register_hook PreToolUse  Bash 'bash "$HOME/.claude/hooks/proteger-arbol.sh"'     'proteger-arbol'
register_hook PreToolUse  Task 'bash "$HOME/.claude/hooks/limite-gasto.sh"'        'limite-gasto'
register_hook PreToolUse  Task 'bash "$HOME/.claude/hooks/delegacion-gate.sh"'     'delegacion-gate'
register_hook PostToolUse Task 'bash "$HOME/.claude/hooks/delegacion-registrar.sh"' 'delegacion-registrar'
register_hook PostToolUse Task 'bash "$HOME/.claude/hooks/delegacion-reporte.sh"'   'delegacion-reporte'
# SessionStart sin matcher (matcher vacío ⇒ se omite la clave ⇒ casa TODAS las fuentes: startup/resume/compact/clear)
register_hook SessionStart '' 'bash "$HOME/.claude/hooks/rehidratar-hilo.sh"'       'rehidratar-hilo'
# SessionStart sin matcher — anti-drift: avisa si la copia por-repo del cerebro quedó atrás de la fuente única
register_hook SessionStart '' 'bash "$HOME/.claude/hooks/aviso-drift-cerebro.sh"'   'aviso-drift-cerebro'
# SessionStart sin matcher — da TRIGGER al barrido de ramas locales ya integradas (throttled 24h, en segundo plano)
register_hook SessionStart '' 'bash "$HOME/.claude/hooks/barrer-ramas.sh"'           'barrer-ramas'
# PostToolUse sin matcher (casa TODA tool) — watermark anti-auto-compact: avisa de compactar proactivo
register_hook PostToolUse '' 'bash "$HOME/.claude/hooks/aviso-contexto.sh"'          'aviso-contexto'
echo "ok: hooks cableados en $GSET (git-branch-guard, merge-squash-guard, confirmar-merge-develop, recordar-dashboard, secret-scan, rama-vieja, proteger-arbol, limite-gasto, delegacion-gate/registrar, rehidratar-hilo, aviso-contexto, aviso-drift-cerebro, barrer-ramas)"

# ── (c) Skills genéricas del cerebro (cerrar-slice, orquestar-fanout, …) ──
if [ -d "$SRC_SKILLS" ]; then
  for sk in "$SRC_SKILLS"/*/; do
    [ -f "$sk/SKILL.md" ] || continue
    name="$(basename "$sk")"
    mkdir -p "$SKILLS_DIR/$name"
    cp -f "$sk/SKILL.md" "$SKILLS_DIR/$name/SKILL.md"
    echo "ok: skill $name instalada en $SKILLS_DIR/$name"
  done
fi

# ── (c2) Sello de VERSIÓN del cerebro instalado ──
# El widget (tab Cerebro de las 3 GUIs) lee ~/.claude/.brain-version — NO el repo — para mostrar
# qué versión del brain quedó instalada en ESTA máquina. Se estampa copiando brain/VERSION.
# Idempotente: re-correr simplemente re-estampa la versión actual.
if [ -f "$SCRIPT_DIR/VERSION" ]; then
  cp -f "$SCRIPT_DIR/VERSION" "$CLAUDE_DIR/.brain-version"
  echo "ok: versión del cerebro estampada en $CLAUDE_DIR/.brain-version (v$(tr -d '[:space:]' < "$SCRIPT_DIR/VERSION"))"
else
  echo "warn: falta $SCRIPT_DIR/VERSION; no estampé .brain-version"
fi

# ── (d) Dashboard del cerebro en la memoria GLOBAL (slug del HOME) si falta ──
HOME_SLUG="$(printf '%s' "$HOME" | sed 's/[^a-zA-Z0-9]/-/g')"
DASH="$CLAUDE_DIR/projects/$HOME_SLUG/memory/dashboard_cerebro.md"
if [ ! -f "$DASH" ]; then
  mkdir -p "$(dirname "$DASH")"
  if [ -f "$SRC_HOOKS/dashboard_cerebro.template.md" ]; then
    cp "$SRC_HOOKS/dashboard_cerebro.template.md" "$DASH"
  else
    printf '# Dashboard del cerebro (memoria GLOBAL de esta compu)\n\n## Mapa\n## Infra clave\n## Cabos sueltos\n## Bitacora (mas reciente ABAJO — appendea con >>, append-safe entre sesiones)\n' > "$DASH"
  fi
  echo "ok: dashboard sembrado en $DASH"
else
  echo "ok: dashboard ya existe ($DASH)"
fi

# ── (d2) Entorno de ESTA máquina en la memoria GLOBAL per-máquina (lo detecta y lo siembra) ──
# Norma dura "el entorno de MÁQUINA vive GLOBAL, jamás en un repo": OS/shell/aliases/rutas/runtime son
# de UNA instancia; en un repo mentirían al clonar en otra compu/OS. Por eso viven AQUÍ (memoria global,
# NO viaja por git). El bootstrap lo SIEMBRA con lo que cada quien tenga configurado; Claude lo MANTIENE
# después. IDEMPOTENTE y no-destructivo: si el archivo no existe → lo crea (encabezado curado + bloque
# detectado); si existe CON el bloque marcado <!-- detectado-por-bootstrap --> → refresca SOLO ese bloque;
# si existe SIN marcadores (curado 100% a mano) → NO lo toca (respeta el trabajo del humano/Claude).
ENTORNO="$CLAUDE_DIR/projects/$HOME_SLUG/memory/entorno-esta-maquina.md"

# --- detección (best-effort; todo fail-safe a "?") ---
det_os="$(uname -srm 2>/dev/null || echo '?')"
det_shell_path="${SHELL:-}"; det_shell="$(basename "${det_shell_path:-sh}")"
# Aliases: se resuelven en el shell de LOGIN del usuario (ahí viven sus rc), en modo interactivo (-i)
# para que cargue el .zshrc/.bashrc. Filtramos SOLO líneas 'nombre=...' → el ruido de un rc que imprime
# algo al arrancar (neofetch, etc.) no matchea. 2>/dev/null traga stderr sin tty.
alias_dump=""
if [ -n "$det_shell_path" ] && command -v "$det_shell_path" >/dev/null 2>&1; then
  alias_dump="$("$det_shell_path" -ic 'alias' 2>/dev/null || true)"
fi
alias_of() {  # $1 = comando; imprime a qué apunta el alias, o "" si no hay
  printf '%s\n' "$alias_dump" | sed 's/^alias //' \
    | grep -E "^$1=" | head -1 | sed "s/^$1=//; s/^'//; s/'\$//; s/^\"//; s/\"\$//"
}
alias_bullets=""
any_alias=0
for a in ls rm cp mv grep; do
  v="$(alias_of "$a")"
  if [ -n "$v" ]; then alias_bullets="${alias_bullets}  - \`$a\` → \`$v\`\n"; any_alias=1
  else alias_bullets="${alias_bullets}  - \`$a\` → (sin alias)\n"; fi
done
tool_bullets=""
for t in eza trash rg fd bat docker colima; do
  if p="$(command -v "$t" 2>/dev/null)" && [ -n "$p" ]; then tool_bullets="${tool_bullets}  - \`$t\` ✓ (\`$p\`)\n"
  else tool_bullets="${tool_bullets}  - \`$t\` ✗ (no está)\n"; fi
done

# El bloque DETECTADO (con sus marcadores) — se regenera en cada corrida.
blk="$(mktemp)" || blk=""
if [ -n "$blk" ]; then
  {
    printf '<!-- detectado-por-bootstrap:INICIO — install-brain REFRESCA esto en cada corrida; edita FUERA de estos marcadores -->\n'
    printf '## Detectado por el bootstrap (%s)\n' "$(date +%Y-%m-%d 2>/dev/null || echo '?')"
    printf -- '- **OS / arch:** `%s`\n' "$det_os"
    printf -- '- **Shell de login:** `%s` (`%s`)\n' "$det_shell" "${det_shell_path:-?}"
    printf -- '- **Aliases que pueden morder comandos** (salta el alias con `/bin/<cmd>` o `\\<cmd>`; comilla los globs en zsh):\n'
    printf '%b' "$alias_bullets"
    printf -- '- **Tools clave (presencia):**\n'
    printf '%b' "$tool_bullets"
    printf '<!-- detectado-por-bootstrap:FIN -->\n'
  } > "$blk"
fi

if [ -z "$blk" ]; then
  echo "warn: no pude crear el bloque detectado (mktemp); omito el sembrado de entorno-esta-maquina.md"
elif [ ! -f "$ENTORNO" ]; then
  mkdir -p "$(dirname "$ENTORNO")"
  {
    printf -- '---\nname: entorno-esta-maquina\ndescription: Entorno de ESTA máquina (shell/aliases, OS/arch, runtime local). Es PER-MÁQUINA: vive SOLO en la memoria global, NUNCA en un repo (viajaría por git y mentiría en otra compu/OS). Lo siembra el bootstrap del cerebro y Claude lo va actualizando.\nmetadata:\n  node_type: memory\n  type: reference\n---\n\n'
    printf '# Entorno de ESTA máquina — sembrado por claude-brain\n\n'
    printf '> **REGLA DURA — por qué este archivo es GLOBAL y no de repo:** el entorno de MÁQUINA (OS,\n'
    printf '> shell, aliases, rutas de tu `$HOME`, runtime local: Docker/BD/certs) es de **esta** compu;\n'
    printf '> en un repo viajaría por git y **mentiría** al clonar en otra máquina/OS. Por eso vive AQUÍ\n'
    printf '> (memoria global per-máquina, NO viaja por git). El bootstrap lo **sembró** detectando la\n'
    printf '> config real; **Claude lo MANTIENE** después: agrega tus mañas (BD, certs, despliegue, cachés\n'
    printf '> del navegador) en la sección de abajo, **FUERA** del bloque `detectado-por-bootstrap` (ese\n'
    printf '> lo REFRESCA `install-brain` en cada corrida — no lo edites a mano).\n\n'
    cat "$blk"
    printf '\n## Notas que Claude va agregando\n(Aún vacío. Aquí van las mañas de esta máquina que no detecta el bootstrap: runtime Docker/BD, certs de dev, despliegue local, cachés, etc.)\n'
  } > "$ENTORNO"
  echo "ok: entorno-esta-maquina.md sembrado en $ENTORNO"
elif grep -q 'detectado-por-bootstrap:INICIO' "$ENTORNO"; then
  tmp="$(mktemp)" || tmp=""
  if [ -n "$tmp" ] && awk -v b="$blk" '
      /<!-- detectado-por-bootstrap:INICIO/ { while ((getline l < b) > 0) print l; close(b); skip=1; next }
      /<!-- detectado-por-bootstrap:FIN/    { skip=0; next }
      skip==0 { print }
    ' "$ENTORNO" > "$tmp" && [ -s "$tmp" ]; then
    mv "$tmp" "$ENTORNO"
    echo "ok: entorno-esta-maquina.md — bloque detectado REFRESCADO ($ENTORNO)"
  else
    rm -f "$tmp"; echo "warn: no pude refrescar el bloque detectado en $ENTORNO (lo dejo intacto)"
  fi
else
  echo "ok: entorno-esta-maquina.md ya existe y está CURADO a mano (sin bloque detectado) — no lo toco ($ENTORNO)"
fi
rm -f "$blk" 2>/dev/null || true

# ── (e) Normas globales en ~/.claude/CLAUDE.md (bloque con marcador; REFRESCA, no solo siembra) ──
# Idempotente Y actualizable: si el bloque BEGIN/END ya existe, se REEMPLAZA EN SU LUGAR con la versión
# actual (así las normas nuevas SÍ llegan a instalaciones existentes al re-correr); si no existe, se
# agrega al final. Conserva intacto todo lo que el usuario tenga fuera del bloque.
if [ ! -f "$SRC_NORMS/global-claude-md.md" ]; then
  echo "warn: no encuentro $SRC_NORMS/global-claude-md.md; no inyecté normas"
elif [ -f "$GCLAUDE" ] && grep -q 'BEGIN claude-brain' "$GCLAUDE"; then
  tmp="$(mktemp)" || tmp=""
  if [ -n "$tmp" ] && awk -v src="$SRC_NORMS/global-claude-md.md" '
      /<!-- BEGIN claude-brain/ { skip=1; while ((getline l < src) > 0) print l; close(src) }
      skip==0 { print }
      /<!-- END claude-brain -->/ { skip=0 }
    ' "$GCLAUDE" > "$tmp" && [ -s "$tmp" ]; then
    mv "$tmp" "$GCLAUDE"
    echo "ok: normas globales del cerebro REFRESCADAS en $GCLAUDE (bloque reemplazado en su lugar)"
  else
    rm -f "$tmp"; echo "warn: no pude refrescar el bloque de normas en $GCLAUDE"
  fi
else
  { [ -f "$GCLAUDE" ] && printf '\n'; cat "$SRC_NORMS/global-claude-md.md"; } >> "$GCLAUDE"
  echo "ok: normas globales del cerebro agregadas a $GCLAUDE"
fi

# fetch.prune global: que `git fetch` borre solos los refs remotos ya eliminados (surface de las ramas
# `: gone`). Es lo que mantiene fresco el marcador que usa limpiar-ramas.sh. Idempotente y no destructivo.
if [ "$(git config --global --get fetch.prune 2>/dev/null)" != "true" ]; then
  git config --global fetch.prune true 2>/dev/null && echo "ok: git config --global fetch.prune=true (ramas remotas borradas se limpian solas al hacer fetch)"
fi

echo "listo: cerebro global instalado (hooks + cableado + skill + sello de versión + dashboard + normas)."
echo "       Los hooks repo-scoped (sesion-inicio, dod-verificar) viven en"
echo "       brain/hooks/ como fuente: cópialos al .claude/ de cada repo (se cargan al INICIAR ahí)."
