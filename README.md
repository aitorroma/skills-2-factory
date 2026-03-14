<div align="center">

  <a href="https://t.me/aitorroma">
    <img src="https://tva1.sinaimg.cn/large/008i3skNgy1gq8sv4q7cqj303k03kweo.jpg" alt="Aitor Roma" />
  </a>

  <br>

  [![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/J3J64AN17)

  <br>

  <a href="https://t.me/aitorroma">
    <img src="https://img.shields.io/badge/Telegram-informational?style=for-the-badge&logo=telegram&logoColor=white" alt="Telegram Badge"/>
  </a>
</div>

# Fábrica de Skills 2.0 con Agent Teams

Este proyecto monta un flujo de trabajo para crear, validar y publicar Skills 2.0 usando Agent Teams y subagentes. El objetivo no es redactar tutoriales, sino generar carpetas de skill que un agente pueda ejecutar con precisión y con el menor ruido posible.

## Qué resuelve

- Coordina varios roles con responsabilidades separadas.
- Obliga a investigar antes de escribir.
- Valida la estructura completa de la skill antes de publicarla.
- Publica la skill en un endpoint configurable y la instala localmente.

## Cómo funciona

El flujo se divide en tres etapas:

1. El Lead recibe el pedido, detecta ambigüedades reales y lanza la investigación.
2. El equipo redacta, revisa y recorta la skill hasta dejar solo lo necesario.
3. Se valida el resultado y, si pasa, se publica.

La separación entre teammates y subagentes es importante: los teammates colaboran entre sí; los subagentes ejecutan tareas concretas y devuelven un resultado.

Cuando el input del usuario es una API o un servidor MCP, la factoría puede invocar el agente `MCP2CLI Toolsmith` para decidir si la skill debe usar `mcp2cli` como capa de tools en runtime.

## Requisitos

- Claude Code con `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`
- Un portal compatible accesible por HTTP
- Un token de acceso para publicar
- `python3`
- `curl`
- `git`
- `uv` si quieres habilitar instalación automática de `skills-ref`

## Configuración

```bash
git clone https://github.com/aitorroma/skills-2-factory
cd skills-2-factory
cp .env.example .env
```

Contenido mínimo de `.env`:

```dotenv
HERMIT_URL=http://localhost:8080
HERMIT_TOKEN=pega_aqui_tu_token
```

Activa Agent Teams en `~/.claude/settings.json`:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

Si necesitas un portal local:

```bash
git clone https://github.com/hermit-labs/hermit
cd hermit
docker compose up -d
```

Después crea una API key en `http://localhost:8080/admin` y copia el valor a `HERMIT_TOKEN`.

Si necesitas un despliegue propio detrás de Traefik, este repo incluye una plantilla en `hermit.yaml` con el host `skills.tudominio.com`.

La plantilla de `hermit.yaml` está pensada para Docker Swarm. Actualiza los placeholders de credenciales, usuario y dominio antes de desplegar.

Despliegue en Swarm:

```bash
docker stack deploy -c hermit.yaml hermit
```

## Uso básico

Abre Claude Code dentro del proyecto:

```bash
claude
```

Ejemplo de petición:

```text
Necesito una skill para crear una VM en Google Cloud con Terraform.
```

Con contexto suficiente, el pipeline continúa hasta la validación y la publicación.

## Scripts disponibles

Validar una skill:

```bash
./validate.sh skills/nombre-skill
```

Publicar una skill:

```bash
./publish.sh skills/nombre-skill
```

`validate.sh` intenta usar `skills-ref` si está disponible. Si no lo encuentra, ejecuta una validación local básica de Skills 2.0 para no bloquear el flujo.

## Estructura del sistema

- `README.md`: visión general y puesta en marcha.
- `CLAUDE.md`: reglas operativas del equipo, roles y formato esperado para una skill completa.
- `agents/mcp2cli-toolsmith.md`: agente opcional para evaluar integración de OpenAPI/MCP con `mcp2cli`.
- `hermit.yaml`: plantilla de despliegue de Hermit con Traefik y credenciales anonimizadas.
- `validate.sh`: validación de skills 2.0.
- `publish.sh`: publicación e instalación local de carpetas de skill completas.

## Qué produce la factoría

La salida objetivo es una carpeta de skill, no solo un `SKILL.md`:

```text
skills/nombre-skill/
├── SKILL.md
├── agents/
│   └── openai.yaml
├── scripts/        # opcional
├── references/     # opcional
└── assets/         # opcional
```

`SKILL.md` sigue siendo obligatorio. `agents/openai.yaml` es recomendado por defecto para que la skill tenga metadata de interfaz y quede lista para catálogos o listados. Los demás directorios se crean solo cuando aportan valor real.

## Criterio de calidad

Una skill está bien hecha si un agente puede ejecutarla sin reinterpretar el objetivo, sin inventar pasos y sin depender de valores hardcodeados. En Skills 2.0 eso incluye decidir qué va en `SKILL.md`, qué debe vivir en `references/`, qué conviene automatizar en `scripts/` y qué metadata mínima necesita `agents/openai.yaml`. La prioridad sigue siendo la precisión operativa.
