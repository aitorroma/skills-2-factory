# Proyecto: Skills Portal — Agent Teams + Subagentes

## Propósito

Este proyecto define un flujo para crear, validar y publicar Skills 2.0 con Agent Teams y subagentes.

Las skills se escriben para que un agente las ejecute, no para enseñar a una persona. La pregunta clave es simple: ¿con esta carpeta de skill el agente puede completar la tarea sin inventar pasos ni pedir datos innecesarios?

---

## Arquitectura

7 agentes, 4 sesiones de Claude.

```
Agent Team (4 sesiones):
  Lead          → tu sesión de Claude Code
  Arquitecto    → teammate (sesión independiente)
  Revisor       → teammate (sesión independiente)
  Optimizador   → teammate (sesión independiente)

Subagentes (corren dentro del Lead, sin sesión propia):
  Investigador  → busca docs oficiales, devuelve research
  MCP2CLI Toolsmith → evalúa si una API/MCP debe resolverse con mcp2cli
  Validador     → ejecuta validate.sh, devuelve PASS/FAIL
  Publisher     → publica en portal y verifica
```

**Por qué esta separación:**
- Los teammates necesitan debatir entre sí (SendMessage). Los subagentes no.
- Los teammates NO pueden lanzar subagentes (no tienen Task tool). Solo el Lead puede.
- Los subagentes ejecutan una tarea acotada y devuelven resultado. No necesitan sesión propia.

---

## Flujo de trabajo

```
FASE 1 — Solo el Lead
1. Lead recibe el request del usuario
2. Lead detecta ambigüedades bloqueantes → pregunta antes de arrancar
3. Lead lanza Investigador (subagente, SIN team_name) → recibe research
3.1. Si el request incluye OpenAPI, MCP o generación de tools desde APIs: Lead lanza MCP2CLI Toolsmith (subagente, SIN team_name)

FASE 2 — El equipo entra con contexto
4. Lead crea task list con dependencias
5. Lead spawna Arquitecto + Revisor + Optimizador (teammates, CON team_name)
   → incluye research del Investigador en el spawn prompt
6. Arquitecto diseña la carpeta de skill y escribe `SKILL.md` usando la información investigada
7. Revisor cuestiona → debate con Arquitecto si hay problemas
8. Optimizador comprime → elimina lo que Claude no necesita y mueve detalle sobrante a recursos opcionales

FASE 3 — Validación y publicación
9. Lead lanza Validador (subagente, SIN team_name) → revisa resultado
10. Si pasa: Lead lanza Publisher (subagente, SIN team_name) → verifica en portal
```

**Instrucción crítica para el Lead:** Los subagentes (Investigador, MCP2CLI Toolsmith, Validador, Publisher) se lanzan con el Task tool **SIN el parámetro team_name**. Los teammates (Arquitecto, Revisor, Optimizador) se lanzan **CON team_name**.

---

## Roles del Agent Team

### Lead

**Responsabilidad:** Coordinar el pipeline. No diseña ni opina sobre el contenido.

**Antes de crear las tareas, DEBE preguntar si falta:**
- El proveedor o herramienta exacta (ej: "¿Cloudflare DNS, Google Cloud DNS o Route53?")
- Información que no puede ser un placeholder (ej: si el scope es ambiguo)

**No pregunta** si la información faltante puede ser un placeholder genérico (`<DOMAIN>`, `<PROJECT_ID>`, `<API_KEY>`).

**Solo cuando tiene contexto suficiente:** lanza primero el subagente Investigador con el brief completo. Cuando el Investigador devuelve resultados, crea la task list e incluye el research en el spawn prompt de los teammates. No spawna el equipo sin el research listo.

**Si la skill depende de OpenAPI o MCP:** lanza además el subagente MCP2CLI Toolsmith y añade su salida al contexto del Arquitecto antes de que diseñe la estructura final.

**Condición de salida:** termina cuando la skill está publicada y verificada en el portal. No agrega tareas adicionales ni "mejoras" no solicitadas.

---

### Arquitecto

**Responsabilidad:** Diseñar la estructura de la skill y escribir el `SKILL.md` como instrucciones para Claude.

**Antes de escribir:** usa el research que el Lead incluyó en el spawn prompt. Si el research no cubre algún caso borde, lo indica explícitamente — no inventa comandos sin fuente.

**Cómo diseña la skill:**
- `SKILL.md` obligatorio.
- `agents/openai.yaml` recomendado por defecto.
- `scripts/` si una parte requiere ejecución determinista o se reescribe siempre igual.
- `references/` si hay documentación de soporte que Claude debe cargar solo cuando haga falta.
- `assets/` solo si hay archivos que la skill reutiliza como salida.

**Cómo escribe:**
- Para un agente, no para humanos. No explicar conceptos base que el agente ya conoce.
- Comandos exactos con flags, orden y prerequisitos reales.
- Decisiones operativas explícitas: cuándo preguntar, cuándo seguir y cuándo abortar.
- Placeholders para todo valor específico del usuario: `<DOMAIN>`, `<PROJECT_ID>`, `<ZONE_NAME>`, `<YOUR_IP>`, `<API_KEY>`.
- Los valores del request del usuario (ej: "example.com") solo van en ejemplos, nunca en comandos reales.
- Cada paso debe dejar claro qué verificar antes de pasar al siguiente.
- Si el body se hace largo, mover detalle a `references/` y dejar en `SKILL.md` solo navegación y decisiones.
- Si existe `agents/openai.yaml`, debe ser coherente con la finalidad y trigger de `SKILL.md`.

**Condición de salida:** termina cuando la carpeta de skill está definida, `SKILL.md` está escrito y el Revisor aprobó. No itera más ni "mejora" sin que el Revisor lo solicite explícitamente.

---

### Revisor

**Responsabilidad:** Verificar que Claude ejecutaría correctamente estas instrucciones.

**Preguntas que se hace:**
- ¿Hay instrucciones ambiguas que Claude podría malinterpretar?
- ¿El `description` es específico sobre QUÉ hace la skill Y CUÁNDO usarla?
- ¿Hay valores hardcodeados que deberían ser placeholders?
- ¿El Investigador encontró fuente primaria para cada comando? Si no, marcar esos pasos.
- ¿Hay casos borde que Claude necesita manejar y no están cubiertos?
- ¿La distribución entre `SKILL.md`, `references/` y `scripts/` minimiza contexto sin perder precisión?
- ¿`agents/openai.yaml` refleja correctamente nombre visible, resumen corto y prompt por defecto?

**Si encuentra problemas:** manda mensaje directo al Arquitecto con objeciones específicas. El Arquitecto corrige y notifica. El Revisor re-revisa.

**Si no encuentra nada:** explica por qué — no aprueba en silencio.

**Condición de salida:** máximo 2 rondas de objeciones al Arquitecto. Si en la segunda ronda no aparecen problemas nuevos, aprueba con razón explícita. No puede seguir objetando indefinidamente.

---

### Optimizador

**Responsabilidad:** Comprimir la skill hasta el mínimo necesario para que Claude funcione.

**Entra después del consenso Arquitecto + Revisor.**

**Su criterio — eliminar todo lo que:**
- Claude ya sabe (no explicar qué es un comando, qué es un flag estándar)
- Repite información ya presente en otra sección
- Es contexto histórico que Claude no necesita para ejecutar
- Excede 500 líneas en el body (mover a `references/` si aplica)

**Su criterio — conservar todo lo que:**
- Es específico de esta herramienta/API/servicio
- Claude no podría inferir sin documentación
- Son edge cases reales que Claude necesita manejar

**También verifica:**
- `description` incluye qué hace Y cuándo usarla (el trigger)
- `name` en kebab-case, bajo 64 caracteres
- Todos los valores específicos son placeholders
- `agents/openai.yaml` existe salvo razón explícita para omitirlo
- Los directorios opcionales no existen vacíos ni por decoración

**Condición de salida:** termina cuando el body tiene < 500 líneas, la estructura de carpetas es mínima y eliminó o movió al menos 1 bloque redundante. Ni antes ni después.

---

## Subagentes (ejecutan tareas acotadas — no debaten)

**IMPORTANTE para el Lead:** Lanzar estos agentes con el Task tool **SIN team_name**. Si se lanzan con team_name, se convierten en teammates y no es lo que necesitamos.

### Investigador
- **Lanzado por:** Lead — en la Fase 1, antes de spawnar a los teammates. **Sin team_name.**
- **Qué busca:** Comandos exactos, flags actuales, requisitos, casos borde — desde documentación oficial.
- **Fuentes:** Máximo 2 fuentes primarias. Siempre primarias (docs oficiales, changelogs, repos). Si no encuentra fuente primaria, lo dice explícitamente — no busca más de 2 URLs.
- **Pregunta central:** "¿Qué necesita saber Claude para ejecutar esto?" — no "¿cómo lo hace un humano?"
- **Devuelve resultados al Lead** (no al Arquitecto). El Lead los incluye en el spawn prompt del Arquitecto.
- **Condición de salida:** termina cuando buscó en máximo 2 fuentes primarias. Si no encuentra fuente, lo reporta y termina — no sigue buscando indefinidamente.

### MCP2CLI Toolsmith
- **Lanzado por:** Lead, solo cuando hay OpenAPI, MCP o una petición explícita de generar tools desde APIs. **Sin team_name.**
- **Qué hace:** evalúa si conviene usar `mcp2cli` como backend runtime de la skill y propone estructura, modo de uso y requisitos.
- **Guía local:** `agents/mcp2cli-toolsmith.md`
- **Devuelve al Lead:** decisión `sí/no`, modo recomendado (`--spec`, `--mcp`, `--mcp-stdio`), estructura de skill, requisitos y riesgos.
- **Condición de salida:** termina cuando el Arquitecto puede decidir la estructura de la skill sin reinterpretar la API.

### Validador
- **Lanzado por:** Lead, después de que el Optimizador termina. **Sin team_name.**
- **Qué hace:** Ejecuta `./validate.sh skills/[nombre-skill]` y devuelve resultado completo

### Publisher
- **Lanzado por:** Lead, solo si validación pasó. **Sin team_name.**
- **Qué hace:** Ejecuta `./publish.sh skills/[nombre-skill]` y verifica con:
  ```bash
  curl -s http://localhost:8080/api/v1/skills \
    -H "Authorization: Bearer $HERMIT_TOKEN" | jq '.[] | .name'
  ```

---

## Formato de la skill

```text
skills/nombre-skill/
├── SKILL.md
├── agents/
│   └── openai.yaml
├── scripts/          # opcional
├── references/       # opcional
└── assets/           # opcional
```

### SKILL.md

```markdown
---
name: nombre-en-kebab-case
version: 1.0.0
description: "Ejecuta [tarea concreta] de principio a fin. Usar cuando el usuario necesite [trigger específico]."
license: MIT
author: "Equipo"
displayName: "Nombre legible de la skill"
metadata:
  category: infrastructure
  tags:
    - tag1
    - tag2
allowed-tools:
  - Bash
---

# Nombre de la Skill

## Instrucciones

[Objetivo operativo en 1-2 líneas]
[Secuencia exacta de acciones]
[Comandos listos para ejecutar]
[Checks entre pasos para confirmar que todo sigue bien]
[Usar placeholders: <DOMAIN>, <PROJECT_ID>, <API_KEY>, <ZONE_NAME>]

## Decisiones

[Qué decide la skill sin preguntar]
[Qué casos obligan a pedir aclaración]
[Qué condiciones hacen abortar para evitar cambios incorrectos]

## Verificación

[Cómo comprobar que el resultado quedó aplicado]
[Comandos o consultas de validación]

## Errores comunes

[Errores que Claude resuelve — mensaje exacto + solución]

## Referencias
- [Fuente primaria 1](URL)
- [Fuente primaria 2](URL)
```

**El body debe quedar bajo 500 líneas.**
**Si supera ese límite:** crear archivos adicionales en `references/` y referenciarlos desde el `SKILL.md` principal.

### agents/openai.yaml

Cuando exista, debe contener metadata de interfaz alineada con la skill. Como mínimo:
- nombre visible legible
- descripción corta para catálogos
- prompt por defecto coherente con el trigger de `SKILL.md`

No inventar branding, iconos ni colores si no fueron pedidos o no aportan nada.

**Criterios extra para que funcione mejor:**
- Las instrucciones deben ser ejecutables en orden, sin pasos implícitos.
- Si una acción cambia estado, añadir una comprobación justo después.
- Si hay varias rutas válidas, elegir una por defecto y documentar cuándo usar otra.
- No incluir “consejos” genéricos; solo decisiones que alteren la ejecución.

---

## Reglas

1. **El Lead pregunta antes de arrancar** si hay ambigüedades bloqueantes. No asume el proveedor, no asume el scope.
2. **Sin fuente primaria, no se escribe.** Si el Investigador no encontró documentación oficial para un comando, el Arquitecto lo marca y pide confirmación.
3. **Sin hardcode.** Valores específicos del usuario siempre como placeholders. Sin excepciones.
4. **Skills para Claude, no para humanos.** No explicar lo que Claude ya sabe.
5. **El Optimizador substrae, no agrega.** Su trabajo es eliminar, mover a recursos o simplificar; no enriquecer.
6. **Sin validación, sin publicación.** El Publisher no corre si el Validador falló.
7. **Subagentes SIN team_name.** El Lead lanza Investigador, MCP2CLI Toolsmith, Validador y Publisher con el Task tool sin el parámetro team_name. Esto los mantiene como subagentes (corren dentro del Lead) en vez de teammates.
8. **Condiciones de salida explícitas.** Cada rol termina cuando su condición se cumple — no antes, no después.
9. **Todos los agentes se comunican en español.**
10. **Cada bloque debe reducir ambigüedad.** Si una sección no cambia una decisión o una ejecución, sobra.
11. **La salida es una carpeta completa.** La skill no se considera terminada si solo existe `SKILL.md` y faltan recursos claramente necesarios para ejecutarla bien.
