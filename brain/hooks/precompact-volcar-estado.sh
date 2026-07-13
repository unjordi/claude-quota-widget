#!/usr/bin/env bash
# precompact-volcar-estado.sh — PreCompact hook.
#
# FIX 2026-07-13: este hook ANTES intentaba INYECTAR un recordatorio ("volcá el estado a la memoria")
# vía hookSpecificOutput.additionalContext. Dos problemas, ambos de raíz:
#   1) PreCompact NO soporta ese canal → Claude Code RECHAZABA la salida ("Hook JSON output
#      validation failed — Invalid input") y el recordatorio nunca llegaba. El hook estaba MUERTO.
#   2) Aunque el canal existiera, sería inútil: entre que PreCompact dispara y la compactación
#      ocurre NO hay turno del modelo → no se le puede pedir que "vuelque ahora". El
#      "recordatorio de último momento" era imposible desde el día 1; el crash solo lo hizo visible.
#
# PreCompact SOLO puede: bloquear la compactación (decision:"block") o dejarla proceder (exit 0).
# Su stdout se DESCARTA. Así que este hook ya no intenta lo imposible: sale 0 limpio (permite
# compactar) y documenta dónde vive el mecanismo REAL de "no perder el hilo al compactar":
#   • el skill `checkpoint` VUELCA el hilo a .claude/memory/hilo-mental-actual.md (proactivo), y
#   • el hook `rehidratar-hilo.sh` (SessionStart, canal FIABLE) lo REINYECTA al retomar/compactar.
#
# OJO disciplina: el auto-compact (contexto lleno) NO avisa y este hook no puede salvarte el hilo
# → corre `checkpoint` PROACTIVAMENTE en pausas naturales, no confíes en un aviso de último momento.
#
# Se conserva cableado como punto de extensión documentado (y para no romper configs existentes).
set -u
cat >/dev/null 2>&1 || true   # drena el payload de PreCompact en stdin; no lo usamos
exit 0
