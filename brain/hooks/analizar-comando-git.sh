# analizar-comando-git.sh — LIB compartida (NO es un hook; se hace `source`). Razona sobre un comando
# git/glab/gh para los git-guards (git-branch-guard · merge-squash-guard · confirmar-merge-develop) →
# UNA sola lógica, dejan de divergir (antídoto al drift H2/H13). bash-3.2-safe. El consumidor verifica
# jq/git si los necesita. Vive junto a los hooks (como delegacion-comun.sh) → viaja en el mismo copy.
# shellcheck shell=bash

# Quita literales entre comillas simples o dobles → un "git push a develop" dentro de un mensaje de
# commit / dato de un grep / doc NO dispara los guards. (Fix #2 · H13.)
acg_despoja_comillas() { printf '%s' "$1" | sed "s/'[^']*'//g; s/\"[^\"]*\"//g"; }

# Quita el VALOR de --repo/-R (p. ej. "-R org/develop") para que un repo cuyo nombre termine en
# /develop|/main NO genere un falso positivo de destino. (H11.)
acg_sin_flag_repo() { printf '%s' "$1" | sed -E 's/(--repo|-R)[[:space:]=]+[^[:space:]]+//g'; }

# Raíz y rama actual del repo del PROYECTO (CLAUDE_PROJECT_DIR), no del cwd del hook.
acg_rama_actual() { git -C "${CLAUDE_PROJECT_DIR:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null; }

# ¿el comando contiene un `git push`?
acg_es_push() { printf '%s' "$1" | grep -qE 'git[[:space:]]+push([[:space:]]|$)'; }

# ¿nombra develop/main como DESTINO explícito del push, en el MISMO segmento (no cruza ; && ||),
# precedido por espacio/:/'/' (no matchea feat/develop-x)?
acg_push_destino_base() {
  printf '%s' "$1" | grep -qE 'git[[:space:]]+push[^;&|]*[[:space:]:/](main|develop)([[:space:]]|$)'
}

# ¿el push va SIN un refspec de rama explícito? (pelón, o solo remoto, o `HEAD` → empuja la RAMA
# ACTUAL). Heurística: tras `git push`, quitando opciones (-x/--x/--x=val) y `HEAD`, quedan ≤1
# posicionales (a lo más el remoto). (H1.)
acg_push_sin_refspec() {
  local seg rest tok posargs=0
  seg=$(printf '%s' "$1" | grep -oE 'git[[:space:]]+push[^;&|]*' | head -1)
  [ -n "$seg" ] || return 1
  rest=$(printf '%s' "$seg" | sed -E 's/^git[[:space:]]+push[[:space:]]*//; s/(-o|--push-option)[[:space:]=]+[^[:space:]]+//g')
  for tok in $rest; do
    case "$tok" in
      -*)   : ;;                       # opción → ignora
      HEAD) : ;;                       # HEAD = la rama actual, no un destino explícito
      *)    posargs=$((posargs+1)) ;;  # posicional (remoto o refspec de rama)
    esac
  done
  [ "$posargs" -le 1 ]
}

# ¿el comando EMPUJARÍA a develop/main? — explícito (nombra la rama) O pelón estando parado en
# develop/main. Opera sobre el cmd SIN comillas ni --repo. Cierra H1 (+ H11/H13). Requiere git para
# el caso pelón; sin git cae a fail-open en ese caso (backstop = ramas protegidas server-side).
acg_push_toca_base() {
  local u; u=$(acg_sin_flag_repo "$(acg_despoja_comillas "$1")")
  acg_es_push "$u" || return 1
  acg_push_destino_base "$u" && return 0
  if acg_push_sin_refspec "$u"; then
    case "$(acg_rama_actual)" in main|develop) return 0 ;; esac
  fi
  return 1
}

# ¿el comando mergea un MR/PR nombrando develop·main como destino? (para el bloqueo de release-a-main
# de git-branch-guard: mismo comportamiento de antes, pero sobre cmd sin comillas ni --repo → H11/H13).
acg_merge_menciona_base() {
  local u; u=$(acg_sin_flag_repo "$(acg_despoja_comillas "$1")")
  printf '%s' "$u" | grep -qE '(glab[[:space:]]+mr[[:space:]]+merge|gh[[:space:]]+pr[[:space:]]+merge)[^;&|]*[[:space:]:/](main|develop)([[:space:]]|$)'
}
