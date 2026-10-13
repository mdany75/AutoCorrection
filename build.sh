#!/bin/bash
#
# build.sh — compile AutoCorrection, assemble l'application et son image disque dans build/.
#
# Usage : ./build.sh [--install]     (depuis n'importe quel dossier courant)
#         --install : remplace aussi /Applications/AutoCorrection.app
#
# Variables d'environnement :
#   SIGN_IDENTITY="-"   signature ad hoc même si un certificat est présent
#   SKIP_NOTARIZE=1     signe avec le certificat mais ne notarise pas (essai rapide)
#   NOTARY_PROFILE=nom  profil de « xcrun notarytool store-credentials » (défaut : notarisation)
#
# Produit build/AutoCorrection.app et build/AutoCorrection.dmg (publié en Release GitHub).
# Sans certificat « Developer ID Application » : signature ad hoc, pas de notarisation.

set -euo pipefail

APP_NAME="AutoCorrection"
VERSION="1.9.1"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
DIST_DIR="${ROOT_DIR}/build"
ICON_FILE="${ROOT_DIR}/Resources/AppIcon.icns"
ENTITLEMENTS="${ROOT_DIR}/Resources/AutoCorrection.entitlements"

INSTALL=0
for arg in "$@"; do
    case "${arg}" in
        --install) INSTALL=1 ;;
        *) printf 'Option inconnue : %s (seule option : --install)\n' "${arg}" >&2; exit 1 ;;
    esac
done

step() { printf '\n==> %s\n' "$1"; }
die()  { printf 'Erreur : %s\n' "$1" >&2; exit 1; }

STAGE_DIR=""
trap '[[ -z "${STAGE_DIR}" ]] || rm -rf "${STAGE_DIR}"' EXIT

[[ -f "${ICON_FILE}" ]] || die "fichier manquant : ${ICON_FILE}"
[[ -f "${ENTITLEMENTS}" ]] || die "fichier manquant : ${ENTITLEMENTS}"
for tool in swift codesign plutil hdiutil ditto security xcrun spctl; do
    command -v "${tool}" >/dev/null 2>&1 || die "outil introuvable : ${tool}"
done

# --- Signature et notarisation ------------------------------------------------

SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -n 1)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-notarisation}"
if [[ "${SIGN_IDENTITY}" == "-" ]]; then
    SIGN_ARGS=(--entitlements "${ENTITLEMENTS}" --sign -)
    NOTARIZE=0; NOTARIZE_WHY="signature ad hoc, aucun certificat Developer ID"
elif [[ "${SKIP_NOTARIZE:-0}" != "0" ]]; then
    SIGN_ARGS=(--options runtime --timestamp --entitlements "${ENTITLEMENTS}" --sign "${SIGN_IDENTITY}")
    NOTARIZE=0; NOTARIZE_WHY="SKIP_NOTARIZE=1"
else
    SIGN_ARGS=(--options runtime --timestamp --entitlements "${ENTITLEMENTS}" --sign "${SIGN_IDENTITY}")
    NOTARIZE=1; NOTARIZE_WHY=""
fi

# sign_code OPTIONS… CHEMIN : signe, puis vérifie (le serveur d'horodatage d'Apple renvoie
# parfois une heure décalée que « codesign --verify --strict » refuse : jusqu'à trois essais).
sign_code() {
    local attempt
    for attempt in 1 2 3; do
        codesign --force "$@"
        codesign --verify --deep --strict "${@:$#}" && return 0
        printf 'Vérification de la signature refusée (essai %s/3), nouvelle signature…\n' "${attempt}" >&2
        sleep 2
    done
    die "signature impossible à vérifier : ${@:$#}"
}

notarize_file() {
    local file="$1" output id
    step "Notarisation de « $(basename "${file}") » (profil « ${NOTARY_PROFILE} »)"
    if ! output="$(xcrun notarytool submit "${file}" --keychain-profile "${NOTARY_PROFILE}" --wait 2>&1)"; then
        printf '%s\n' "${output}" >&2
        die "notarisation impossible : session verrouillée ou profil « ${NOTARY_PROFILE} » absent (xcrun notarytool store-credentials)"
    fi
    printf '%s\n' "${output}"
    if ! grep -q '^ *status: Accepted' <<< "${output}"; then
        id="$(sed -n 's/^ *id: //p' <<< "${output}" | head -n 1)"
        [[ -z "${id}" ]] || xcrun notarytool log "${id}" --keychain-profile "${NOTARY_PROFILE}" >&2 || true
        die "notarisation refusée par Apple (détail ci-dessus)"
    fi
}

finalize_dmg() {
    local dmg="$1"
    if [[ "${NOTARIZE}" -eq 0 ]]; then
        step "Image disque non notarisée (${NOTARIZE_WHY}) : avertissement de macOS sur un autre Mac"
        return 0
    fi
    sign_code --timestamp --sign "${SIGN_IDENTITY}" "${dmg}"
    notarize_file "${dmg}"
    step "Agrafage du ticket et vérification Gatekeeper"
    xcrun stapler staple "${dmg}"
    spctl -a -t open --context context:primary-signature -vv "${dmg}"
}

# --- 1. Compilation -----------------------------------------------------------

step "Compilation (release)"
swift build -c release --package-path "${ROOT_DIR}"
BINARY="$(swift build -c release --package-path "${ROOT_DIR}" --show-bin-path)/${APP_NAME}"
[[ -x "${BINARY}" ]] || die "exécutable introuvable après la compilation : ${BINARY}"

# --- 2. Assemblage (hors du projet : pas d'attributs étendus qui feraient échouer la signature)

step "Assemblage de « ${APP_NAME}.app »"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/autocorrection-app.XXXXXX")"
STAGE_APP="${STAGE_DIR}/${APP_NAME}.app"
mkdir -p "${STAGE_APP}/Contents/MacOS" "${STAGE_APP}/Contents/Resources"
cp "${BINARY}" "${STAGE_APP}/Contents/MacOS/${APP_NAME}"
cp "${ICON_FILE}" "${STAGE_APP}/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "${STAGE_APP}/Contents/PkgInfo"

cat > "${STAGE_APP}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>ca.dany.AutoCorrection</string>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>AutoCorrection utilise le microphone pour dicter un texte.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>AutoCorrection transcrit votre voix en texte pour la dictée.</string>
</dict>
</plist>
PLIST
plutil -lint "${STAGE_APP}/Contents/Info.plist" >/dev/null || die "Info.plist invalide"

# --- 3. Signature -------------------------------------------------------------

step "Signature (${SIGN_IDENTITY})"
xattr -cr "${STAGE_APP}"
sign_code "${SIGN_ARGS[@]}" "${STAGE_APP}"

mkdir -p "${DIST_DIR}"
rm -rf "${DIST_DIR}/${APP_NAME}.app"
ditto "${STAGE_APP}" "${DIST_DIR}/${APP_NAME}.app"

# --- 4. Installation (avec --install) -----------------------------------------

if [[ "${INSTALL}" -eq 1 ]]; then
    step "Installation dans /Applications"
    rm -rf "/Applications/${APP_NAME}.app"
    ditto "${STAGE_APP}" "/Applications/${APP_NAME}.app"
    codesign --verify --deep --strict "/Applications/${APP_NAME}.app"
    touch "/Applications/${APP_NAME}.app"
fi

# --- 5. Image disque, notarisation --------------------------------------------

step "Image disque « ${APP_NAME}.dmg »"
DMG_ROOT="${STAGE_DIR}/dmg"
mkdir -p "${DMG_ROOT}"
ditto "${STAGE_APP}" "${DMG_ROOT}/${APP_NAME}.app"
ln -s /Applications "${DMG_ROOT}/Applications"

hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_ROOT}" -fs HFS+ -format UDZO \
    -ov -quiet "${STAGE_DIR}/${APP_NAME}.dmg"
hdiutil verify -quiet "${STAGE_DIR}/${APP_NAME}.dmg"

finalize_dmg "${STAGE_DIR}/${APP_NAME}.dmg"
mv -f "${STAGE_DIR}/${APP_NAME}.dmg" "${DIST_DIR}/${APP_NAME}.dmg"

step "Terminé"
printf '%s\n' "${DIST_DIR}/${APP_NAME}.dmg"
