---
name: checkpoint
description: Volcado LIGERO del estado efímero a memoria durable para poder compactar (o cerrar sesión) sin perder el hilo. Sobrescribe hilo-mental-actual.md (de qué va la tarea/conversación AHORA) y, si el proyecto avanzó, actualiza estado-proyecto.md + bitácora. Es el "volcado compartido" que cerrar-slice §2 también hace. Invócalo en pausas naturales, antes de un /compact, o cuando quieras dejar un punto de retorno.
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

## Cuándo correrlo
- **Antes de un `/compact` manual** — lo más importante.
- En una **pausa natural** (terminaste un sub-paso, vas a cambiar de tema).
- Cuando quieras dejar un **punto de retorno** por si la sesión se corta.
- ⚠️ El **auto-compact** (contexto lleno) NO avisa, y `precompact` NO puede salvarte el hilo
  (PreCompact no tiene canal para inyectar ni para pedirte actuar, y no hay turno entre el hook y la
  compactación). Por eso el checkpoint es **proactivo**, no de último momento: si vienes trabajando
  rato, vuelca aunque no vayas a compactar todavía.

## Qué hace (el volcado)
1. **El HILO (siempre).** Sobrescribe `.claude/memory/hilo-mental-actual.md` (créalo si no existe:
   `mkdir -p .claude/memory`). No es log ni backlog — es "de qué va ESTO ahora mismo". Estructura:
   ```markdown
   # Hilo mental actual
   > Se SOBRESCRIBE (no se appendea). Última actualización: <FECHA> · rama <rama>.

   ## En qué estamos AHORA
   <1-3 líneas: la tarea viva y su porqué>
   ## Decisión abierta / lo que razonamos
   <la pregunta a medio cocinar, opciones sobre la mesa>
   ## Siguiente paso concreto
   <la próxima acción — con punto de entrada al código si aplica>
   ## Hilos sueltos / no olvidar
   <pequeños pendientes de contexto que el resumen perdería>
   ```
   Pon la **FECHA real**: `rehidratar-hilo` la muestra al retomar para que juzgues si el hilo quedó viejo.
2. **El estado del proyecto (solo si avanzó).** Igual que `cerrar-slice §2`: mueve ítems en
   `estado-proyecto.md` (hecho/pendiente/decidido) y **appendea UNA línea al FINAL** de `bitacora.md`
   con `>>` (`printf '%s\n' '- …' >> bitacora.md`), **no** con un Edit que reescriba (así varias
   sesiones no se pisan). Si no avanzó nada del proyecto, este paso se salta — checkpoint puede ser
   solo-hilo.
3. **doc = realidad (vistazo).** Si en esta tanda cambiaste comportamiento/config/rutas, actualiza la
   doc que lo describe en la MISMA tanda (no lo dejes para después).

## Qué NO es
- **No es `cerrar-slice`.** Checkpoint es SOLO el volcado; no verifica build/tests, no abre MR, no
  cosecha aprendizajes. Cuando de verdad terminaste un slice, usa `cerrar-slice` (que hace este mismo
  volcado + esas etapas). Checkpoint es el "guarda punto" ligero de en medio.
- **No sustituye la disciplina.** Ningún hook puede correrlo por ti (PreCompact no tiene turno) — es
  una skill que TÚ invocas.

## Compartido vs local
`hilo-mental-actual.md` es memoria de trabajo **VOLÁTIL** (se sobrescribe seguido) y personal de tu
stream de trabajo. En repos **COMPARTIDOS** conviene **gitignorearlo** (per-dev, como los `*.local.md`)
para no generar conflictos de merge entre devs. El estado durable COMPARTIDO son
`estado-proyecto.md`/`bitacora.md`. El continuo cross-sesión del hilo (que es lo que este skill
protege) es para TU hilo, no el del equipo.
