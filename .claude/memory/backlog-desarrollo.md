# Backlog de desarrollo del widget

> Ideas de feature pedidas por unjordi, aún NO implementadas. Un ítem = un slice (ramita → MR →
> develop, squash). Al arrancar uno, muévelo a "en curso"; al cerrarlo con QA, bórralo de aquí y
> deja la huella en `bitacora.md`. Ordenado por lo más reciente arriba.

## [2026-07-12] Pain-points de los transcripts de plantilla/claude-brain (auditoría forense #2)
**Método:** 3 agentes read-only barrieron 8 transcripts (~35.8k líneas) de los slugs plantilladotnet +
claude-quota-widget, **incluida ESTA sesión**. Deduplicado contra la auditoría de cps (sección aparte) y
contra lo YA arreglado hoy (dod-reina #121, gobernanza #122, gotchas !97, proteger-arbol #119, ruleset
main=merge-commit, test anti-ciclos #123) y lo YA capturado (hedging/inventar-causas/desconfianza).
Solo va lo **NUEVO**. `[HECHO]`=leído · `[INF]`=inferido. (Nota: puede chocar trivialmente al mergear con
el MR de pain-points de cps —ambos insertan aquí arriba—; se resuelve conservando las dos secciones.)

> **TRIAGE (unjordi, 2026-07-12):** **P1–P8 = READY** (aprobados para atacar). **P9–P16 = HELD**
> (parqueados, pendientes de decisión — NO arrancar sin que unjordi los nombre).

### 🔴 ALTA
- **P1. `dod-verificar` da FALSOS POSITIVOS — y #121 pudo empeorarlo** [HECHO]. Disparó ~10× en una
  sesión, ≥2 demostrablemente falsos (saltó cuando Claude solo PREGUNTABA por un UUID, sin declarar
  cierre). **AUTO-CRÍTICA:** mi #121 (B1) AMPLIÓ el `CLAIM_RE` (agregó cerrado/🏁/✅) → puede subir la
  tasa de falsos positivos que este hallazgo señala. Mitigado por el escape de STATUS_RE + gate de
  código-tocado + conf, pero la precisión es baja. → **mejora:** no disparar si el último turno del
  asistente es una PREGUNTA o no hay verbo de cierre en 1ª persona; **añadir a test-brain una suite de
  frases (cierre vs estatus)** que fije la precisión y evite regresiones. Un guard con falsos positivos
  pierde credibilidad. Casa: `dod-verificar` + test-brain.
- **P2. Fan-out de migración REHACE en vez de PORTAR** [HECHO]. Agentes reconstruían componentes desde
  cero en vez de traer el código VIVO de cps ("lo rehicieron", "no necesitas inventar, revisa cómo se
  hizo en cps"). → regla dura en `aplicar-plantilla-a-proyecto` + prompt de fan-out: "PORTAR = copiar el
  artefacto que YA funciona y adaptarlo; PROHIBIDO rehacer si existe fuente; **cita el archivo origen** y
  léelo ANTES de escribir". Casa: skill aplicar-plantilla + contrato de agente en orquestar-fanout.
- **P3. Instalador multi-OS: "releaseado" se rompió en CADA máquina nueva** [INF]. PATH no exportado,
  CRLF en `.sh`, SDK ausente, ccusage fuera del PATH de systemd, rename roto en Linux, ícono genérico —
  cada plataforma (Windows/Cachy/Mac ajeno) destapó un supuesto no cubierto. → para un producto
  clonable/instalable, el verde técnico en UNA máquina NO es LISTO: **checklist de instalador** (PATH en
  zsh+bash+Windows, normalizar EOL de `.sh`, deps bundled/verificadas) como gate antes de declarar un
  release instalable. Casa: skill de release del widget / Definición de LISTO para "producto instalable".

### 🟡 MEDIA
- **P4. Heartbeat de orquestación** [HECHO]: con agentes en vuelo Claude quedaba mudo y el usuario hacía
  "ping? ping?"/"todo bien?". → `orquestar-fanout`: emitir un latido de estado mientras hay agentes
  corriendo (no solo el volcado a bitácora al cerrar). Señal de desvío: el usuario preguntó "¿sigues?".
- **P5. `merge-squash-guard` en GitHub (`gh`): ¿detecta destino `main`?** [INF]. El guard citó `glab` en
  un repo `gh` y el fail-safe conservador exigió squash a un release develop→main (que va SIN squash). →
  **verificar** que la detección de target `main` funciona para `gh pr merge` (no solo glab); si no, el
  fail-safe bloquea un release legítimo. Casa: `merge-squash-guard`.
- **P6. Cross-repo: "cambia el folder a otro repo" → NO cargan hooks ni CLAUDE.md** [HECHO]. Lección vieja
  (2026-07-04) que RESURGIÓ al delegar con "cambia de folder". → prohibir ese patrón en instrucciones de
  delegación; INICIAR el agente en el repo destino; recordatorio si un agente opera en un cwd distinto al
  de arranque. Casa: `orquestar-fanout` + posible guard.
- **P7. No persistir una PREFERENCIA durable de UN mensaje ambiguo** [HECHO]. Claude guardó "los merges a
  develop los hace unjordi" al revés de la queja real ("es queja, no orden"), y osciló 3× en la política.
  → regla: no escribir preferencia durable a partir de un solo mensaje ambiguo sin confirmar el sentido;
  + línea canónica en la norma: "el gate `confirmar-merge-develop` ≠ 'no puedes' — con OK explícito Claude
  mergea develop por CLI+squash, SIN clics del usuario". Casa: norma + estilo.
- **P8. Meta-patrón: una norma-prosa SIN hook = el usuario es el enforcement** [HECHO]. Pasó con
  auto-reporte y doc=realidad (se arreglaron volviéndolos hooks #114/#116). → principio para el brain:
  **toda norma de higiene/cierre nace con su mecanismo (hook/gate/paso operativo), o no se cumple sola.**
  Corolario inverso (P1): un hook mal dirigido genera falsos positivos que desgastan la confianza.

### ⏸ HELD — parqueados por unjordi (P9–P16, pendientes de decisión)
- **P9. AGENTS.md se DEGRADÓ al templatizar** [HECHO]: el template quedó con <½ de las filas de cps/cenam
  y perdió reglas GENÉRICAS (no solo el dominio). → al derivar un "template" de un concreto, distinguir
  mecánicamente "dominio (quitar)" de "regla genérica (conservar)"; un diff PORTAR-vs-OK-EXCLUIDO como
  método por defecto. Casa: skill de instanciar/templatizar.
- 🟢 BAJA (gotchas / notas reutilizables):
- **P10. Repos personales (GitHub) sin los hooks del template** → caen en el clasificador auto-mode
  genérico → fricción recurrente en git (merge/borrado/config). → sembrar develop+hooks al tocarlos, o
  documentar qué acciones esperar bloqueadas ahí. [HECHO]
- **P11. Append-`>>` para bitácora/dashboard es norma pero NO se aplicó** (se usó Edit y chocó con "File
  modified since read") → volverlo PASO OPERATIVO del cierre, no solo principio. [HECHO] (ya reforzado en
  cerrar-slice; verificar que se siga).
- **P12. Un agente nuevo (`~/.claude/agents/`) NO está disponible en la sesión que lo crea** — requiere
  reiniciar sesión. [HECHO] Nota durable en entorno-maquina.
- **P13. QA de no-regresión visual**: un fix de layout rompía otro ya arreglado ("ya estaba centradísimo,
  ¿qué pasó?"). → tras tocar layout compartido, re-verificar los 2-3 ajustes previos del mismo componente. [INF]
- **P14. Offline: smoke acordado** (cargar en línea → apagar webapi → recargar) como criterio antes de
  declarar avance; no auto-verificable sin el navegador. [HECHO]
- **P15. zsh: citar args con `?`/`*`/`-R`** (se globbearon/malinterpretaron). [HECHO] · **gh `--json`**: usar
  campos verificados (`state`, no `merged`). [HECHO] · **guard bloquea su propio comando de prueba** por el
  literal `glab mr merge` → que ignore literales en heredocs/strings de test. [HECHO]
- **P16. Avisar cuando contenido que el usuario está viendo vive en una ramita SIN mergear** (el backlog
  "desapareció" al volver a develop — no era pérdida, era el working tree rotando). [HECHO]

**Ya-capturado/ya-arreglado (NO se re-agrega, solo se anota):** verde-técnico→LISTO (núcleo, dod-reina +
norma); squash-a-main (ruleset main=merge-commit); doc=realidad (#116); auto-reporte (#114); overstep de
autorización no-transitiva (ya en CLAUDE.md); hedging/inventar-causas/desconfianza (feedback en dashboard).

## [2026-07-11] No desechar el último OAuth bueno al fallar la lectura (tener≠nunca-tener)
**Qué (unjordi, 2026-07-11):** hoy el fetch reescribe `state.json` COMPLETO y sin condición en cada
tick (~9 min); el `basis` se recalcula desde cero (`basis: (if $usage!=null then "oauth" else "cost")`).
Si la lectura OAuth falla —token vencido, un 401, o un parpadeo de red que tumba el `curl`— esa corrida
**aplasta el % real con el estimado local (cost-basis)**, aunque el número real de hace minutos siga
siendo válido. Síntoma real: la Cachy con el token vencido 17h mostraba 5h=0% / semanal=1.1% mientras la
Mac (OAuth vivo) mostraba el real 98% / 50% — MISMA cuenta, números distintos solo por el basis.

**El principio (unjordi, textual):** *"no es lo mismo tener OAuth y perderlo a nunca haberlo tenido; si lo
tuvo y lo perdió, no debería desechar a lo wey."* → tres estados, no dos:
- **Nunca tuvo OAuth** (máquina fresca / sin login) → el estimado LOCAL (cost-basis) es lo mejor que hay. OK.
- **Tuvo OAuth y lo perdió, RECIENTE** (dentro de la ventana 5h/semanal) → **cargar hacia adelante el último
  % real marcado como STALE** (`basis:"oauth-stale"` + `stale_since`), NO aplastarlo con el estimado local.
- **Tuvo OAuth y lo perdió, VIEJO** (fuera de ventana → el número ya no significa) → degradar, pero aun así
  decir "último real: X% a las HH:MM, no puedo refrescar", nunca un 0% con cara de verdad.

**El patrón ya existe a medias:** líneas 42‑50 de `src/bin/claude-brain-fetch` YA cargan hacia adelante el
`resets_at` real del último OAuth cuando cae a fallback (un "próximo lunes" adivinado estaría mal). Solo hay
que **extender ese mismo mecanismo a los porcentajes** (y a `cost_usd`/`tokens`), con el timestamp de staleness.

**Unifica 3 cabos que salieron el mismo día** (NO tres ítems sueltos):
1. **No clobberear** el último-OAuth-bueno (este ítem, el núcleo).
2. **Auto-refresh del token**: el daemon podría refrescar con el `refresh_token` guardado (`claudeAiOauth.refreshToken`)
   en vez de esperar a que el humano abra `claude` — así una máquina inactiva no se queda ciega. (Evaluar riesgo:
   el CLI y Claude.app comparten el slot de credencial; un refresh a destiempo no debe pisar identidad — ya hay
   guard de account-mismatch.)
3. **Marcar visualmente** el modo stale/fallback en las 3 GUIs (⚠ / "estimado local" / "último real HH:MM")
   en vez de un número confiado. Un 0% confiado tapando un 98% real es la trampa de UX que hay que matar.

**Dónde toca:** `src/bin/claude-brain-fetch` + `macos/bin/claude-brain-fetch` (la lógica de basis + carry-forward);
Windows `QuotaService` (misma lógica en C#); el badge de estado en las 3 GUIs (Swift/QML/WinForms). **No urge**
(el caso se auto-cura al refrescar el token), pero es correctez de datos: el widget no debe mentir con cara de verdad.

## [2026-07-11] Arreglar el extractor de Chats (formato del app de escritorio cambió)
**Qué:** `bin/chats-extract.js` devuelve `[]` aunque el IndexedDB del app de escritorio TIENE datos
(~2.5 MB, app corriendo con chats activos) → la pestaña Chats se auto-oculta. El app de Claude **cambió
el formato de su cache** (update); el parser Snappy+V8/Blink de `chats-extract.js` ya no reconoce las
conversaciones. **NO es pérdida de datos** (los chats están en el app + claude.ai); es que nuestro lector
quedó desfasado. **Qué hacer:** re-ingeniería-inversa del nuevo formato (como el build original — un
snapshot del IndexedDB + inspeccionar el envelope/estructura) y actualizar `chats-extract.js`. Aplica a
las 3 plataformas (el extractor es compartido). **Fragilidad inherente:** leer un cache privado no
documentado se rompe con cada update del app → considerar si vale la pena mantenerlo vs. deprecar la
pestaña Chats. unjordi: al backlog, no urge (2026-07-11).

## [2026-07-10] Inicializar / reconciliar el cerebro GLOBAL + barrer todos los slugs desde el widget
**Qué:** una opción en la pestaña **Cerebro** (extiende la 🩹 curita, que hoy solo cura el cerebro
GLOBAL de la máquina) que:
1. **Inicializa/llena el dashboard-global** (`~/.claude/projects/<slug-del-HOME>/memory/dashboard_cerebro.md`)
   si falta o está vacío — sembrándolo de la plantilla (el bootstrap ya lo hace; esto lo EXPONE en el widget).
2. **Barre TODOS los slugs de proyecto** que el widget conoce y, para cada uno que mapee a un repo git,
   verifica/instala su cerebro: correr su `bootstrap-claude.sh` (instala los hooks GLOBALES de máquina +
   enlaza) y confirmar que su `.claude/` (hooks, settings.json, memoria) esté completo. **Reporta** cuáles
   repos les falta algo y ofrece arreglarlos.

**Por qué:** hoy no hay forma, desde el widget, de VER ni ARREGLAR el estado del cerebro de CADA proyecto
repartido por la máquina — solo del global. Al onboardear a un colega (caso Felipe, 2026-07-10) o al
retomar una máquina, se quiere un "reconciliar todo" de un clic.

**Matices / retos:**
- El widget ya conoce los slugs (`stats.projects` + `~/.claude/projects/<slug>/`), y el fetch ya
  normaliza slug → nombre de repo vía `~/.claude.json` (`.projects`). Reusar esa resolución para hallar
  la RUTA del repo de cada slug.
- **No silencioso:** no todo slug es un repo git clonable, y correr `bootstrap-claude.sh` en cada repo es
  invasivo → el patrón debe ser **detectar + reportar + ofrecer arreglar** (opt-in por repo), no auto-correr.
- Las versiones del cerebro entre repos pueden diferir (plantilla vs claude-brain) — reportar divergencias
  en vez de pisarlas a ciegas.
- **Dónde toca:** `BrainInspector`/`healBrain` de la pestaña Cerebro (macOS `PopoverView.swift`, Linux
  `main.qml`, Windows `PopupForm.cs`), + una pasada nueva que itere slugs→repos.

## HECHO (fuera del backlog) — 2026-07-11
- **Contexto al renombrar sesión (+ "Sugerir nombre")** y **Mover sesión entre slugs** →
  IMPLEMENTADOS en las 3 GUIs (#104/#106, en develop; `bin/sessions-extract.js` +summary/+slug y
  `bin/session-move.js`). QA visual parcial de unjordi (macOS). Detalle en `claude-quota-widget.md`
  (sección 2026-07-11) y bitácora del dashboard. Decisión del "cwd": el move SÍ reescribe el cwd
  interno (con respaldo) para que `--resume` quede coherente; no hay "memorias por-sesión" que mover.
