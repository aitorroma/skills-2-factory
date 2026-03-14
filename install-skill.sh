#!/bin/bash

set -euo pipefail

usage() {
  echo "Uso: ./install-skill.sh <skill-slug> [version] [destino]"
}

SKILL_SLUG="${1:-}"
SKILL_VERSION="${2:-}"
DEST_DIR="${3:-}"

if [ -z "$SKILL_SLUG" ]; then
  echo "Error: Debes indicar la skill a descargar"
  usage
  exit 1
fi

if [ -f ".env" ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

HERMIT_URL="${HERMIT_URL:-https://hermit.cl.n1mbot.cloud}"
HERMIT_TOKEN="${HERMIT_TOKEN:-}"

if [ -z "$HERMIT_TOKEN" ]; then
  echo "Error: HERMIT_TOKEN no configurado"
  exit 1
fi

if [ -z "$DEST_DIR" ]; then
  if [ -n "$SKILL_VERSION" ]; then
    DEST_DIR="./downloaded-skills/${SKILL_SLUG}-${SKILL_VERSION}"
  else
    DEST_DIR="./downloaded-skills/${SKILL_SLUG}"
  fi
fi

TMP_ZIP="$(mktemp /tmp/${SKILL_SLUG}.XXXXXX.zip)"
cleanup() {
  rm -f "$TMP_ZIP"
}
trap cleanup EXIT

DOWNLOAD_URL="${HERMIT_URL%/}/api/v1/download?slug=${SKILL_SLUG}"
if [ -n "$SKILL_VERSION" ]; then
  DOWNLOAD_URL="${DOWNLOAD_URL}&version=${SKILL_VERSION}"
fi

echo "⬇ Descargando $SKILL_SLUG${SKILL_VERSION:+@$SKILL_VERSION} desde $HERMIT_URL"
curl -fsS \
  -H "Authorization: Bearer $HERMIT_TOKEN" \
  "$DOWNLOAD_URL" \
  -o "$TMP_ZIP"

rm -rf "$DEST_DIR"
mkdir -p "$DEST_DIR"

python3 - "$TMP_ZIP" "$DEST_DIR" <<'PY'
import sys
import zipfile
from pathlib import Path

zip_path = Path(sys.argv[1])
dest = Path(sys.argv[2])

with zipfile.ZipFile(zip_path) as zf:
    zf.extractall(dest)
PY

echo "✓ Skill descargada en: $DEST_DIR"
