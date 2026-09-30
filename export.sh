#!/usr/bin/env bash
# Export release builds into build/.
#
#   ./export.sh              # Linux + Windows
#   ./export.sh windows      # one platform: linux | windows
set -euo pipefail
cd "$(dirname "$0")"

GODOT=${GODOT:-godot}
VERSION=$("$GODOT" --version | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+)\.([a-z]+).*/\1.\2/')
TEMPLATES="${HOME}/.local/share/godot/export_templates/${VERSION}"

if [ ! -f data/neurons.mm ] || [ ! -f data/edges.bin ]; then
    echo "data/ is missing — run ./download_data.sh first" >&2
    exit 1
fi

if [ ! -d "$TEMPLATES" ]; then
    echo ">> installing export templates for Godot $VERSION"
    tag=${VERSION%.stable}-stable
    tmp=$(mktemp -d)
    curl -L --progress-bar -o "$tmp/templates.tpz" \
        "https://github.com/godotengine/godot/releases/download/${tag}/Godot_v${tag}_export_templates.tpz"
    mkdir -p "$(dirname "$TEMPLATES")"
    unzip -q "$tmp/templates.tpz" -d "$tmp"
    mv "$tmp/templates" "$TEMPLATES"
    rm -rf "$tmp"
fi

mkdir -p build
export GODOT_SILENCE_ROOT_WARNING=1
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

want=${1:-all}
if [ "$want" = all ] || [ "$want" = linux ]; then
    echo ">> Linux"
    "$GODOT" --headless --path . --export-release Linux build/godot-fly.x86_64 2>&1 | grep -iE "error|warn" || true
fi
if [ "$want" = all ] || [ "$want" = windows ]; then
    echo ">> Windows"
    "$GODOT" --headless --path . --export-release Windows build/godot-fly.exe 2>&1 | grep -iE "error|warn" || true
fi

echo ">> build/:"
ls -lh build/ | tail -n +2
echo "Linux: godot-fly.x86_64 is self-contained.  Windows: copy godot-fly.exe together with godot-fly.pck."
