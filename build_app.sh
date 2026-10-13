#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

APP_NAME="mO2FLATTENER"
MAIN_SCRIPT="$ROOT/src/mo2_flattener_gui.py"
ICON_PNG="$ROOT/assets/icon.png"
ICON_ICNS="$ROOT/assets/icon.icns"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mo2flattener_build.XXXXXX")"

cleanup() {
    rm -rf "$WORK_DIR" "$ROOT/build" "$ROOT/__pycache__" "$ROOT/src/__pycache__"
    rm -f "$ROOT"/*.spec
}
trap cleanup EXIT

echo "=================================================="
echo "  Compilation de ${APP_NAME} pour macOS"
echo "=================================================="

# 1. Icône .icns
if [ -f "$ICON_ICNS" ]; then
    echo "✓ Icône déjà présente."
else
    [ -f "$ICON_PNG" ] || { echo "Erreur : '$ICON_PNG' introuvable." >&2; exit 1; }
    echo "🎨 Conversion de '$ICON_PNG' en .icns..."
    ICONSET="$WORK_DIR/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for s in 16 32 128 256 512; do
        sips -z $s $s "$ICON_PNG" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
        sips -z $((s*2)) $((s*2)) "$ICON_PNG" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$ICON_ICNS"
fi

# 2. PyInstaller
if ! command -v pyinstaller &>/dev/null; then
    echo "Installation de PyInstaller..."
    pip3 install pyinstaller
fi

# 3. Compilation (sorties temporaires hors du projet), livraison à la racine et signature stable (_tools)
echo "📦 Compilation de ${APP_NAME}..."
pyinstaller \
    --noconfirm --clean --onedir --windowed \
    --name "$APP_NAME" \
    --icon "$ICON_ICNS" \
    --distpath "$WORK_DIR/dist" \
    --workpath "$WORK_DIR/build" \
    --specpath "$WORK_DIR" \
    "$MAIN_SCRIPT"
rm -rf "$ROOT/${APP_NAME}.app"
mv "$WORK_DIR/dist/${APP_NAME}.app" "$ROOT/"
"$(cd "$ROOT/.." && pwd)/_tools/sign_app.sh" "$ROOT/${APP_NAME}.app"

echo "=================================================="
echo "✓ Application : $ROOT/${APP_NAME}.app"
echo "=================================================="
