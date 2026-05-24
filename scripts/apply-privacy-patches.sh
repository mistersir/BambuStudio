#!/usr/bin/env bash
# apply-privacy-patches.sh
# Apply all privacy-fork core patches to a clean upstream checkout.
# Run from the repo root.
#
# Usage:
#   bash scripts/apply-privacy-patches.sh          # apply
#   bash scripts/apply-privacy-patches.sh --check  # dry-run only

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCHES_DIR="${REPO_ROOT}/patches/core"
DRY_RUN=0

if [[ "${1:-}" == "--check" ]]; then
    DRY_RUN=1
    echo "=== DRY-RUN MODE: checking patches only ==="
fi

cd "${REPO_ROOT}"

# Ordered list — apply in this sequence after a clean upstream checkout
ORDERED_PATCHES=(
    "p1-telemetry-master-disable.patch"
    "p2-p3-p9-gui-app-patches.patch"
    "p4-preset-force-update-disable.patch"
    "p5-p6-cloud-relay-disable.patch"
    "p8-plugin-sync-freeze.patch"
    "p10-iotc-cloud-camera-disable.patch"
)

PASS=0
FAIL=0

for patch in "${ORDERED_PATCHES[@]}"; do
    patch_path="${PATCHES_DIR}/${patch}"

    if [[ ! -f "${patch_path}" ]]; then
        echo "MISSING  ${patch}"
        (( FAIL++ )) || true
        continue
    fi

    if [[ "${DRY_RUN}" == "1" ]]; then
        if git apply --check "${patch_path}" 2>/dev/null; then
            echo "OK       ${patch}"
            (( PASS++ )) || true
        else
            echo "FAILED   ${patch}  (apply --check failed — conflict or already applied)"
            (( FAIL++ )) || true
        fi
    else
        # First check, then apply
        if git apply --check "${patch_path}" 2>/dev/null; then
            git apply "${patch_path}"
            echo "APPLIED  ${patch}"
            (( PASS++ )) || true
        else
            # Already applied? Try reverse check
            if git apply --check --reverse "${patch_path}" 2>/dev/null; then
                echo "SKIP     ${patch}  (already applied)"
                (( PASS++ )) || true
            else
                echo "FAILED   ${patch}  (conflict — manual resolution required)"
                (( FAIL++ )) || true
            fi
        fi
    fi
done

echo ""
echo "=== Results: ${PASS} OK, ${FAIL} FAILED ==="
if [[ "${FAIL}" -gt 0 ]]; then
    exit 1
fi
