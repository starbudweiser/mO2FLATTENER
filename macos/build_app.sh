#!/bin/bash
# Compile la version Swift de mO2FLATTENER et assemble « mO2FLATTENER.app » à la racine du projet,
# avec l'icône, l'identifiant de bundle habituel et la signature stable (_tools/sign_app.sh).
# Usage : macos/build_app.sh [dossier de sortie]   (par défaut : racine du projet)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
OUT_DIR="${1:-$ROOT}"
APP_NAME="mO2FLATTENER"
BUNDLE_ID="mO2FLATTENER"  # inchangé d'une version à l'autre : macOS garde les autorisations
VERSION="2.0.1"
ICON="$ROOT/assets/icon.icns"
APP="$OUT_DIR/$APP_NAME.app"

[[ -f "$ICON" ]] || { echo "❌ Introuvable : $ICON" >&2; exit 1; }

# mackit : l'outil en ligne de commande du moteur Mac commun (DXMT, ENB, DLSS), embarqué tel quel.
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

echo "→ Traductions"
python3 "$HERE/gen_strings.py"

echo "→ Tests"
swift test --package-path "$HERE" -q

echo "→ Compilation"
swift build --package-path "$HERE" -c release -q
BIN="$(swift build --package-path "$HERE" -c release --show-bin-path)/$APP_NAME"

echo "→ Assemblage"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ICON" "$APP/Contents/Resources/icon.icns"
if [ -x "$MACKIT_BIN" ]; then
    cp "$MACKIT_BIN" "$APP/Contents/Resources/mackit"
    echo "✓ mackit embarqué : $MACKIT_BIN"
else
    echo "ATTENTION : mackit introuvable ($MACKIT_BIN) : l'adaptation au Mac sera indisponible." >&2
fi
# Langues déclarées : les panneaux système (choix de dossier…) suivent la langue du Mac
for lang in fr en it es; do mkdir -p "$APP/Contents/Resources/$lang.lproj"; done
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIconFile</key><string>icon.icns</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>fr</string><string>en</string><string>it</string><string>es</string></array>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Signature stable avec _tools/sign_app.sh (certificat local) ; sans lui (compilation depuis
# le dépôt GitHub seul), signature ad hoc pour que l'appli se lance quand même.
SIGN_APP="$ROOT/../_tools/sign_app.sh"
if [ -x "$SIGN_APP" ]; then
    "$SIGN_APP" "$APP" "$VERSION"
    EMBEDDED="$APP/Contents/Resources/mackit"
    if [ -x "$EMBEDDED" ]; then
        codesign --verify --strict "$EMBEDDED" && echo "✓ mackit signé dans l'.app"
    elif [ -x "$MACKIT_BIN" ]; then
        echo "Erreur : mackit absent de l'.app." >&2; exit 1
    fi
else
    echo "_tools/sign_app.sh absent : signature ad hoc."
    codesign --force --deep --sign - "$APP"
fi
echo "✓ Application créée : $APP"
