#!/usr/bin/env bash
# entorno-maquina-guard.sh — PreToolUse/Bash. MECANISMO de la norma dura "el entorno de MÁQUINA vive
# GLOBAL, jamás en un repo". AVISA (NO bloquea) cuando un `git commit` está por meter al `.claude/memory/`
# de un repo algo específico-de-esta-máquina — que viajaría por git y MENTIRÍA al clonar en otra compu/OS.
# Lo machine-specific vive SOLO en la memoria GLOBAL per-máquina (entorno-esta-maquina.md, que NO viaja
# por git); un repo documenta el proyecto de forma PORTABLE/CONDICIONAL (nombrado `correr-en-local.md`).
#
# Dispara con DOS señales de alta precisión, ambas acotadas a archivos bajo `.claude/memory/`:
#   (1) FILENAME: un `entorno-maquina.md` (el nombre-trampa que la norma prohíbe → renómbralo).
#   (2) CONTENIDO agregado: líneas nuevas con marcas machine-specific — aliases personales
#       (`alias x=` / `→ eza|trash|…`), rutas absolutas de un `$HOME` (`/Users/x/`, `/home/x/`,
#       `C:\Users\`), o "Rosetta" SIN condicional (si/if/cuando/Apple Silicon/arm64/opt-in).
# Precisión > exhaustividad: solo mira lo que ENTRA (staged) en archivos de memoria del repo; cualquier
# otro Bash pasa al instante. NUNCA bloquea (additionalContext), así no frena trabajo — solo nombra el
# smell y a dónde va. Fail-open sin jq/git.
#
# Vive en brain/hooks/ (fuente); tier `both` (viaja per-repo Y global). dedupe doble-cableado abajo.
set -u

# dedupe: si soy la copia del REPO y la copia GLOBAL existe, cedo (evita doble aviso). En un clon SIN
# bootstrap la del repo sí corre. NO-debilitante: sigue avisando 1×.
case "$0" in "$HOME/.claude/hooks/"*) : ;; *) [ -f "$HOME/.claude/hooks/$(basename "$0")" ] && exit 0 ;; esac

command -v jq >/dev/null 2>&1 || exit 0
cmd=$(jq -r '.tool_input.command // ""' 2>/dev/null)
[ -z "$cmd" ] && exit 0
# Ignora menciones entrecomilladas (un `git commit` dentro de un grep/echo/mensaje) — como los otros guards.
unquoted=$(printf '%s' "$cmd" | sed "s/'[^']*'//g; s/\"[^\"]*\"//g")
printf '%s' "$unquoted" | grep -qE 'git[[:space:]]+commit' || exit 0

command -v git >/dev/null 2>&1 || exit 0
dir="${CLAUDE_PROJECT_DIR:-.}"
git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Candidatos: archivos .md bajo .claude/memory/ que ENTRAN en este commit (staged). Si el commit trae
# -a/--all, suma también los tracked modificados sin stagear (git los staged al commitear).
staged=$(git -C "$dir" diff --cached --name-only 2>/dev/null)
allflag=0
printf '%s' "$unquoted" | grep -qE '(^|[[:space:]])(-a|--all|-[a-zA-Z]*a[a-zA-Z]*)([[:space:]]|$)' && allflag=1
[ "$allflag" = 1 ] && staged="$staged
$(git -C "$dir" diff --name-only 2>/dev/null)"

mem_files=$(printf '%s\n' "$staged" | grep -E '(^|/)\.claude/memory/[^/]*\.md$' | grep -v '\.local\.md$' | sort -u)
[ -z "$mem_files" ] && exit 0

# (1) FILENAME-trampa
bad_name=$(printf '%s\n' "$mem_files" | grep -E '(^|/)entorno-maquina\.md$')

# (2) CONTENIDO machine-specific en líneas AGREGADas (staged; o worktree si vino por -a)
added_of() {  # $1 = archivo → solo líneas agregadas (sin la cabecera +++)
  local f="$1" d
  d=$(git -C "$dir" diff --cached -- "$f" 2>/dev/null)
  [ -z "$d" ] && [ "$allflag" = 1 ] && d=$(git -C "$dir" diff -- "$f" 2>/dev/null)
  printf '%s\n' "$d" | grep -E '^\+' | grep -vE '^\+\+\+'
}
content_hits=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  added=$(added_of "$f")
  [ -z "$added" ] && continue
  hit=""
  printf '%s\n' "$added" | grep -qE '(^|[^[:alnum:]])alias[[:space:]]+[A-Za-z0-9_-]+=|→[[:space:]]*`?(eza|trash|bat|nvim|colima)' && hit="alias/tool personal"
  printf '%s\n' "$added" | grep -qE '/Users/[A-Za-z0-9._-]+/|/home/[A-Za-z0-9._-]+/|[A-Za-z]:[\\]Users[\\]' && hit="${hit:+$hit, }ruta absoluta de un \$HOME"
  # "Rosetta" sin una palabra condicional en la MISMA línea
  if printf '%s\n' "$added" | grep -iE 'rosetta' | grep -viqE 'si |if |cuando|apple silicon|arm64|opt-in|condicional|solo si|only if' >/dev/null 2>&1; then
    printf '%s\n' "$added" | grep -iE 'rosetta' | grep -iqE 'si |if |cuando|apple silicon|arm64|opt-in|condicional|solo si|only if' || hit="${hit:+$hit, }Rosetta sin condicional"
  fi
  [ -n "$hit" ] && content_hits="${content_hits}    · ${f##*/}: $hit\n"
done <<EOF
$mem_files
EOF

[ -z "$bad_name" ] && [ -z "$content_hits" ] && exit 0

MSG="AVISO (norma dura 'el entorno de MÁQUINA vive GLOBAL, jamás en un repo'): este git commit mete al .claude/memory/ de ESTE repo contenido que parece específico-de-esta-máquina — en un repo viaja por git y MIENTE al clonar en otra compu/OS."
[ -n "$bad_name" ] && MSG="$MSG || FILENAME-trampa: $(printf '%s' "$bad_name" | tr '\n' ' ')— la norma prohíbe 'entorno-maquina.md' en un repo; si es cómo correr EL PROYECTO, hazlo PORTABLE/CONDICIONAL y renómbralo a 'correr-en-local.md'."
[ -n "$content_hits" ] && MSG="$MSG || CONTENIDO machine-specific en:\n$(printf '%b' "$content_hits")   Lo personal-de-instancia (aliases, rutas de tu \$HOME, Rosetta/colima sin condicional) va SOLO en la memoria GLOBAL per-máquina (~/.claude/projects/<slug-del-HOME>/memory/entorno-esta-maquina.md, que NO viaja por git). En el repo deja solo lo portable/condicional ('si estás en Apple Silicon: platform: linux/amd64')."
MSG="$MSG || Esto AVISA, no bloquea: si de verdad es portable, ignóralo."

jq -n --arg m "$MSG" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$m}}'
exit 0
