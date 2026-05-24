#!/usr/bin/env bash
# build-arm64.sh
# Full build sequence for BambuStudio privacy fork — macOS Apple Silicon (arm64).
# Run from the repo root.
#
# Prerequisites:
#   - Xcode Command Line Tools
#   - Homebrew: cmake ninja gettext openssl@3
#   - brew unlink glew && brew pin glew   (avoids slicer finder conflict)
#   - bambu_networking.dylib in ~/Library/Application Support/BambuStudio/plugins/
#
# Usage:
#   bash scripts/build-arm64.sh            # full build
#   bash scripts/build-arm64.sh --no-deps  # skip dep build (already built)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="arm64"
BUILD_TYPE="RelWithDebInfo"
DEPS_INSTALL="${REPO_ROOT}/deps/build/${ARCH}/BambuStudio_deps"
SLICER_BUILD="${REPO_ROOT}/build/${ARCH}"
APP_BUNDLE="${SLICER_BUILD}/BambuStudio/BambuStudio.app"
PLUGINS_DIR="${HOME}/Library/Application Support/BambuStudio/plugins"
SKIP_DEPS=0

if [[ "${1:-}" == "--no-deps" ]]; then
    SKIP_DEPS=1
fi

cd "${REPO_ROOT}"

echo "=== BambuStudio privacy fork — arm64 build ==="
echo "    Repo:        ${REPO_ROOT}"
echo "    Build type:  ${BUILD_TYPE}"
echo "    Deps:        ${DEPS_INSTALL}"
echo ""

# ── Step 1: CMake 4.x compatibility fixes ────────────────────────────────────
# Must be applied before any cmake configure. Re-run after upstream updates.
echo "[1/6] Applying CMake 4.x compatibility fixes to src/ bundled libs..."
find "${REPO_ROOT}/src" -name "CMakeLists.txt" -print0 | \
    xargs -0 grep -lZ 'cmake_minimum_required(VERSION [0-2]\.' 2>/dev/null | \
    xargs -0 sed -i '' \
    's/cmake_minimum_required(VERSION [0-9][0-9.]*)/cmake_minimum_required(VERSION 3.5)/g' \
    2>/dev/null || true
echo "    Done."

# ── Step 2: Build dependencies ────────────────────────────────────────────────
if [[ "${SKIP_DEPS}" == "0" ]]; then
    echo "[2/6] Building dependencies (this takes ~30 min on first run)..."
    DEP_BUILD_DIR="${REPO_ROOT}/deps/build/${ARCH}"
    mkdir -p "${DEP_BUILD_DIR}"
    cmake -S "${REPO_ROOT}/deps" -B "${DEP_BUILD_DIR}" \
        -G Ninja \
        -DDESTDIR="${DEPS_INSTALL}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="${ARCH}" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="11.0"
    echo "    Configured. Building..."
    ninja -C "${DEP_BUILD_DIR}" -j"$(sysctl -n hw.logicalcpu)"

    # Fix wxWidgets cotire module CMake 4.x compat (in build tree after configure)
    COTIRE_DIR="${DEP_BUILD_DIR}/dep_wxWidgets-prefix/src/dep_wxWidgets/build/cmake/modules"
    if [[ -d "${COTIRE_DIR}" ]]; then
        echo "    Fixing wxWidgets cotire CMake version..."
        sed -i '' \
            's/cmake_minimum_required(VERSION [0-9][0-9.]*)/cmake_minimum_required(VERSION 3.5)/g' \
            "${COTIRE_DIR}/cotire.cmake" \
            "${COTIRE_DIR}/cotire_test/CMakeLists.txt" 2>/dev/null || true
    fi
    echo "    Dependencies built."
else
    echo "[2/6] Skipping dep build (--no-deps)."
    if [[ ! -d "${DEPS_INSTALL}" ]]; then
        echo "ERROR: ${DEPS_INSTALL} not found. Run without --no-deps first."
        exit 1
    fi
fi

# ── Step 3: Configure slicer ─────────────────────────────────────────────────
echo "[3/6] Configuring slicer..."
mkdir -p "${SLICER_BUILD}"
cmake -S "${REPO_ROOT}" -B "${SLICER_BUILD}" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
    -DBBL_RELEASE_TO_PUBLIC=1 \
    -DCMAKE_PREFIX_PATH="${DEPS_INSTALL}/usr/local" \
    -DCMAKE_OSX_ARCHITECTURES="${ARCH}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="11.0"
echo "    Configured."

# ── Step 4: Build ────────────────────────────────────────────────────────────
echo "[4/6] Building (ninja -j$(sysctl -n hw.logicalcpu))..."
ninja -C "${SLICER_BUILD}" -j"$(sysctl -n hw.logicalcpu)" BambuStudio
echo "    Build complete."
echo "    App bundle: ${APP_BUNDLE}"

# ── Step 5: Bundle fix — create Frameworks directory ─────────────────────────
echo "[5/6] Setting up bundle Frameworks directory..."
mkdir -p "${APP_BUNDLE}/Contents/Frameworks"
echo "    Created: ${APP_BUNDLE}/Contents/Frameworks/"

# ── Step 6: Copy dylibs ───────────────────────────────────────────────────────
echo "[6/6] Copying bambu_networking dylibs..."

if [[ ! -d "${PLUGINS_DIR}" ]]; then
    echo ""
    echo "WARNING: Plugin directory not found: ${PLUGINS_DIR}"
    echo "         Launch the retail BambuStudio once to download the dylibs,"
    echo "         then re-run this script from step 5."
    echo "         Or copy manually:"
    echo "           cp <plugins>/libbambu_networking.dylib  ${APP_BUNDLE}/Contents/Frameworks/bambu_networking.dylib"
    echo "           cp <plugins>/libBambuSource.dylib       ${APP_BUNDLE}/Contents/Frameworks/"
    echo "           cp <plugins>/liblive555.dylib           ${APP_BUNDLE}/Contents/Frameworks/"
    exit 0
fi

# libbambu_networking.dylib → bambu_networking.dylib (rename on copy)
cp "${PLUGINS_DIR}/libbambu_networking.dylib" \
   "${APP_BUNDLE}/Contents/Frameworks/bambu_networking.dylib"

cp "${PLUGINS_DIR}/libBambuSource.dylib" \
   "${APP_BUNDLE}/Contents/Frameworks/libBambuSource.dylib"

cp "${PLUGINS_DIR}/liblive555.dylib" \
   "${APP_BUNDLE}/Contents/Frameworks/liblive555.dylib"

# Strip quarantine attribute
xattr -cr "${APP_BUNDLE}"

echo ""
echo "=== Build complete ==="
echo "    App: ${APP_BUNDLE}"
echo "    open \"${APP_BUNDLE}\""
