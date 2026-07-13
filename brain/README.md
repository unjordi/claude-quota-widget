# `brain/` — el cerebro global compartible de Claude Code (doc interna)

Esta carpeta **es** el cerebro: los guardrails, la gobernanza de costo de delegación, la definición
de "LISTO", las normas de git del equipo y una skill genérica de cierre. Todo es **agnóstico de
stack** (no trae nada de .NET ni de repos de la empresa) para que cualquier proyecto lo adopte.

Doc para **contribuidores del cerebro**. El README de la raíz es para *usuarios* (instalar el widget
+ el cerebro); este explica las piezas por dentro, cómo probarlas y cómo instalar/desinstalar.

Todos los hooks corren bajo **bash** en Mac/Linux/Windows (Git Bash) — un solo juego de `.sh`, sin
drift `.sh`/`.ps1`. Dependen de **`jq`**; sin `jq` fallan **abierto** (no bloquean) y el instalador
no puede cablear `settings.json`.

## Layout

```
brain/
├── install-brain.sh      # instalador GLOBAL idempotente (hooks + cableado + skill + dashboard + normas)
├── install-brain.ps1     # lanzador delgado de Windows: verifica bash+jq y delega en install-brain.sh
├── uninstall-brain.sh    # inverso EXACTO del instalador (idempotente)
├── test-brain.sh         # pruebas versionadas y repetibles (contra un $HOME falso aislado)
├── README.md             # este archivo
├── hooks/                # los hooks .sh + agentes-costo.json + dashboard_cerebro.template.md
├── skills/               # skills genéricas: cerrar-slice, orquestar-fanout, checkpoint (SKILL.md c/u)
└── norms/global-claude-md.md  # bloque de normas que se inyecta en ~/.claude/CLAUDE.md
```

## Los hooks — qué hace cada uno

Se dividen en dos **tiers** según su alcance:

### Tier GLOBAL (los instala `install-brain.sh` en `~/.claude/hooks/`, aplican a TODOS los repos)

| Hook | Evento | Qué hace |
|---|---|---|
| `git-branch-guard.sh` | PreToolUse/Bash | Bloquea `git push`/merge a `develop`/`main` y redirige al flujo ramita→MR→develop. |
| `merge-squash-guard.sh` | PreToolUse/Bash | Bloquea un `glab mr merge`/`gh pr merge` sin `--squash` (la ramita colapsa a 1 commit limpio). |
| `confirmar-merge-develop.sh` | PreToolUse/Bash | Exige confirmación EXPRESA antes de integrar a `develop`; autorización súper-explícita para un release a `main`. |
| `proteger-arbol.sh` | PreToolUse/Bash | Protege el árbol de trabajo compartido: bloquea que un agente de fan-out corra `git reset`/`checkout`/`rebase` en el árbol principal (orfanaría commits del orquestador). |
| `secret-scan.sh` | PreToolUse/Bash | Bloquea un `git commit`/`git push` si lo que entra al repo trae un SECRETO (AWS/PEM/Anthropic/OpenAI/GitHub/GitLab/Slack/Google). Escapes: `--no-verify` / `CLAUDE_SKIP_SECRET_SCAN=1`. |
| `rama-vieja.sh` | PreToolUse/Bash | Antes de un `git push`, AVISA (no bloquea) si la ramita está muy atrás de `origin/develop` (base vieja → MR con ruido). Umbral `RAMA_VIEJA_UMBRAL` (def 40). |
| `limite-gasto.sh` | PreToolUse/Task | FRENO DURO: bloquea reclutar agentes cuando el gasto real rebasa un techo (`LIMITE_GASTO_OVERAGE_PCT` def 90 / `LIMITE_GASTO_5H_PCT` def off). Complementa al gate (que pregunta). |
| `recordar-dashboard.sh` | PreToolUse/Bash | Antes de un `git push`, RECUERDA (no bloquea) actualizar el dashboard del cerebro. |
| `rehidratar-hilo.sh` | SessionStart | Al abrir/retomar/compactar, REINYECTA `.claude/memory/hilo-mental-actual.md` si existe (el hilo mental de la tarea en curso). Silencioso si no existe. Lo escribe el skill `checkpoint`. |
| `delegacion-gate.sh` | PreToolUse/Task | Pide consentimiento de COSTO al reclutar un agente (ver modelo de costo abajo). |
| `delegacion-registrar.sh` | PostToolUse/Task | Materializa el "pregunta 1×": registra el consentimiento tras un `ask` aprobado. |
| `delegacion-reporte.sh` | PostToolUse/Task | Tras un `Task`, recuerda el auto-reporte del fan-out (append a bitácora + actualizar estado). |
| `delegacion-comun.sh` | — (lib) | Librería compartida por el gate y el registrador (`source`). Clasifica el nivel de costo y arma la línea de estado de cuota. **No es un hook por sí sola.** |

Config del gate: **`hooks/agentes-costo.json`** (se copia a `~/.claude/`). Clasifica agentes por
regex y fija el umbral de ventana (`umbral_ventana_pct`, def 95).

### Tier REPO-SCOPED (fuente en `hooks/`; NO se instalan globales)

Cada repo los copia a su propio `.claude/` y los cablea en su `settings.json` — se cargan **solo si
la sesión INICIA en ese repo**.

| Hook | Evento | Qué hace |
|---|---|---|
| `sesion-inicio.sh` | SessionStart | Reinyecta rama + norma de git + orden de leer la memoria al abrir/retomar sesión o tras compactar. (Complementa al global `rehidratar-hilo`: éste hace el hilo, aquél el ritual del proyecto.) |
| `precompact-volcar-estado.sh` | PreCompact | **No-op honesto:** PreCompact no puede inyectar contexto ni pedir acción (no hay turno antes de compactar) → sale 0. El "no perder el hilo al compactar" lo hacen el skill `checkpoint` (escribe el hilo) + `rehidratar-hilo` (lo relee). |
| `dod-verificar.sh` | Stop | Bloquea declarar algo "listo" sin evidencia de build/tests verdes + memoria al día. |

## Modelo de costo de delegación (3 niveles + ventana + consentimiento)

Reclutar un agente (`Task`) cuesta según su nivel, que resuelve `delegacion-comun.sh`:

- **gratis** — modelo local (regla `clase:"local"`), sin costo por token.
- **incluido** — Claude **dentro** de tu ventana de 5h (uso < `umbral_ventana_pct`): sin costo
  marginal (ya cubierto por la suscripción).
- **metered** — Claude en **overage** (ventana agotada), API externa de pago, o agente **desconocido**
  (default conservador → se trata como con costo).

El nivel es **window-aware**: se lee el `state.json` del daemon de cuota (fresco, < 30 min). El `ask`
muestra el estado real de tus ventanas, p. ej.
`Ventana 5h: 19% ($2.48 de $45; 3.7M tokens) · Semanal: 57% ($401/$4800)` (la semanal se omite si el
snapshot no la trae).

Cadencia del consentimiento:

- **gratis / incluido** → se pregunta **1× por computadora**, luego silencioso (registro en
  `~/.claude/delegacion-consentimiento.json`, clave `maquina`). Si la ventana se agota, el mismo
  agente pasa a `metered` (cambia la clave `nivel:firma`) → se vuelve a preguntar.
- **metered** → se pregunta **1× por workflow** (`session_id`), luego silencioso el resto del workflow.

Si el usuario NIEGA el `ask`, el `Task` no corre → `delegacion-registrar` no dispara → no se registra
nada (la próxima vez vuelve a preguntar). Sin `jq` o sin snapshot fresco → se trata como `metered`
(pregunta): fail-safe de gasto.

## Cómo probar

```sh
bash brain/test-brain.sh      # o: just test-brain
```

`test-brain.sh` NO toca tu `~/.claude`: corre todo contra un `$HOME` FALSO aislado (`mktemp`, se borra
al salir). Cubre: (a) `bash -n` de todos los hooks + `jq empty` de los JSON; (b) el gate de delegación
(gratis/incluido/metered/desconocido, el ciclo gate→registrar→gate-silencioso y la transición
dentro/fuera de la ventana); (b5) el CONTRATO de salida por-evento (p. ej. `precompact` NO debe emitir
`hookSpecificOutput` — el bug que `bash -n` no ve) + `rehidratar-hilo`; (c) idempotencia de `install-brain.sh` corrido 2× (cada hook 1× en
`settings.json`, 1 solo bloque de normas) y limpieza por `uninstall-brain.sh`.

La **CI** (`.github/workflows/ci.yml`) repite en cada push/PR el `bash -n` de todos los `.sh`, el
`jq empty` de los `.json` y `shellcheck --severity=error`. El cerebro se auto-valida antes de
distribuirse.

## Instalar / desinstalar

```sh
# Instalar (idempotente; re-correr es seguro)
bash brain/install-brain.sh                 # Mac/Linux
pwsh -File brain\install-brain.ps1          # Windows (delega en bash brain/install-brain.sh)

# … o por el instalador maestro de la raíz (widget + cerebro):
./install.sh                # todo
./install.sh --no-brain     # solo el widget/daemon, sin el cerebro

# Desinstalar (idempotente; inverso EXACTO del instalador)
bash brain/uninstall-brain.sh
./uninstall.sh              # widget + cerebro
./uninstall.sh --no-brain   # solo el widget, deja el cerebro
```

`uninstall-brain.sh` quita los hooks globales, `agentes-costo.json`, la skill y el bloque de normas
de `~/.claude/CLAUDE.md`, y **des-cablea de `settings.json` solo las entradas que apuntan a esos
hooks** (deja intactas las demás, vía `jq`). **NO borra datos del usuario**: conserva el dashboard,
el registro de consentimiento de delegación y toda la memoria de proyectos.

## Con `just` (desde la raíz)

```sh
just install-brain      # bash brain/install-brain.sh
just uninstall-brain    # bash brain/uninstall-brain.sh
just test-brain         # bash brain/test-brain.sh
```
