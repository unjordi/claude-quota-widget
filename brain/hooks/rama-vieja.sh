#!/usr/bin/env bash
# rama-vieja.sh — PreToolUse/Bash: antes de un `git push`, AVISA (NO bloquea) si la ramita arrastra
# una base vieja — está muchos commits detrás de origin/develop. Una ramita rezagada hace que el MR
# traiga ruido y conflictos; el aviso sugiere rebasar antes de seguir. Umbral configurable
# (RAMA_VIEJA_UMBRAL, def 40). No avisa sobre develop/main. Fail-open sin jq/git (no estorba).
set -u
command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0
cmd=$(jq -r '.tool_input.command // ""' 2>/dev/null)
# Ignora un 'git push' que aparezca como DATO entrecomillado (grep, descripción de MR, prueba).
unquoted=$(printf '%s' "$cmd" | sed "s/'[^']*'//g; s/\"[^\"]*\"//g")
printf '%s' "$unquoted" | grep -qE 'git[[:space:]]+push' || exit 0

dir="${CLAUDE_PROJECT_DIR:-.}"
git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
case "$branch" in develop|main|HEAD|"") exit 0 ;; esac   # solo ramitas de trabajo

git -C "$dir" rev-parse --verify -q origin/develop >/dev/null 2>&1 || exit 0
behind=$(git -C "$dir" rev-list --count "HEAD..origin/develop" 2>/dev/null)
[ -z "$behind" ] && exit 0
umbral="${RAMA_VIEJA_UMBRAL:-40}"
if [ "$behind" -ge "$umbral" ] 2>/dev/null; then
  jq -n --arg b "$branch" --arg n "$behind" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:("AVISO (rama vieja — no bloquea): la ramita \($b) está \($n) commits DETRÁS de origin/develop. Arrastra una base vieja → el MR puede traer ruido/conflictos. Considera actualizarla antes de seguir: git fetch origin && git rebase origin/develop (resuelve y repushea con --force-with-lease). Si el push es a propósito, ignora este aviso.")}}'
fi
exit 0
