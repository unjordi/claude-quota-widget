#!/usr/bin/env bash
# limite-gasto.sh — PreToolUse/Task: FRENO DURO cuando NO queda capacidad en NINGÚN lado. A diferencia
# de delegacion-gate (que PREGUNTA por la ventana de 5h y tú decides), este BLOQUEA reclutar un agente
# SOLO en la condición COMBINADA: tu ventana de 5h está AGOTADA **Y** tu overage NO tiene holgura
# (topado o deshabilitado). Ahí no hay ni cupo del plan ni saldo → el agente moriría a medias, mejor no
# arrancarlo. Lee el state.json del daemon de cuota (el mismo que alimenta el widget).
#
# CLAVE (el hueco viejo): NO frena por overage SOLO. Con suscripción + ventana fresca, overage al 100%
# NO te para (trabajas cubierto por el plan). Y con ventana agotada pero saldo de overage, tampoco
# frena — ahí delegacion-gate te PREGUNTA y tú decides. Solo la AND de ambos agotados dispara el freno.
# Umbrales configurables:
#   LIMITE_GASTO_5H_PCT       (ventana considerada agotada; def 99)
#   LIMITE_GASTO_OVERAGE_PCT  (overage considerado sin holgura; def 100)
# Fail-open: sin jq, sin snapshot, o snapshot rancio (>30 min) NO bloquea (nunca frena a ciegas).
set -u
command -v jq >/dev/null 2>&1 || exit 0
input=$(cat 2>/dev/null || true)
[ "$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" = "Task" ] || exit 0

snap=""
for c in "${XDG_CACHE_HOME:-$HOME/.cache}/claude-brain/state.json" "$HOME/Library/Caches/claude-brain/state.json"; do
  [ -f "$c" ] && { snap="$c"; break; }
done
[ -z "$snap" ] && exit 0
[ -n "$(find "$snap" -mmin +30 2>/dev/null)" ] && exit 0   # rancio → no frena

five_pct=$(jq -r '.five_hour.percent // empty' "$snap" 2>/dev/null)
over_util=$(jq -r '.extra_usage.utilization // empty' "$snap" 2>/dev/null)
over_on=$(jq -r '.extra_usage.enabled // false' "$snap" 2>/dev/null)
lim_5h="${LIMITE_GASTO_5H_PCT:-99}"          # ventana considerada AGOTADA (>= esto)
lim_over="${LIMITE_GASTO_OVERAGE_PCT:-100}"  # overage considerado SIN HOLGURA (>= esto)

# (1) ¿ventana de 5h agotada?
ventana_agotada=0
[ -n "$five_pct" ] && awk -v a="$five_pct" -v b="$lim_5h" 'BEGIN{exit !(a+0>=b+0)}' && ventana_agotada=1

# (2) ¿overage SIN holgura? Tiene holgura SOLO si está habilitado Y (sin dato de util | util < tope).
#     Deshabilitado, o topado, o util>=tope → sin holgura. Ante duda (habilitado sin dato) → asumimos
#     holgura (no frenamos a ciegas; para eso está el gate que pregunta).
overage_sin_holgura=1
if [ "$over_on" = "true" ]; then
  if [ -z "$over_util" ] || awk -v a="$over_util" -v b="$lim_over" 'BEGIN{exit !(a+0<b+0)}'; then
    overage_sin_holgura=0
  fi
fi

# FRENO solo con la AND: ventana agotada Y overage sin holgura → no hay capacidad en ningún lado.
[ "$ventana_agotada" = 1 ] && [ "$overage_sin_holgura" = 1 ] || exit 0

_ov_txt=$([ "$over_on" = "true" ] && echo "overage al ${over_util:-?}% (topado)" || echo "overage deshabilitado")
jq -n --arg f "$five_pct" --arg o "$_ov_txt" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:("FRENO DURO (limite-gasto): SIN capacidad en ningún lado — tu ventana de 5h está agotada ("+$f+"%) Y "+$o+". Reclutar agentes ahora los dejaría A MEDIAS (Anthropic los mata al no haber ni cupo del plan ni saldo de overage). NO reintentes en automático. Opciones: (a) espera el reset de tu ventana de 5h; (b) mete saldo / sube el tope de overage; (c) hazlo TÚ, sin delegar. Umbrales: LIMITE_GASTO_5H_PCT / LIMITE_GASTO_OVERAGE_PCT.")}}'
exit 0
