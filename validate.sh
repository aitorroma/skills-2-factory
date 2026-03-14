#!/bin/bash

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
OPENAI_FILE="$SKILL_DIR/agents/openai.yaml"
QUICK_VALIDATE="/home/tuxed/.codex/skills/.system/skill-creator/scripts/quick_validate.py"

if [ ! -f "$SKILL_FILE" ]; then
  echo "Error: No existe $SKILL_FILE"
  exit 1
fi

echo "🔍 Validando: $SKILL_FILE"
echo ""

ERRORS=0

check() {
  local label="$1"
  local condition="$2"
  if eval "$condition"; then
    echo "  ✓ $label"
  else
    echo "  ✗ $label"
    ERRORS=$((ERRORS + 1))
  fi
}

check "Frontmatter de apertura presente" "head -1 '$SKILL_FILE' | grep -q '^---$'"
check "Frontmatter de cierre presente" "sed -n '4p' '$SKILL_FILE' | grep -q '^---$'"
check "Campo name presente" "grep -q '^name:' '$SKILL_FILE'"
check "Campo description presente" "grep -q '^description:' '$SKILL_FILE'"
check "Titulo principal presente" "grep -q '^# ' '$SKILL_FILE'"

if [ -f "$OPENAI_FILE" ]; then
  check "agents/openai.yaml presente y con display_name" "grep -q 'display_name:' '$OPENAI_FILE'"
  check "agents/openai.yaml con short_description" "grep -q 'short_description:' '$OPENAI_FILE'"
  check "agents/openai.yaml con default_prompt" "grep -q 'default_prompt:' '$OPENAI_FILE'"
fi

if [ -f "$QUICK_VALIDATE" ]; then
  echo ""
  echo "🧪 Ejecutando quick_validate.py"
  if python3 "$QUICK_VALIDATE" "$SKILL_DIR"; then
    echo "  ✓ quick_validate.py"
  else
    echo "  ✗ quick_validate.py"
    ERRORS=$((ERRORS + 1))
  fi
fi

echo ""

if [ $ERRORS -gt 0 ]; then
  echo "❌ Validación fallida: $ERRORS error(es)"
  exit 1
fi

echo "✅ Validación pasada"
