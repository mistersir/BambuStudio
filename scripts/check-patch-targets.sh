#!/usr/bin/env bash
# check-patch-targets.sh
# Verify that each patched function signature still exists at the expected
# location in its target source file.
# Run from the repo root after an upstream merge to catch moved targets
# before attempting to apply patches.
#
# Exit code: 0 = all targets found, 1 = one or more targets moved/missing

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"

PASS=0
FAIL=0

check() {
    local description="$1"
    local file="$2"
    local pattern="$3"

    if grep -q "${pattern}" "${file}" 2>/dev/null; then
        echo "OK       ${description}"
        (( PASS++ )) || true
    else
        echo "WARNING  ${description}"
        echo "         File:    ${file}"
        echo "         Pattern: ${pattern}"
        echo "         >> Patch target may have moved or been renamed upstream <<"
        (( FAIL++ )) || true
    fi
}

echo "=== Checking privacy-fork patch targets ==="
echo ""

# P1 — telemetry master disable
check "P1  NetworkAgent::track_enable()" \
    "src/slic3r/Utils/NetworkAgent.cpp" \
    "int NetworkAgent::track_enable"

# P2 — consent reporting disable
check "P2  GUI_App::report_consent_common()" \
    "src/slic3r/GUI/GUI_App.cpp" \
    "void GUI_App::report_consent_common"

# P3 — slicer force-upgrade neutralize
check "P3  GUI_App::check_update()" \
    "src/slic3r/GUI/GUI_App.cpp" \
    "void GUI_App::check_update"

# P4 — preset force-update disable
check "P4  PresetUpdater::config_update()" \
    "src/slic3r/Utils/PresetUpdater.cpp" \
    "PresetUpdater::UpdateResult PresetUpdater::config_update"

# P5 — cloud relay no-op
check "P5  NetworkAgent::connect_server()" \
    "src/slic3r/Utils/NetworkAgent.cpp" \
    "int NetworkAgent::connect_server"

# P6 — cloud subscribe no-op
check "P6  NetworkAgent::start_subscribe()" \
    "src/slic3r/Utils/NetworkAgent.cpp" \
    "int NetworkAgent::start_subscribe"

# P7 — version check suppressed
check "P7  startup check_new_version call site" \
    "src/slic3r/GUI/GUI_App.cpp" \
    "check_new_version"

# P8 — plugin sync freeze
check "P8  PresetUpdater::sync() sync_plugins call site" \
    "src/slic3r/Utils/PresetUpdater.cpp" \
    "sync_plugins"

# P9 — get_login_info null guard
check "P9  GUI_App::get_login_info()" \
    "src/slic3r/GUI/GUI_App.cpp" \
    "void GUI_App::get_login_info"

# P10 — IOTC cloud camera disable
check "P10 NetworkAgent::get_camera_url()" \
    "src/slic3r/Utils/NetworkAgent.cpp" \
    "int NetworkAgent::get_camera_url"

check "P10 NetworkAgent::get_camera_url_for_golive()" \
    "src/slic3r/Utils/NetworkAgent.cpp" \
    "int NetworkAgent::get_camera_url_for_golive"

# P11a — HTTP 401 dialog suppression
check "P11a GUI_App::on_http_error() status==401 block" \
    "src/slic3r/GUI/GUI_App.cpp" \
    "void GUI_App::on_http_error"

# P11b — server-connected return_code==5 dialog suppression
check "P11b init_networking_callbacks set_on_server_connected_fn" \
    "src/slic3r/GUI/GUI_App.cpp" \
    "set_on_server_connected_fn"

echo ""
echo "=== Results: ${PASS} OK, ${FAIL} WARNING ==="
if [[ "${FAIL}" -gt 0 ]]; then
    echo ""
    echo "Re-run after locating the moved targets and updating patches."
    exit 1
fi
