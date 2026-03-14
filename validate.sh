#!/bin/bash

# validate.sh — Valida una skill 2.0
#
# Orden de resolución de skills-ref:
#   1. En PATH (venv activado o instalado globalmente)
#   2. En ~/agentskills/skills-ref/.venv/bin/skills-ref (instalación local)
#   3. Auto-instalación del validador si `uv` está disponible
#   4. Fallback: validación básica local
#
# Uso: ./validate.sh skills/nombre-skill

set -euo pipefail

usage() {
  echo "Uso: ./validate.sh skills/nombre-skill"
}

SKILL_DIR="${1:-}"

if [ -z "$SKILL_DIR" ]; then
  echo "Error: Debes especificar el directorio de la skill"
  usage
  exit 1
fi

SKILL_FILE="$SKILL_DIR/SKILL.md"

if [ ! -f "$SKILL_FILE" ]; then
  echo "Error: No existe $SKILL_FILE"
  exit 1
fi

echo "🔍 Validando: $SKILL_FILE"
echo ""

has_files_in_dir() {
  local dir="$1"
  [ -d "$dir" ] && find "$dir" -type f | grep -q .
}

# ── Resolver skills-ref ───────────────────────────────────────────────────────

SKILLS_REF_BIN=""

# 1. En PATH
if command -v skills-ref &> /dev/null; then
  SKILLS_REF_BIN="skills-ref"

# 2. Instalación local estándar
elif [ -x "$HOME/agentskills/skills-ref/.venv/bin/skills-ref" ]; then
  SKILLS_REF_BIN="$HOME/agentskills/skills-ref/.venv/bin/skills-ref"

# 3. Auto-instalación via uv
elif command -v uv &> /dev/null; then
  echo "skills-ref no encontrado. Instalando validador..."
  echo ""
  git clone --quiet https://github.com/agentskills/agentskills "$HOME/agentskills" 2>/dev/null \
    || git -C "$HOME/agentskills" pull --quiet
  (cd "$HOME/agentskills/skills-ref" && uv sync --quiet)
  SKILLS_REF_BIN="$HOME/agentskills/skills-ref/.venv/bin/skills-ref"
  echo "✓ skills-ref instalado en ~/agentskills/skills-ref/.venv"
  echo ""
fi

# ── Validación oficial ────────────────────────────────────────────────────────
if [ -n "$SKILLS_REF_BIN" ]; then
  echo "Usando skills-ref..."
  "$SKILLS_REF_BIN" validate "$SKILL_DIR"
  exit $?
fi

# ── Fallback: validación básica local ────────────────────────────────────────
echo "skills-ref no disponible. Ejecutando validación básica..."
echo ""

ERRORS=0
WARNINGS=0

check() {
  local label="$1"
  local condition="$2"
  local is_error="${3:-true}"

  if eval "$condition"; then
    echo "  ✓ $label"
  else
    if [ "$is_error" = "true" ]; then
      echo "  ✗ $label"
      ERRORS=$((ERRORS + 1))
    else
      echo "  ⚠ $label"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
}

# Verificar frontmatter existe
check "Frontmatter presente (---)" \
  "head -1 '$SKILL_FILE' | grep -q '^---$'"

# Verificar campos obligatorios
check "Campo 'name' presente" \
  "grep -q '^name:' '$SKILL_FILE'"

check "Campo 'version' presente" \
  "grep -q '^version:' '$SKILL_FILE'"

check "Campo 'description' presente" \
  "grep -q '^description:' '$SKILL_FILE'"

check "Campo 'license' presente" \
  "grep -q '^license:' '$SKILL_FILE'"

check "Campo 'allowed-tools' presente" \
  "grep -q '^allowed-tools:' '$SKILL_FILE'"

check "Archivo principal agents/openai.yaml presente" \
  "[ -f '$SKILL_DIR/agents/openai.yaml' ]" "false"

check "Directorio scripts/ no vacío cuando existe" \
  "! [ -d '$SKILL_DIR/scripts' ] || has_files_in_dir '$SKILL_DIR/scripts'"

check "Directorio references/ no vacío cuando existe" \
  "! [ -d '$SKILL_DIR/references' ] || has_files_in_dir '$SKILL_DIR/references'"

check "Directorio assets/ no vacío cuando existe" \
  "! [ -d '$SKILL_DIR/assets' ] || has_files_in_dir '$SKILL_DIR/assets'"

# Verificar formato name (kebab-case)
NAME=$(grep '^name:' "$SKILL_FILE" | head -1 | sed 's/name: //' | tr -d '"' | tr -d "'" | tr -d ' ')
check "Nombre en kebab-case (sin espacios, sin mayúsculas)" \
  "echo '$NAME' | grep -qE '^[a-z][a-z0-9-]+$'"

# Verificar versión semver
VERSION=$(grep '^version:' "$SKILL_FILE" | head -1 | sed 's/version: //' | tr -d '"' | tr -d "'" | tr -d ' ')
check "Versión en formato semver (X.Y.Z)" \
  "echo '$VERSION' | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'"

# Verificar secciones del body (acepta español e inglés)
check "Sección de instrucciones presente (## Instrucciones o ## Instructions)" \
  "grep -qE '^## (Instrucciones|Instructions)' '$SKILL_FILE'"

check "Al menos 1 bloque de código presente" \
  "grep -q '^\`\`\`' '$SKILL_FILE'"

# Verificar longitud description
DESC=$(grep '^description:' "$SKILL_FILE" | head -1 | sed 's/description: //' | tr -d '"')
DESC_LEN=${#DESC}
check "Description menor a 200 caracteres (actual: ${DESC_LEN})" \
  "[ $DESC_LEN -lt 200 ]" "true"

# Warnings (no bloquean)
check "Sección de decisiones/edge cases presente (## Decisiones o ## Decisions)" \
  "grep -qE '^## (Decisiones|Decisions)' '$SKILL_FILE'" "false"

check "Sección de errores presente (## Errores comunes o ## Common Issues)" \
  "grep -qE '^## (Errores comunes|Common Issues)' '$SKILL_FILE'" "false"

check "Sección de referencias presente (## Referencias o ## References)" \
  "grep -qE '^## (Referencias|References)' '$SKILL_FILE'" "false"

if [ -f "$SKILL_DIR/agents/openai.yaml" ]; then
  check "agents/openai.yaml incluye display_name" \
    "grep -q '^display_name:' '$SKILL_DIR/agents/openai.yaml'"

  check "agents/openai.yaml incluye short_description" \
    "grep -q '^short_description:' '$SKILL_DIR/agents/openai.yaml'"

  check "agents/openai.yaml incluye default_prompt" \
    "grep -q '^default_prompt:' '$SKILL_DIR/agents/openai.yaml'"
fi

echo ""
echo "────────────────────────────────────────"

if [ $ERRORS -gt 0 ]; then
  echo "❌ Validación fallida: $ERRORS error(s), $WARNINGS advertencia(s)"
  echo ""
  echo "Para habilitar la instalación automática, instala uv:"
  echo "  curl -LsSf https://astral.sh/uv/install.sh | sh"
  echo "  # Luego vuelve a correr ./validate.sh — se instala automáticamente"
  exit 1
else
  echo "✅ Validación pasada: 0 errores, $WARNINGS advertencia(s)"
  echo ""
  if [ $WARNINGS -gt 0 ]; then
    echo "Considera agregar las secciones opcionales para mejorar la skill."
  fi
fi
