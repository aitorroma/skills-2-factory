#!/bin/bash

# publish.sh — Publica una skill 2.0 en el endpoint configurado
#
# Uso: ./publish.sh skills/nombre-skill
# Ejemplo: ./publish.sh skills/cloudflare-tunnels

set -euo pipefail

usage() {
  echo "Uso: ./publish.sh skills/nombre-skill"
}

SKILL_DIR="${1:-}"

if [ -z "$SKILL_DIR" ]; then
  echo "Error: Debes especificar el directorio de la skill"
  usage
  exit 1
fi

if [ ! -d "$SKILL_DIR" ]; then
  echo "Error: No existe el directorio $SKILL_DIR"
  exit 1
fi

if [ ! -f "$SKILL_DIR/SKILL.md" ]; then
  echo "Error: No existe SKILL.md en $SKILL_DIR"
  exit 1
fi

# Cargar variables de entorno
if [ -f ".env" ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
else
  HERMIT_TOKEN="${HERMIT_TOKEN:-}"
fi

HERMIT_URL="${HERMIT_URL:-http://localhost:8080}"
HERMIT_TOKEN="${HERMIT_TOKEN:-}"

if [ -z "$HERMIT_TOKEN" ]; then
  echo "Error: HERMIT_TOKEN no configurado en .env"
  exit 1
fi

extract_frontmatter_field() {
  local field="$1"
  awk -F': *' -v key="$field" '
    BEGIN { in_frontmatter = 0 }
    /^---$/ {
      if (in_frontmatter == 0) {
        in_frontmatter = 1
        next
      }
      exit
    }
    in_frontmatter && $1 == key {
      sub(/^[^:]*:[[:space:]]*/, "", $0)
      gsub(/^["'\'' ]+|["'\'' ]+$/, "", $0)
      print
      exit
    }
  ' "$SKILL_DIR/SKILL.md"
}

extract_tags_json() {
  python3 - "$SKILL_DIR/SKILL.md" <<'PY'
import json
import sys

path = sys.argv[1]
tags = []
in_frontmatter = False
in_tags = False
tag_indent = None

with open(path, "r", encoding="utf-8") as f:
    for raw_line in f:
        line = raw_line.rstrip("\n")

        if line.strip() == "---":
            if not in_frontmatter:
                in_frontmatter = True
                continue
            break

        if not in_frontmatter:
            continue

        stripped = line.strip()
        indent = len(line) - len(line.lstrip(" "))

        if in_tags:
            if stripped.startswith("- "):
                tags.append(stripped[2:].strip().strip("\"'"))
                continue
            if stripped == "":
                continue
            if indent <= tag_indent:
                in_tags = False
            else:
                continue

        if stripped == "tags:":
            in_tags = True
            tag_indent = indent

print(json.dumps(tags))
PY
}

# Extraer metadata del frontmatter
SKILL_NAME=$(extract_frontmatter_field "name")
SKILL_VERSION=$(extract_frontmatter_field "version")
SKILL_DESCRIPTION=$(extract_frontmatter_field "description")
SKILL_DISPLAY=$(extract_frontmatter_field "displayName")
SKILL_TAGS_JSON=$(extract_tags_json)

if [ -z "$SKILL_DISPLAY" ]; then
  SKILL_DISPLAY=$(grep '^# ' "$SKILL_DIR/SKILL.md" | head -1 | sed 's/^# //')
fi

if [ -z "$SKILL_DISPLAY" ]; then
  SKILL_DISPLAY="$SKILL_NAME"
fi

if [ -z "$SKILL_NAME" ] || [ -z "$SKILL_VERSION" ]; then
  echo "Error: Faltan campos obligatorios en el frontmatter (name/version)"
  exit 1
fi

echo "📦 Publicando skill..."
echo "   Nombre:  $SKILL_NAME"
echo "   Versión: $SKILL_VERSION"
echo "   Portal:  $HERMIT_URL"
echo ""

FILE_LIST_JSON=$(python3 - "$SKILL_DIR" <<'PY'
import json
import os
import sys

root = sys.argv[1]
files = []
for current_root, _, filenames in os.walk(root):
    for filename in filenames:
        full_path = os.path.join(current_root, filename)
        rel_path = os.path.relpath(full_path, root)
        files.append(rel_path)
print(json.dumps(sorted(files)))
PY
)

PAYLOAD=$(
  SKILL_NAME="$SKILL_NAME" \
  SKILL_DISPLAY="$SKILL_DISPLAY" \
  SKILL_VERSION="$SKILL_VERSION" \
  SKILL_DESCRIPTION="$SKILL_DESCRIPTION" \
  SKILL_TAGS_JSON="$SKILL_TAGS_JSON" \
  FILE_LIST_JSON="$FILE_LIST_JSON" \
  python3 <<'PY'
import json
import os

payload = {
    "slug": os.environ["SKILL_NAME"],
    "displayName": os.environ["SKILL_DISPLAY"],
    "version": os.environ["SKILL_VERSION"],
    "changelog": "Published via publish.sh",
    "summary": os.environ.get("SKILL_DESCRIPTION", "").strip(),
    "tags": json.loads(os.environ.get("SKILL_TAGS_JSON", "[]")),
    "files": json.loads(os.environ.get("FILE_LIST_JSON", "[]")),
}
print(json.dumps(payload))
PY
)

TMP_ARCHIVE=$(mktemp "/tmp/${SKILL_NAME}.XXXXXX.tar.gz")
tar -C "$SKILL_DIR" -czf "$TMP_ARCHIVE" .

FILE_ARGS=()
while IFS= read -r -d '' file; do
  rel_path="${file#$SKILL_DIR/}"
  FILE_ARGS+=(-F "files=@$file;filename=$rel_path")
done < <(find "$SKILL_DIR" -type f -print0 | sort -z)

cleanup() {
  rm -f "$TMP_ARCHIVE"
}
trap cleanup EXIT

RESPONSE=$(curl -sS -w "\n%{http_code}" \
  -X POST "$HERMIT_URL/api/v1/skills" \
  -H "Authorization: Bearer $HERMIT_TOKEN" \
  -F "payload=$PAYLOAD" \
  -F "bundle=@$TMP_ARCHIVE;filename=${SKILL_NAME}.tar.gz" \
  "${FILE_ARGS[@]}")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -1)

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
  echo "✅ Skill publicada correctamente"
  echo ""

  # Instalar localmente para uso en sesiones nuevas
  LOCAL_SKILL_DIR="$HOME/.claude/skills/$SKILL_NAME"
  rm -rf "$LOCAL_SKILL_DIR"
  mkdir -p "$LOCAL_SKILL_DIR"
  cp -R "$SKILL_DIR"/. "$LOCAL_SKILL_DIR"/
  echo "📥 Skill instalada localmente en: $LOCAL_SKILL_DIR"
  echo ""
  echo "🌐 Endpoint: $HERMIT_URL"
  echo ""
  echo "Verificar:"
  echo "  curl -sS $HERMIT_URL/api/v1/skills -H 'Authorization: Bearer \$HERMIT_TOKEN' | python3 -m json.tool"
else
  echo "❌ Error al publicar (HTTP $HTTP_CODE)"
  echo "Respuesta: $BODY"
  exit 1
fi
