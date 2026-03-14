#!/bin/bash

set -euo pipefail

usage() {
  echo "Uso: ./publish.sh skills/nombre-skill [version]"
}

SKILL_DIR="${1:-}"
VERSION_ARG="${2:-}"

if [ -z "$SKILL_DIR" ]; then
  echo "Error: Debes especificar el directorio de la skill"
  usage
  exit 1
fi

if [ ! -f "$SKILL_DIR/SKILL.md" ]; then
  echo "Error: No existe SKILL.md en $SKILL_DIR"
  exit 1
fi

ROOT_DIR="$(pwd)"
SKILL_DIR="${SKILL_DIR%/}"
SKILL_PATH="$ROOT_DIR/$SKILL_DIR"
QUICK_VALIDATE="/home/tuxed/.codex/skills/.system/skill-creator/scripts/quick_validate.py"

if [ -f ".env" ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

HERMIT_URL="${HERMIT_URL:-http://localhost:8080}"
HERMIT_TOKEN="${HERMIT_TOKEN:-}"

if [ -z "$HERMIT_TOKEN" ]; then
  echo "Error: HERMIT_TOKEN no configurado en .env"
  exit 1
fi

if [ ! -d "$SKILL_PATH" ]; then
  echo "Error: No existe el directorio $SKILL_DIR"
  exit 1
fi

if [ -f "$QUICK_VALIDATE" ]; then
  echo "🔍 Validando con quick_validate.py"
  python3 "$QUICK_VALIDATE" "$SKILL_PATH"
fi

slug="$(basename "$SKILL_DIR")"
skill_file="$SKILL_PATH/SKILL.md"
openai_yaml="$SKILL_PATH/agents/openai.yaml"
version="${VERSION_ARG:-${HERMIT_VERSION:-1.0.0}}"
changelog="${HERMIT_CHANGELOG:-Initial release}"
tags_csv="${HERMIT_TAGS:-latest}"

description="$(awk '
  /^description:/ {
    sub(/^description:[[:space:]]*/, "", $0)
    print
    exit
  }
' "$skill_file")"

display_name=""
if [ -f "$openai_yaml" ]; then
  display_name="$(awk -F'"' '
    /display_name:/ {
      print $2
      exit
    }
  ' "$openai_yaml")"
fi

if [ -z "$display_name" ]; then
  display_name="$(python3 - "$slug" <<'PY'
import sys
print(" ".join(part.capitalize() for part in sys.argv[1].split("-")))
PY
)"
fi

payload="$(python3 - "$slug" "$display_name" "$version" "$changelog" "$description" "$tags_csv" <<'PY'
import json
import sys

slug, display_name, version, changelog, summary, tags_csv = sys.argv[1:7]
payload = {
    "slug": slug,
    "displayName": display_name,
    "version": version,
    "changelog": changelog,
    "tags": [tag.strip() for tag in tags_csv.split(",") if tag.strip()],
}
if summary.strip():
    payload["summary"] = summary.strip()
print(json.dumps(payload, ensure_ascii=True))
PY
)"

echo "📦 Publicando skill desde $SKILL_DIR hacia $HERMIT_URL"
echo "   slug: $slug"
echo "   displayName: $display_name"
echo "   version: $version"

curl_args=(
  -fsS
  -X POST
  -H "Authorization: Bearer $HERMIT_TOKEN"
  -F "payload=$payload"
)

while IFS= read -r -d '' file; do
  rel_path="${file#"$SKILL_PATH"/}"
  curl_args+=(-F "files=@$file;filename=$rel_path")
  curl_args+=(-F "paths=$rel_path")
done < <(
  find "$SKILL_PATH" \
    \( -type d \( -name __pycache__ -o -name venv -o -name .venv -o -name node_modules -o -name .git \) -prune \) -o \
    \( -type f \
      ! -name '*.pyc' \
      ! -name '*.pyo' \
      ! -name '.DS_Store' \
      ! -name 'Thumbs.db' \
      -print0 \
    \) | sort -z
)

response="$(
  curl "${curl_args[@]}" "$HERMIT_URL/api/v1/skills"
)"

echo "✅ Publicacion completada"
echo "$response"
