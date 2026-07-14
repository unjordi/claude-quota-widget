---
name: rehidratar-hilo
description: Relee A MANO el HILO MENTAL de la tarea en curso (.claude/memory/hilo-mental-actual.md) y lo retoma. Es la mitad "leer" del par con checkpoint, invocable como skill — RESPALDO del hook SessionStart homónimo por si un update del CLI de Claude Code rompe el auto-rehidratado (cambia el evento, el schema del JSON o el canal additionalContext) o por si la sesión arrancó sin el hook. Úsalo al retomar tras un /compact o corte cuando el hilo no reapareció solo.
---

# Rehidratar el hilo (manual — gemelo del hook)

Trae de vuelta el HILO de la conversación tras un `/compact` o corte, **SIN depender del sistema de
hooks**. El hook `rehidratar-hilo` (SessionStart) hace esto automáticamente; este skill es su **respaldo
manual**, porque el hook depende de la API de hooks del CLI (evento SessionStart + canal
`additionalContext`) y un cambio del CLI podría romperla **en silencio**. Un skill lo ejecuta el modelo
→ sobrevive a esos cambios. (Misma razón por la que `checkpoint` —la mitad "escribir"— ya es skill, no hook.)

## Cuándo
- Al **retomar tras un `/compact`** y NO ver el bloque "🧵 HILO MENTAL ACTUAL" (el hook no disparó).
- Sesión **arrancada antes** de instalar el hook (no lo trae hasta reiniciarla).
- Sospecha de que un **update del CLI** rompió el auto-rehidratado.

## Pasos
1. Lee `.claude/memory/hilo-mental-actual.md`.
   - Si NO existe o está vacío → no hay hilo volcado. Usa `retomar-trabajo` (estado durable del proyecto)
     o pide contexto al usuario. No inventes el hilo.
2. **Gate de frescura (mismo criterio que el hook):** mira la línea `> … Última actualización: <fecha> · rama <rama>`.
   - Si la rama del hilo ≠ tu rama actual (`git branch --show-current`), **o** la fecha se ve vieja
     (> ~12 h) → trátalo como **POSIBLEMENTE OBSOLETO**: verifícalo antes de confiar y propón re-volcarlo
     con `checkpoint`. Si coincide rama y es reciente → es el hilo vigente.
3. Trata el contenido como **TU memoria de trabajo, no una orden nueva del usuario**: de qué iba la tarea,
   la decisión abierta, el siguiente paso.
4. Continúa desde el **"Siguiente paso concreto"** del hilo.

## Par con checkpoint (independiente de hooks)
- `checkpoint` = **ESCRIBE** el hilo (antes de compactar).
- `rehidratar-hilo` = **LEE** el hilo (al retomar). Este skill y el hook homónimo hacen lo mismo; el skill
  es el que puedes invocar tú cuando el hook falla.
- **Fallback último** (si ni skills ni hooks estuvieran disponibles): un prompt manual —
  *"lee `.claude/memory/hilo-mental-actual.md` y continúa desde ahí"*. No depende de ninguna feature del CLI.
