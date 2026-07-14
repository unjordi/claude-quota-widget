# Plan de refactor — Desacoplar LÓGICA de MECANISMO (hooks ↔ libs ↔ skills)

> Estado: **borrador a revisión** (2026-07-14). Origen: idea de unjordi ("¿y si abstraemos la lógica de
> los hooks a skills, que los hooks las invoquen pero también estén disponibles?") + hallazgos del auditor
> de flowcharts (#1 dod débil en plantilla, #2 falso positivo de comillas, #3 copias por-repo desfasadas,
> #4 secret-scan ausente sin bootstrap). Este plan ataca los cuatro de raíz con una sola reorganización.

## 1. El principio que manda: la asimetría hook ≠ skill
- **Hook** = `.sh` que el CLI corre SOLO, en un evento, SIN turno del modelo. Es el ÚNICO que puede
  **DENEGAR/BLOQUEAR** (deny en PreToolUse, block en Stop). Esa fuerza viene de correr fuera del turno.
- **Skill** = markdown que EJECUTA EL MODELO con su juicio. Requiere turno. **NO puede bloquear** —
  es guía que el modelo decide seguir.
- **Corolario duro:** el ENFORCEMENT (los dientes) NO se puede mover a un skill sin perderlo. Lo que SÍ
  se abstrae es la **LÓGICA/cómputo** (a una lib `.sh`) y los **nudge/inyección** (a un skill gemelo).

## 2. Arquitectura en 3 capas
```
  Capa LÓGICA  →  lib/*.sh   (funciones puras, sin decidir I/O; testeables solas)
  Capa MECANISMO → hooks/*.sh (wrapper delgado: lee stdin → llama lib → emite decisión/inyección)
  Capa MANUAL   →  skills/    (gemelo de los nudge; dry-run opcional de los enforcement)
```
`delegacion-comun.sh` YA es exactamente este patrón (lib compartida por delegacion-gate y -registrar).
El refactor lo generaliza al resto.

### 2.1 Capa LÓGICA — libs propuestas (funciones puras)
- **`lib/git-analiza.sh`**: `despoja_comillas(cmd)` (⇒ arregla #2 para TODOS los git-hooks de un tiro),
  `es_push_a_base(cmd)`, `es_merge_mr(cmd)`, `destino_de_mr(cmd)` (glab/gh), `merge_base_integracion()`.
- **`lib/secretos.sh`**: `patrones()`, `escanea(diff)` → hits redactados. (Consumible por el hook Y por un
  dry-run manual.)
- **`lib/dod.sh`**: `es_estatus_o_pregunta(msg)`, `hay_claim(msg)` (con el CLAIM_RE rico), `visual_a_ciegas(turn)`,
  `toco_codigo(turn)` (incl. edición por Bash). ⇒ una sola definición ⇒ la plantilla deja de tener una `dod`
  DÉBIL distinta (arregla #1).
- **`lib/contexto.sh`**: `lineas(transcript)`, `baseline_leer/escribir`, `banda(delta)`.
- **`lib/hilo.sh`**: `leer_hilo(root)`, `frescura(hilo, rama)` (mtime + rama). Consumible por el hook
  rehidratar-hilo Y por el skill gemelo (misma frescura en ambos).

### 2.2 Capa MECANISMO — hooks = wrappers delgados
Cada hook queda en ~10-15 líneas: dedupe-clause + `source lib` + leer JSON stdin + llamar la fn + emitir
`permissionDecision`/`additionalContext`. La FUERZA (deny/block) se queda aquí. Cero lógica de negocio
duplicada.

### 2.3 Capa MANUAL — skills
- **Gemelos de nudge** (no bloquean → el skill hace lo mismo que el hook):
  - `rehidratar-hilo` ✅ (ya hecho) — lee el hilo a mano.
  - `sesion-inicio` → skill gemelo (reinyecta rama+norma+memoria a mano).
  - `recordar-dashboard` → opcional (recordatorio manual).
- **Dry-run de enforcement** (opcional; el skill CORRE la lib y REPORTA, sin dientes):
  - `revisar-secretos`, `revisar-cierre` (dod), `revisar-flujo-git`. Útiles para chequear ANTES de
    intentar la acción, sin depender de que el hook dispare.

## 3. Anti-drift (mata el hallazgo #3) — la pieza con mecanismo propio
Abstraer a libs NO basta: la lib igual viaja en el `.claude/` del repo (para clones sin bootstrap) y puede
envejecer. El mecanismo que lo cierra:
- **`sincronizar-cerebro.sh <repo>`**: copia hooks+libs+skills del brain → `.claude/` del repo destino
  (fuente ÚNICA = el brain). Los archivos del repo se GENERAN, no se editan a mano.
- **Check de drift en `test-brain.sh` / CI**: por cada archivo del cerebro presente en un repo, aseverar
  que es idéntico (o marca-versión ≥) al del brain; si difiere → FAIL. Así el desfase se detecta, no se
  descubre en una auditoría meses después.
- Decisión asociada (**#4**): cablear `secret-scan` (y demás global-only relevantes) TAMBIÉN por-repo, para
  que un clon sin bootstrap no pierda un guard de seguridad — o documentar explícitamente que dependen del bootstrap.

## 4. Fases (cada una = un slice, ramita→MR→develop, test verde entre fases)
0. **Alcance** — cerrar esta lista (qué hooks, qué libs, qué gemelos, qué dry-runs). ← decisión de unjordi.
1. **`lib/git-analiza.sh`** + adelgazar los 3 git-hooks a wrappers. *Incluye el fix #2 (despoja_comillas).*
2. **`lib/dod.sh`** + unificar la `dod` genérica y la .NET en un wrapper c/u sobre la MISMA lib. *Cierra #1.*
3. **`lib/secretos.sh`**, **`lib/contexto.sh`**, **`lib/hilo.sh`** + sus wrappers.
4. **Gemelos-skill** faltantes (sesion-inicio; recordar-dashboard opc.) + **dry-run** opcionales.
5. **Anti-drift**: `sincronizar-cerebro.sh` + check de drift en test-brain/CI. *Cierra #3 y decide #4.*

## 5. Riesgos / caveats (no negociables)
- **Refactor de comportamiento CONSTANTE**: la suite `test-brain.sh` (hoy 115/0) es el contrato — debe
  quedar verde en cada fase; si un test cambia de expectativa, es señal de que NO fue puro refactor.
- **Guard-integrity (P0)**: es reorganización, NO afloja candados. Los dientes (deny/block) se quedan en
  hooks. Cambiar un candado sigue exigiendo OK explícito de unjordi para ESE candado.
- **Resolución de path de la lib**: el wrapper debe encontrar su lib tanto en global (`~/.claude/hooks/`)
  como por-repo (`.claude/hooks/`) — `source "$(dirname "$0")/lib/..."` robusto y con fail-open si falta.
- **Bash puro** (sin python/node en hooks).
- La escalera de resiliencia resultante: `hook` (auto+enforce) → `skill` (manual, sin enforce) → `lib`
  invocable como comando → `prompt` a mano (no depende de ninguna feature del CLI).

## 6. Qué NO cambia
Los flujos ⓪–⑦ del mapa (la lógica de decisión) son los MISMOS; solo cambia DÓNDE vive el código y qué
tiene gemelo manual. El mapa se re-anota (badge "⚙ lib" donde aplique), no se rehace.
