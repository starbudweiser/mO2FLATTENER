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

# 3. mackit : l'outil en ligne de commande du moteur Mac commun (DXMT, ENB, DLSS), embarqué tel quel.
# Source unique dans _tools/shared/mackit (compilé par son build.sh si absent ou plus vieux que sa source).
# Hors de ce dossier d'outils (dépôt GitHub seul), MACKIT_BIN=<chemin> en donne un ; sans lui l'appli se compile
# quand même et l'annonce « Adaptation au Mac » dit que l'outil est introuvable.
MACKIT_DIR="$(cd "$ROOT/.." && pwd)/_tools/shared/mackit"
MACKIT_BIN="${MACKIT_BIN:-$MACKIT_DIR/dist/mackit}"
if [ -z "${MACKIT_NO_BUILD:-}" ] && [ -x "$MACKIT_DIR/build.sh" ]; then
    if [ ! -x "$MACKIT_BIN" ] || [ -n "$(find "$MACKIT_DIR/cli" "$MACKIT_DIR/src" -type f -name '*.ts' -newer "$MACKIT_BIN" -print -quit)" ]; then
        echo "🔧 Compilation de mackit..."
        "$MACKIT_DIR/build.sh"
    fi
fi
MACKIT_ARGS=()
if [ -x "$MACKIT_BIN" ]; then
    echo "✓ mackit embarqué : $MACKIT_BIN"
    MACKIT_ARGS=(--add-binary "$MACKIT_BIN:.")
else
    echo "ATTENTION : mackit introuvable ($MACKIT_BIN) : l'adaptation au Mac sera indisponible." >&2
fi

# 4. Compilation (sorties temporaires hors du projet), livraison à la racine et signature stable (_tools)
echo "📦 Compilation de ${APP_NAME}..."
# Lanceur PyInstaller compilé depuis les sources, contre les faux positifs antivirus (absent hors de ce dossier d'outils : lanceur standard).
PYI_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/_tools/pyinstaller_source.sh"
if [ -x "$PYI_SRC" ]; then "$PYI_SRC" python3; fi
pyinstaller \
    --noconfirm --clean --onedir --windowed \
    --name "$APP_NAME" \
    --icon "$ICON_ICNS" \
    --distpath "$WORK_DIR/dist" \
    --workpath "$WORK_DIR/build" \
    --specpath "$WORK_DIR" \
    ${MACKIT_ARGS[@]+"${MACKIT_ARGS[@]}"} \
    "$MAIN_SCRIPT"
rm -rf "$ROOT/${APP_NAME}.app"
mv "$WORK_DIR/dist/${APP_NAME}.app" "$ROOT/"
# Signature stable avec _tools/sign_app.sh (certificat local) ; sans lui (compilation depuis
# le dépôt GitHub seul), signature ad hoc pour que l'appli se lance quand même.
SIGN_APP="$(cd "$ROOT/.." && pwd)/_tools/sign_app.sh"
if [ -x "$SIGN_APP" ]; then
    "$SIGN_APP" "$ROOT/${APP_NAME}.app" 1.3.0
    # mackit est dans l'.app : --deep l'a signé avec l'identité de l'appli ; on le vérifie (sans lui, l'adaptation ne tourne pas)
    EMBEDDED="$(find "$ROOT/${APP_NAME}.app/Contents" -type f -name mackit -perm -u+x -print -quit)"
    if [ -n "$EMBEDDED" ]; then
        codesign --verify --strict "$EMBEDDED" && echo "✓ mackit signé dans l'.app : ${EMBEDDED#$ROOT/}"
    elif [ -x "$MACKIT_BIN" ]; then
        echo "Erreur : mackit absent de l'.app." >&2; exit 1
    fi
else
    echo "_tools/sign_app.sh absent : signature ad hoc."
    codesign --force --deep --sign - "$ROOT/${APP_NAME}.app"
fi

echo "=================================================="
echo "✓ Application : $ROOT/${APP_NAME}.app"
echo "=================================================="
