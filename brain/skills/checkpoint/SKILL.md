---
name: checkpoint
description: Volcado del estado efímero a memoria durable para poder compactar (o cerrar sesión) sin perder el hilo, en DOS NIVELES. LIGERO (pausas naturales, punto de retorno rápido) sobrescribe hilo-mental-actual.md (de qué va la tarea AHORA) y, si el proyecto avanzó, actualiza estado-proyecto.md + bitácora. COMPLETO (OBLIGATORIO antes de cualquier /compact —manual o anunciado por el aviso de contexto— y cada ~2h en corridas largas) agrega el PLAN COMPLETO con el CÓMO, lo RESUELTO HOY y la COSECHA DURABLE a memorias/skills. Es el "volcado compartido" que cerrar-slice §2 también hace. Ante la duda de nivel: COMPLETO.
---

# Checkpoint — vaciar lo efímero a memoria durable (sin fricción)

Un **checkpoint** vuelca lo que solo vive en el contexto del chat (frágil: se pierde al compactar) a
archivos durables en disco, para que **compactar cuanto quieras NO cueste el hilo**. Es la mitad
"escribir" del par; la mitad "leer" la hace el hook `rehidratar-hilo` (SessionStart) al retomar.

> **Por qué existe.** Al compactar se pierden DOS cosas y solo una tenía casa. El **estado del
> proyecto** (hecho/pendiente/decidido) ya vivía en `estado-proyecto.md`/`bitacora.md`. El **HILO de
> la conversación** (qué razonamos AHORA, la decisión a medio cocinar, el siguiente paso, el porqué)
> no vivía en ningún lado durable → se degradaba en cada resumen del LLM. `hilo-mental-actual.md` es
> su casa. Con el hilo en disco, la compactación deja de ser el único portador del contexto real.

## Los DOS NIVELES (y cómo elegir)

- **LIGERO** — pausas naturales, punto de retorno rápido. El hilo terso (en qué estamos / decisión
  abierta / siguiente paso / hilos sueltos) + estado-proyecto/bitácora si avanzó. Cuesta segundos.
- **COMPLETO** — **OBLIGATORIO antes de cualquier `/compact`** (manual, o cuando el hook
  `aviso-contexto` anuncie que viene) **y cada ~2h en corridas largas/nocturnas**. Además del hilo
  terso, el `hilo-mental-actual.md` crece con TRES secciones (PLAN COMPLETO con el CÓMO · RESUELTO
  HOY · COSECHA DURABLE — ver abajo) y la cosecha a memorias/skills se hace COMO PARTE del checkpoint.

**Criterio de elección:** ¿viene un compact? ¿llevas >2h de corrida? ¿la implementación que sigue es
crítica? → **COMPLETO**. ¿Pausa casual entre sub-pasos? → ligero. **Ante la duda, COMPLETO**:
sub-volcar cuesta una noche (pasó de verdad); sobre-volcar cuesta 2 minutos.

## Por qué el nivel COMPLETO funciona (anatomía del descubrimiento)

Nació de un descubrimiento de unjordi (2026-07-18): antes de un compact crítico, en vez del checkpoint
terso, le pidió a su Claude — *"puedes hacer una memoria super temporal con TODO lo que tienes planeado
ahorita, todos los pendientes, el mecanismo y detalles de cómo los quieres resolver, y toda la lista de
cosas que resolvimos hoy? y actualizar las memorias y skills de etl? haciendo eso ya podemos hacer el
compact con calma"* — y funcionó "perfecto de perfectolandia". La anatomía de por qué:

En el contexto viven **3 tipos de estado**, y el resumen del compact solo trata bien uno:
1. **La narrativa** — lo único que el resumen conserva (con pérdida).
2. **Las intenciones procedimentales** — el PLAN con su CÓMO. Lo MÁS frágil: un resumen conserva
   "pendiente: X" pero amputa "lo iba a resolver con Y porque Z". Por eso el PLAN se vuelca completo.
3. **Lo RESUELTO** — decisiones ya tomadas. Si no se escriben, **reviven como pendientes fantasma**
   tras compactar (caso real: frenaron una noche entera de ETL). Por eso la sección anti-fantasma.

El volcado **en las PROPIAS palabras del modelo** permite re-instanciarse releyendo textual, en vez de
reconstruir desde un resumen ajeno (= confabular). Y "actualizar memorias/skills" **desaloja del canal
volátil lo que tiene casa durable** → reduce lo que el compact puede siquiera perder.

## Cuándo correrlo
- **Antes de un `/compact` manual** — lo más importante. **Nivel COMPLETO, sin excepción.**
- Cuando el aviso de contexto (`aviso-contexto`) anuncie que el compact viene → **COMPLETO**.
- Cada **~2h en corridas largas/nocturnas** → **COMPLETO** (el auto-compact no avisa).
- En una **pausa natural** (terminaste un sub-paso, vas a cambiar de tema) → ligero basta.
- Cuando quieras dejar un **punto de retorno** por si la sesión se corta → ligero basta.
- ⚠️ El **auto-compact** (contexto lleno) NO avisa, y `precompact` NO puede salvarte el hilo
  (PreCompact no tiene canal para inyectar ni para pedirte actuar, y no hay turno entre el hook y la
  compactación). Por eso el checkpoint es **proactivo**, no de último momento: si vienes trabajando
  rato, vuelca aunque no vayas a compactar todavía.

## Qué hace (el volcado)
1. **El HILO (siempre, ambos niveles).** Sobrescribe `.claude/memory/hilo-mental-actual.md` (créalo si
   no existe: `mkdir -p .claude/memory`). No es log ni backlog — es "de qué va ESTO ahora mismo".
   Estructura (las tres últimas secciones SOLO en nivel COMPLETO):
   ```markdown
   # Hilo mental actual
   > Se SOBRESCRIBE (no se appendea). Última actualización: <FECHA> · rama <rama> · nivel <ligero|COMPLETO>.

   ## En qué estamos AHORA
   <1-3 líneas: la tarea viva y su porqué>
   ## Decisión abierta / lo que razonamos
   <la pregunta a medio cocinar, opciones sobre la mesa>
   ## Siguiente paso concreto
   <la próxima acción — con punto de entrada al código si aplica>
   ## Hilos sueltos / no olvidar
   <pequeños pendientes de contexto que el resumen perdería>

   <!-- ▼ SOLO nivel COMPLETO ▼ -->
   ## PLAN COMPLETO (con el CÓMO)
   <TODO lo planeado, ítem por ítem: qué + el MECANISMO de resolución pensado + detalles, gotchas y
    porqués — a fidelidad completa, en TUS propias palabras. NO telegráfico: es lo que te vas a
    releer para re-instanciarte tras el compact.>
   ## RESUELTO HOY (no reabrir)
   <decisiones tomadas + su porqué en una línea cada una. El ANTI-FANTASMA: lo que está aquí NO se
    re-pregunta ni se re-descubre después de compactar.>
   ## COSECHA DURABLE (hecha en esta tanda)
   <qué se promovió EN ESTE checkpoint a su casa durable — memorias del proyecto, skills tocados —
    con sus rutas. La promoción se hace COMO PARTE del checkpoint completo, no "después".>
   ```
   Pon la **FECHA real**: `rehidratar-hilo` la muestra al retomar para que juzgues si el hilo quedó viejo.
2. **El estado del proyecto (solo si avanzó).** Igual que `cerrar-slice §2`: mueve ítems en
   `estado-proyecto.md` (hecho/pendiente/decidido) y **appendea UNA línea al FINAL** de `bitacora.md`
   con `>>` (`printf '%s\n' '- …' >> bitacora.md`), **no** con un Edit que reescriba (así varias
   sesiones no se pisan). Si no avanzó nada del proyecto, este paso se salta — checkpoint puede ser
   solo-hilo.
3. **doc = realidad (vistazo).** Si en esta tanda cambiaste comportamiento/config/rutas, actualiza la
   doc que lo describe en la MISMA tanda (no lo dejes para después).
4. **La cosecha durable (solo COMPLETO).** Antes de cerrar el volcado, pregúntate: *¿qué de lo que
   traigo en contexto ya tiene casa durable?* — un aprendizaje que va a una memoria del proyecto, un
   gotcha que va a un skill, una decisión de infra que va a su doc. **Promuévelo AHORA, como parte del
   checkpoint** (no lo agendes), y regístralo en `## COSECHA DURABLE` con sus rutas. Lo que ya vive en
   disco es lo único que el compact no puede perder.

## Qué NO es
- **No es `cerrar-slice`.** Checkpoint es SOLO el volcado; no verifica build/tests, no abre MR, no
  cosecha aprendizajes de cierre de slice. Cuando de verdad terminaste un slice, usa `cerrar-slice`
  (que hace este mismo volcado + esas etapas). Checkpoint es el "guarda punto" de en medio — ligero o
  completo, sigue siendo un punto de retorno, no un cierre.
- **No sustituye la disciplina.** Ningún hook puede correrlo por ti (PreCompact no tiene turno) — es
  una skill que TÚ invocas. `aviso-contexto` te lo RECUERDA cuando el contexto sube; correrlo (y al
  nivel correcto) sigue siendo tuyo.

## Compartido vs local
`hilo-mental-actual.md` es memoria de trabajo **VOLÁTIL** (se sobrescribe seguido) y personal de tu
stream de trabajo. En repos **COMPARTIDOS** conviene **gitignorearlo** (per-dev, como los `*.local.md`)
para no generar conflictos de merge entre devs. El estado durable COMPARTIDO son
`estado-proyecto.md`/`bitacora.md`. El continuo cross-sesión del hilo (que es lo que este skill
protege) es para TU hilo, no el del equipo.
