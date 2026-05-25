#!/usr/bin/env bash
# bundle-fix.sh
# Assemble the BambuStudio.app bundle after a successful cmake build.
# Run from the repo root after: cmake --build build/arm64 --parallel
#
# Usage:
#   bash scripts/bundle-fix.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="arm64"
BUILD_BIN="${REPO_ROOT}/build/${ARCH}/src/BambuStudio"
APP="${REPO_ROOT}/build/${ARCH}/BambuStudio/BambuStudio.app"
PLUGINS="${HOME}/Library/Application Support/BambuStudio/plugins"
RETAIL_APP="/Applications/BambuStudio.app"

echo "=== BambuStudio bundle fix ==="
echo "    App:    ${APP}"
echo "    Binary: ${BUILD_BIN}"
echo ""

# ── 1. MacOS binary ───────────────────────────────────────────────────────────
if [[ ! -f "${BUILD_BIN}" ]]; then
    echo "ERROR: binary not found at ${BUILD_BIN}"
    echo "       Run:  cmake --build ${REPO_ROOT}/build/${ARCH} --parallel"
    exit 1
fi
echo "[1/6] Copying binary..."
mkdir -p "${APP}/Contents/MacOS"
cp "${BUILD_BIN}" "${APP}/Contents/MacOS/BambuStudio"
echo "      OK"

# ── 2. Resources ─────────────────────────────────────────────────────────────
echo "[2/6] Syncing Resources..."
mkdir -p "${APP}/Contents/Resources"
rsync -a --delete "${REPO_ROOT}/resources/" "${APP}/Contents/Resources/"
echo "      OK"

# ── 3. Info.plist ─────────────────────────────────────────────────────────────
echo "[3/6] Copying Info.plist..."
if [[ -f "${RETAIL_APP}/Contents/Info.plist" ]]; then
    cp "${RETAIL_APP}/Contents/Info.plist" "${APP}/Contents/Info.plist"
    echo "      OK (from retail app)"
elif [[ -f "${REPO_ROOT}/build/${ARCH}/src/Info.plist" ]]; then
    cp "${REPO_ROOT}/build/${ARCH}/src/Info.plist" "${APP}/Contents/Info.plist"
    echo "      OK (from build tree)"
else
    echo "      WARNING: Info.plist not found — app may not launch correctly"
    echo "      Expected: ${RETAIL_APP}/Contents/Info.plist"
fi

# ── 4. Frameworks / dylibs ────────────────────────────────────────────────────
echo "[4/6] Copying dylibs to Frameworks..."
mkdir -p "${APP}/Contents/Frameworks"

if [[ ! -d "${PLUGINS}" ]]; then
    echo "      WARNING: plugins dir not found: ${PLUGINS}"
    echo "      Launch retail BambuStudio once to download dylibs, then re-run."
else
    cp "${PLUGINS}/libbambu_networking.dylib" \
       "${APP}/Contents/Frameworks/bambu_networking.dylib"
    cp "${PLUGINS}/libBambuSource.dylib" \
       "${APP}/Contents/Frameworks/libBambuSource.dylib"
    cp "${PLUGINS}/liblive555.dylib" \
       "${APP}/Contents/Frameworks/liblive555.dylib"
    echo "      OK (3 dylibs copied)"
fi

# ── 5. Strip quarantine ───────────────────────────────────────────────────────
echo "[5/6] Stripping quarantine (xattr -cr)..."
xattr -cr "${APP}"
echo "      OK"

# ── 6. Ad-hoc codesign ────────────────────────────────────────────────────────
echo "[6/6] Ad-hoc codesigning..."
codesign --force --deep --sign - "${APP}"
echo "      OK"

echo ""
echo "=== Bundle ready ==="
echo "    open \"${APP}\""
