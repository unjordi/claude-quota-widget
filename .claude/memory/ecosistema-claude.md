---
name: ecosistema-claude
description: KB VIVA de todo lo aprendido sobre el ecosistema Claude (CLI, chat/desktop, API, hooks, cuotas, sesiones) al desarrollar claude-brain
type: reference
---

# Conocimiento del ecosistema Claude (KB viva)

> Base de conocimiento que **CRECE**: cada cosa no-obvia que descubrimos sobre cómo se comporta
> Claude Code (CLI), Claude chat/desktop, la API, hooks, cuotas y sesiones — sobre todo lo destilado
> al construir el **claude-brain**. Un ítem = un hallazgo, con su **evidencia + fecha**. Añade abajo.

## Autenticación / cuentas
- **El login de Claude Code es GLOBAL a la máquina** — un solo credential store en `~/.claude/`, **NO
  por-terminal ni por-sesión.** Consecuencia clave: si haces logout/login a OTRA cuenta (aunque sea en
  otra terminal), **las sesiones ya vivas toman la credencial/cuota nueva en sus SIGUIENTES requests** —
  el switch es **transparente para la sesión en curso** (no hay que resumear en otra terminal). Truco
  práctico: al toparte el límite de una cuenta, cambiar a una 2ª cuenta deja **seguir la MISMA sesión**
  sin overage. Prueba lógica de que el switch ya aplicó: si la cuenta vieja estuviera topada sin overage,
  Claude **no podría responder** — que responda demuestra que ya está sobre la cuota fresca.
  *(2026-07-15, verificado en vivo.)*

## Cuotas / límites
- **El mensaje "claude-opus-4-8 temporarily unavailable — auto mode cannot determine safety of Bash" NO
  significa que Bash esté roto:** significa que **se agotó un quota de tokens** (el clasificador de
  seguridad de Bash es una llamada al modelo que no puede correr sin cuota). **Read/Edit/Write siguen
  funcionando** (no pasan por el clasificador); solo **Bash** queda bloqueado, hasta el reset O hasta
  cambiar de cuenta / habilitar overage. Confirmación rápida: el widget claude-brain muestra el semanal
  y/o la ventana de 5h al 100%. *(2026-07-15.)*
- Hay dos ventanas **independientes**: **5 h** y **semanal (7 d)**. El widget las muestra por separado
  (+ desglose por modelo). Toparse la semanal no topa necesariamente la de 5h y viceversa.

## Compactación / contexto
- **`PreCompact` NO puede inyectar `additionalContext`** — el CLI rechaza el JSON con "Hook JSON output
  validation failed — (root): Invalid input". Solo `Stop`/`SubagentStop`/`UserPromptSubmit`/`PostToolUse`
  aceptan `additionalContext`. Por eso el hook `precompact-volcar-estado` fue **RETIRADO**; el "no perder
  el HILO al compactar" lo hacen el skill `checkpoint` (ESCRIBE el hilo antes) + el hook `rehidratar-hilo`
  en **SessionStart** (LEE el hilo al retomar — canal FIABLE). *(Confirmado de nuevo en cps 2026-07-15:
  un repo con el hook viejo aún cableado tiraba ese error en cada `/compact`; era ruido, no rotura — el
  compact ocurría y el hilo rehidrataba igual.)*
- Tras compactar, el harness ordena **retomar en SILENCIO** (sin recap ni "continúo") — es feature, no
  bug; el anuncio visible solo aplica si el usuario invoca el skill `rehidratar-hilo` a mano.

## Sesiones
- Los transcripts viven en `~/.claude/projects/<slug>/<id>.jsonl` — **por-máquina, NO en el repo**
  (gitignored: pesan MBs y traen datos sensibles). El **slug se DERIVA del cwd** (ruta con `/`→`-`).
- **Resumear una sesión en otra máquina** = copiar su `.jsonl` al **mismo slug** del destino + `claude
  --resume <id>` (requiere que el cwd coincida). El widget claude-brain tiene *mover sesión entre slugs*
  y *renombrar*, pero **sync cross-máquina de transcripts NO está construido** (idea: sincronizarlos por
  el canal Drive que el widget ya usa para stats — FUERA de git).
