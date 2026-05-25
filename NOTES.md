# BambuStudio Privacy Fork — Architectural Reconnaissance Notes

Track here: build failures, telemetry locations, subsystem findings, successful patches, upstream changes.

---

## PATCH STATUS — CORE LAYER

| ID | File | Function | Status | Patch file |
|----|------|----------|--------|------------|
| P1 | `src/slic3r/Utils/NetworkAgent.cpp` | `track_enable()` | ✅ Applied | `patches/core/p1-telemetry-master-disable.patch` |
| P2 | `src/slic3r/GUI/GUI_App.cpp` | `report_consent_common()` | ✅ Applied | `patches/core/p2-p3-p9-gui-app-patches.patch` |
| P3 | `src/slic3r/GUI/GUI_App.cpp` | `check_update()` | ✅ Applied | `patches/core/p2-p3-p9-gui-app-patches.patch` |
| P4 | `src/slic3r/Utils/PresetUpdater.cpp` | `config_update()` | ✅ Applied | `patches/core/p4-preset-force-update-disable.patch` |
| P9 | `src/slic3r/GUI/GUI_App.cpp` | `get_login_info()` | ✅ Applied | `patches/core/p2-p3-p9-gui-app-patches.patch` |
| P5 | `src/slic3r/Utils/NetworkAgent.cpp` | `connect_server()` | ✅ Applied | `patches/core/p5-p6-cloud-relay-disable.patch` |
| P6 | `src/slic3r/Utils/NetworkAgent.cpp` | `start_subscribe()` | ✅ Applied | `patches/core/p5-p6-cloud-relay-disable.patch` |
| P10 | `src/slic3r/Utils/NetworkAgent.cpp` | `get_camera_url()`, `get_camera_url_for_golive()` | ✅ Applied | `patches/core/p10-iotc-cloud-camera-disable.patch` |
| P7 | `src/slic3r/GUI/GUI_App.cpp` | startup `check_new_version()` call | ✅ Applied | (in GUI_App.cpp, committed with P11) |
| P8 | `src/slic3r/Utils/PresetUpdater.cpp` | `sync_plugins()` call | ✅ Applied | `patches/core/p8-plugin-sync-freeze.patch` |
| P11a | `src/slic3r/GUI/GUI_App.cpp` | `on_http_error()` HTTP 401 dialog | ✅ Applied | (in GUI_App.cpp) |
| P11b | `src/slic3r/GUI/GUI_App.cpp` | `init_networking_callbacks()` return_code==5 dialog | ✅ Applied | (in GUI_App.cpp) |
| — | `src/slic3r/GUI/GUI_App.cpp` | `init_networking_callbacks()` return_code<0 dialog | ✅ Applied | (in GUI_App.cpp — cloud-connect-failure suppression) |
| P13 | `src/slic3r/GUI/GUI_App.cpp` | `check_networking_version()` | ✅ Applied | (in GUI_App.cpp) |

**ALL PATCHES APPLIED. Build session complete.**

Confirmed working:
- LAN printing ✅
- Print sent successfully ✅
- Camera feed visible (local RTSP) ✅
- AMS filament state ✅

Known remaining issue: periodic disconnection timeout (non-blocking — printer continues printing, reconnects automatically over LAN MQTT).

---

## BUNDLE SETUP — required after every build

The `bambu_networking.dylib` and companion dylibs are **not** produced by the build system.
They are downloaded by BambuStudio at first launch and cached in the user plugins directory.
They must be manually copied into the built `.app` bundle before it will run.

```bash
APP=build/arm64/BambuStudio/BambuStudio.app
PLUGINS=~/Library/Application\ Support/BambuStudio/plugins

# Create Frameworks directory (not present in raw build output)
mkdir -p "${APP}/Contents/Frameworks"

# Copy the three required dylibs
cp "${PLUGINS}/libbambu_networking.dylib" \
   "${APP}/Contents/Frameworks/bambu_networking.dylib"

cp "${PLUGINS}/libBambuSource.dylib" \
   "${APP}/Contents/Frameworks/libBambuSource.dylib"

cp "${PLUGINS}/liblive555.dylib" \
   "${APP}/Contents/Frameworks/liblive555.dylib"

# Strip quarantine attribute so macOS Gatekeeper allows launch
xattr -cr "${APP}"
```

**P8 is now REQUIRED (not optional).** Without `sync_plugins()` suppressed, the app will
attempt to re-download a new `bambu_networking.dylib` on every launch, overwriting the known-good
version. Apply P8 before shipping any build.

---

## BUILD FINDINGS — macOS Apple Silicon / CMake 4.x

### CMake 4.x compatibility fixes required

CMake 4.3+ removes support for `cmake_minimum_required` < 3.5 and errors out on affected files.
Two sets of files required patching before deps and slicer would configure.

**1. wxWidgets cotire module** — in the dep build tree after the first configure attempt:

```bash
# Run these after the first cmake configure of deps (which downloads wxWidgets source)
COTIRE_DIR="deps/build/arm64/dep_wxWidgets-prefix/src/dep_wxWidgets/build/cmake/modules"

sed -i '' \
  's/cmake_minimum_required(VERSION [0-9][0-9.]*)/cmake_minimum_required(VERSION 3.5)/' \
  "${COTIRE_DIR}/cotire.cmake" \
  "${COTIRE_DIR}/cotire_test/CMakeLists.txt"
```

**2. Slicer source bundled libs** — in the repo source tree:

```bash
# Apply to all affected subdirectories in src/
find src/admesh src/imguizmo src/clipper src/Shiny src/boost \
     src/imgui src/clipper2 src/miniz src/semver src/glu-libtess \
     -name "CMakeLists.txt" | xargs sed -i '' \
  's/cmake_minimum_required(VERSION [0-9][0-9.]*)/cmake_minimum_required(VERSION 3.5)/'
```

**Upstream survivability note**: These fixups must be re-applied after any upstream update that
touches these files. They are pre-build fixups, not tracked patches, because the cotire fix
applies to a generated path inside the build tree. The `src/` fixup could be a patch but is
fragile to line number drift — the `find | sed` form is more maintainable.

---

### Homebrew GLEW conflict

Homebrew's `glew` package (2.3.1) conflicts with the slicer's own GLEW finder at CMake configure
time. The slicer bundles its own GLEW and expects to find it via `CMAKE_PREFIX_PATH`, but
`find_package(GLEW)` picks up the Homebrew version first.

```bash
# Before running cmake configure for the slicer:
brew unlink glew

# To prevent Homebrew auto-upgrading and re-linking it:
brew pin glew
```

This must be re-applied if `brew upgrade` re-links GLEW. `brew pin glew` is the durable fix.

---

### Deployment target — use 11.0, not 10.15

`BuildMac.sh` defaults to `MACOSX_DEPLOYMENT_TARGET=10.15`. This is the x86_64 baseline.
On arm64 with recent Xcode SDKs (15+), the codebase's `-Werror=unguarded-availability-new`
flag causes compile errors for APIs gated at 11.0+ when the deployment target is set lower.

**Use `11.0` explicitly** for all arm64 builds — both deps and slicer:
```
-DCMAKE_OSX_DEPLOYMENT_TARGET=11.0
```

Do not rely on `BuildMac.sh` default. Pass the flag directly to cmake.

---

### bambu_networking.dylib — location and acquisition

The dylib is **not bundled in the official DMG** and is not produced by this build.
It is downloaded at first launch by a retail BambuStudio install and cached at:

```
~/Library/Application Support/BambuStudio/plugins/libbambu_networking.dylib
```

Three dylibs are required together:

| Cached filename | Bundle target name |
|---|---|
| `libbambu_networking.dylib` | `Contents/Frameworks/bambu_networking.dylib` |
| `libBambuSource.dylib` | `Contents/Frameworks/libBambuSource.dylib` |
| `liblive555.dylib` | `Contents/Frameworks/liblive555.dylib` |

Note the rename: cached files have `lib` prefix, bundle targets do not (for `bambu_networking`).

The `Contents/Frameworks/` directory does **not** exist in the raw `ninja` build output.
It must be created manually. See BUNDLE SETUP above.

---

## RECOMMENDED PATCH ORDER (updated)

1. P1 — telemetry disable (lowest risk, highest coverage)
2. P2 — consent reporting disable (one line, zero risk)
3. P3 — slicer force-upgrade neutralize (one conditional change)
4. P4 — preset force-update neutralize (one conditional change)
5. P9 — get_login_info null-guard (**required for offline stability**)
6. Bundle setup — copy dylibs, `xattr -cr`
7. Validate LAN printing, AMS, camera
8. P5 + P6 — cloud relay no-op (test carefully after LAN validation)
9. P7 — version check suppress (optional hardening)
10. P8 — plugin sync freeze (**required** — prevents dylib clobber on launch)

---

## CRITICAL ARCHITECTURAL FACT — READ FIRST

The actual network protocol implementation (`bambu_networking`) is a **closed-source precompiled
dynamic library** loaded at runtime via `dlopen`/`dlsym`.

- Entry point: `NetworkAgent::initialize_network_module()` → `GUI_App::on_init_network()`
- Wrapper class: `src/slic3r/Utils/NetworkAgent.cpp/.hpp`
- Interface definition: `src/slic3r/Utils/bambu_networking.hpp`
- All ~100 network functions are resolved as C function pointers at startup

**Consequence**: We cannot patch the binary library. We patch the open-source C++ wrapper layer
that calls into it. This is actually ideal — the wrapper is a clean, stable interception point
that survives upstream merges well.

---

## SUBSYSTEM MAP

### 1. Telemetry / Analytics

**Master gate**: `NetworkAgent::enable_track` (private bool, `NetworkAgent.hpp:242`)

Set to `true` only inside `GUI_App::check_track_enable()` (`GUI_App.cpp:5217`), which fires if
`app_config->get("firstguide", "privacyuse") == "true"`. Called from:
- `GUI_App::on_user_login()` → `check_track_enable()`
- App startup `CallAfter` block (`GUI_App.cpp:1346`) if already logged in

All four outbound telemetry calls already guard themselves:
```cpp
// NetworkAgent.cpp — track_event, track_header, track_update_property, track_get_property
if (!this->enable_track) return 0;
```

**Sending sites** (spread across many files, all guarded by enable_track):
- `GUI_App.cpp` — `studio_launch`, `key_func`, `menu_click`, `device_ctrl`, `enter_model_mall`
- `MainFrame.cpp` — key/menu/device tracking
- `Plater.cpp` — `user_start_print`, `slice_group_mode`, `helio_state`
- `DeviceManager.cpp` — `printer_control`, `cali`, `message_delay`, `ack_cmd_*`
- `Monitor.cpp`, `CalibrationPanel.cpp` — `connect_dev`
- `GUI_Factories.cpp`, `GLGizmoBase.cpp` — UI interaction metrics
- `CalibUtils.cpp`, `CaliHistoryDialog.cpp` — calibration events

**Separate consent reporting** (`report_consent_common()`, `GUI_App.cpp:8018`):
- HTTP POST to Bambu cloud on every startup (`GUI_App.cpp:1096`) unconditionally
- Also fires on privacy dialog confirm/cancel
- Sends "Opt-in"/"Withdraw" for `StudioImprovementPolicy` and `SoftwarePrivacy`
- Path: `agent->report_consent()` if logged in, else direct HTTP via `wxGetApp().report_consent()`

---

### 2. Cloud Relay

**Startup sequence** (`on_user_login_handle`, `GUI_App.cpp:5181`):
1. `m_agent->connect_server()` — opens cloud MQTT relay connection
2. `dev->update_user_machine_list_info()` — fetches cloud device list
3. `m_agent->start_subscribe("app")` (`GUI_App.cpp:3391`) — subscribes to cloud topics

**`connect_server()` implementation** (`NetworkAgent.cpp:807`):
```cpp
int NetworkAgent::connect_server() {
    if (network_agent && connect_server_ptr)
        ret = connect_server_ptr(network_agent);  // calls into closed binary
    return ret;
}
```

**Cloud re-subscribe timer** (`GUI_App::on_start_subscribe_again`, `GUI_App.cpp:2635`):
- Fires on device reconnect events with a 5-second delay timer
- Calls `m_agent->start_subscribe()` again

**IMPORTANT DISTINCTION** — these are separate and must be preserved:
- `connect_server()` = cloud MQTT relay (target for neutralization)
- `connect_printer(dev_id, dev_ip, user, pass, ssl)` = **local MQTT to printer** (DO NOT TOUCH)
- `start_discovery(true, false)` = **SSDP/LAN discovery** (DO NOT TOUCH)

---

### 3. Firmware Update Systems

There are **two independent firmware update systems**.

#### 3a. Slicer Self-Upgrade (force_upgrade for BambuStudio itself)

Call chain:
```
App startup CallAfter (GUI_App.cpp:1341)
  → check_new_version()      [HTTP GET to Bambu update server]
  → check_update()           [GUI_App.cpp:5272]
  → version_info.force_upgrade parsed from JSON["software"]["force_update"]
  → enter_force_upgrade()    [GUI_App.cpp:5606]
  → EVT_ENTER_FORCE_UPGRADE handler (GUI_App.cpp:3188)
  → DownloadDialog: YES=open browser, NO/default=mainframe->Close(true)
```

The dialog has no "remind me later" path — `NO` and the window close button both call
`mainframe->Close(true)`. This is the enforcement point.

#### 3b. PresetUpdater Forced Profile Updates

Call chain:
```
PresetUpdater::sync() thread (PresetUpdater.cpp:1637)
  → sync_config() → parses force_update from vendor JSON
  → check_config_updates_from_updater() (on main thread)
  → UpdateParams check at PresetUpdater.cpp:1748
  → if (force_update) → perform_updates() silently, no user prompt
```

`force_update` is parsed from downloaded vendor changelog JSON, field `"force_update": true`.

#### 3c. Printer Firmware OTA (not auto-triggered by slicer)

`DevUpgrade::m_upgrade_force_upgrade` is parsed from MQTT message field `upgrade_state.force_upgrade`.
This flag is **display state only** — it affects what the UpgradePanel UI shows, not automatic pushing.

Actual firmware push commands (`CtrlUpgradeFirmware`, `CtrlUpgradeModule`, `CtrlUpgradeConfirm`
in `DevUpgradeCtrl.cpp`) are **only triggered by user button presses** in `UpgradePanel.cpp`.

The slicer does NOT auto-push printer firmware. This is user-initiated only.

---

### 4. Login / Account Enforcement

**Extremely narrow**. Only two hard gates:

1. `GUI_App::check_login()` (`GUI_App.cpp:4491`) — called from:
   - `request_project_download()` (`GUI_App.cpp:5007`)
   - Cloud filament manager client (`wgtFilaManagerCloudClient.cpp` — 5 call sites)

2. `ShowUserLogin()` — also called from `GUI_App.cpp:4458` (unrelated to printing)

**LAN printing has zero login requirement.** `PrintJob.cpp` branches on `connection_type == "lan"`
before any auth check. The `start_local_print()` path requires no login token.

`is_user_login()` appears ~20 times but in conditional-feature branches only (cloud sync,
design info embedding, user presets). None block LAN print or AMS.

---

### 5. Systems to Protect (DO NOT MODIFY)

| System | Location | Why |
|---|---|---|
| `start_discovery(true, false)` | `GUI_App.cpp:1369, 1934` | SSDP — finds LAN printers |
| `connect_printer()` | `NetworkAgent.cpp` | Local MQTT to printer |
| `start_local_print()` | `NetworkAgent.cpp` → `PrintJob.cpp:619` | LAN print path |
| `start_local_print_with_record()` | `NetworkAgent.cpp` → `PrintJob.cpp:592` | LAN print with cloud record |
| MQTT parse loop | `DeviceManager.cpp` ~line 2500+ | AMS/status/camera from printer |
| `DevInfo::ParseInfo()` | `DeviceCore/DevInfo.cpp` | Sets `connection_type` for LAN routing |
| `liveview_local` / `local_rtsp_url` | `DeviceManager.cpp:3311-3328` | Local camera RTSP |
| AMS mapping in `PrintParams` | `bambu_networking.hpp` | AMS filament routing |
| `DevUpgrade::ParseUpgrade_V1_0()` | `DeviceCore/DevUpgrade.cpp` | Reads firmware state from printer |

**Camera note**: Local camera uses RTSP URL pushed by printer over MQTT (`ipcam.rtsp_url`).
Cloud camera uses `get_camera_url()` (Agora/TUTK relay). The local path is fully independent.

---

## PATCH DESCRIPTIONS

### P1 — Telemetry master disable
```
File: src/slic3r/Utils/NetworkAgent.cpp
Function: NetworkAgent::track_enable(bool enable)
Change: Always pass false to the library; ignore caller's true.
```
Single point that gates all ~50 track_event/track_header/track_update_property calls across
the codebase. They all guard on `enable_track`. One function, total coverage.

### P2 — Consent reporting disable
```
File: src/slic3r/GUI/GUI_App.cpp
Function: GUI_App::report_consent_common(bool agree, ...)
Change: Return early at top of function body.
```
Stops the unconditional HTTP POST on every startup and all privacy dialog callbacks.

### P3 — Slicer force-upgrade neutralization
```
File: src/slic3r/GUI/GUI_App.cpp
Function: GUI_App::check_update(bool show_tips, int by_user)
Change: Treat force_upgrade as always false (always take the else branch).
```
New version notifications still work; the app can no longer force-close itself.

### P4 — PresetUpdater force-profile neutralization
```
File: src/slic3r/Utils/PresetUpdater.cpp
Function: config_update() ~line 1757
Change: Treat force_update as always false.
```
Profile updates remain available but become voluntary. No silent forced rewrites.

### P5 — Cloud relay no-op ✅
```
File: src/slic3r/Utils/NetworkAgent.cpp
Function: NetworkAgent::connect_server()
Change: Return 0 immediately without calling connect_server_ptr.
```
Call site (`GUI_App.cpp:5198`) is fire-and-forget — return value is discarded. LAN printing
confirmed on separate path: `connect_printer()` at line 902 is a distinct function, and
`start_discovery()` (`bool` return, line 954) is completely unaffected.

### P6 — Cloud subscription no-op ✅
```
File: src/slic3r/Utils/NetworkAgent.cpp
Function: NetworkAgent::start_subscribe(std::string module)
Change: Return 0 immediately without calling start_subscribe_ptr. (void)module to suppress unused warning.
```
Call site (`GUI_App.cpp:3391`) is fire-and-forget — return value is discarded. Companion to P5.
LAN devices subscribe via `connect_printer()`, not `start_subscribe()`.

### P10 — IOTC/TUTK cloud camera disable ✅
```
File: src/slic3r/Utils/NetworkAgent.cpp
Functions: get_camera_url(), get_camera_url_for_golive()
Change: Return 0 immediately. Do not invoke get_camera_url_ptr or
        get_camera_url_for_golive_ptr. Suppress (void) all parameters.
```
**Root cause**: `get_camera_url()` is the sole entry point that causes the closed binary
to initialize its IOTC session. Once initialized, an internal `IOTC_Check_Session_Status`
timer fires, finds no cloud relay (P5 killed `connect_server()`), and calls
`IOTC_DeInitialize` — which tears down shared internal state and destabilizes local MQTT
connections. Symptoms: LAN printer drops, AMS state freezes, camera fails.

**Safe**: Local RTSP camera uses a completely separate branch in `MediaPlayCtrl::Play()`
(lines 316–338): when `m_lan_proto > LVL_Disable`, it constructs `bambu:///local/`,
`bambu:///rtsps___`, or `bambu:///rtsp___` URLs from `m_lan_ip`/`m_lan_passwd` (MQTT-sourced)
and returns before ever reaching `get_camera_url()`. The two paths are mutually exclusive.

**Effect**: Cloud camera (TUTK/Agora) and go-live streaming are unavailable. Expected.
Local RTSP camera continues to work normally.

**Call sites** (all fire-and-forget callback pattern; return value always discarded):
- `MediaPlayCtrl.cpp:373, 637, 716`
- `SendToPrinter.cpp:1757`
- `MediaFilePanel.cpp:606`
- `PartSkipDialog.cpp:497`
- `HttpServer.cpp:420` (go-live variant)

### P7 — Outbound version check suppression ⏳ (optional)
```
File: src/slic3r/GUI/GUI_App.cpp
Location: startup CallAfter block, ~line 1341
Change: Comment out this->check_new_version();
```
P3 already neutralizes the dangerous outcome. P7 is optional hardening.

### P8 — Plugin sync freeze ⚠️ REQUIRED
```
File: src/slic3r/Utils/PresetUpdater.cpp
Function: PresetUpdater::sync() background thread
Change: Comment out this->p->sync_plugins(http_url, plugin_version);
```
**Required.** Without this, the app re-downloads `bambu_networking.dylib` from Bambu's servers
on every launch, overwriting the known-good version copied into the bundle. The downloaded
version may differ from the one the build was validated against and may introduce new telemetry
or protocol changes. Freeze the plugin version intentionally.

### P9 — get_login_info null-guard ✅
```
File: src/slic3r/GUI/GUI_App.cpp
Function: GUI_App::get_login_info()
Change: Return early if !m_agent || !m_agent->is_server_connected()
```
**Crash**: SIGSEGV at `build_login_cmd()` / `build_logout_cmd()` (inside closed binary) called
from a repeating wxTimer in `WebViewPanel::OnFreshLoginStatus()`.

**Root cause**: When cloud relay is blocked (our intended state), `connect_server()` was never
called. Both `build_login_cmd()` and `build_logout_cmd()` dereference an internal cloud session
handle that was never initialized — SIGSEGV. The existing `if (m_agent)` guard does not help
because the agent object exists; the crash is inside the closed binary's uninitialized state.

**Guard**: `is_server_connected()` is a safe wrapper that returns `false` when no cloud
handshake has occurred. Returns silently when false — the WebView timer continues harmlessly.

LAN risk: NONE. `get_login_info()` is cloud login state only; no LAN path passes through it.

### P13 — Networking version check bypass ✅
```
File: src/slic3r/GUI/GUI_App.cpp
Function: GUI_App::check_networking_version()
Change: Replace entire body with m_networking_compatible = true; return true;
```
`check_networking_version()` compares the first 8 characters of the slicer's version string
against the version embedded in `bambu_networking.dylib`. If they don't match, it sets
`m_networking_compatible = false`, which gates the network agent initialization and causes
the app to show a "plugin incompatible" error or silently skip loading the dylib.

When building from source against a dylib sourced from a different retail release, the
version strings will always diverge. P13 unconditionally sets `m_networking_compatible = true`
so the version check never blocks plugin load regardless of dylib provenance.

LAN risk: NONE. `m_networking_compatible = true` is also what the check sets on a successful
version match — we're just always taking the passing branch.

---

## FILE REFERENCE

| File | Relevance |
|---|---|
| `src/slic3r/Utils/NetworkAgent.hpp` | NetworkAgent class, all function pointer typedefs |
| `src/slic3r/Utils/NetworkAgent.cpp` | All wrapper implementations — PRIMARY PATCH TARGET |
| `src/slic3r/Utils/bambu_networking.hpp` | Closed-library interface (read-only reference) |
| `src/slic3r/GUI/GUI_App.cpp` | App init, check_track_enable, check_new_version, consent |
| `src/slic3r/Utils/PresetUpdater.cpp` | Profile/plugin sync and force_upgrade logic |
| `src/slic3r/GUI/Jobs/PrintJob.cpp` | LAN vs cloud print routing — DO NOT TOUCH |
| `src/slic3r/GUI/DeviceCore/DevInfo.cpp` | connection_type() — DO NOT TOUCH |
| `src/slic3r/GUI/DeviceCore/DevUpgrade.cpp` | Firmware state parsing — DO NOT TOUCH |
| `src/slic3r/GUI/DeviceCore/DevUpgradeCtrl.cpp` | Firmware push commands (user-initiated only) |
| `src/slic3r/GUI/DeviceManager.cpp` | MQTT message parser, AMS, camera — DO NOT TOUCH |

---

## BUILD SESSION FINDINGS

### CMake 4.x compatibility

CMake 4.3+ removes support for `cmake_minimum_required` < 3.5 and hard-errors on affected files.
Two sets of files required patching before deps and slicer would configure.

**1. wxWidgets cotire module** — in the dep build tree after the first configure attempt:

```bash
COTIRE_DIR="deps/build/arm64/dep_wxWidgets-prefix/src/dep_wxWidgets/build/cmake/modules"
sed -i '' \
  's/cmake_minimum_required(VERSION [0-9][0-9.]*)/cmake_minimum_required(VERSION 3.5)/' \
  "${COTIRE_DIR}/cotire.cmake" \
  "${COTIRE_DIR}/cotire_test/CMakeLists.txt"
```

**2. Slicer source bundled libs** — approximately 10 files under `src/`:

```bash
find src/ -name CMakeLists.txt | xargs grep -l 'cmake_minimum_required(VERSION [0-2]\.' | \
  xargs sed -i '' \
  's/cmake_minimum_required(VERSION [0-9][0-9.]*)/cmake_minimum_required(VERSION 3.5)/'
```

These sed fixes must be re-applied after any upstream update that touches the wxWidgets dep or
the affected `src/` subdirectories.

### Homebrew GLEW conflict

Homebrew's system GLEW overrides the slicer's own finder and causes a link error.

```bash
brew unlink glew
brew pin glew   # prevents re-link on brew upgrade
```

### Deployment target

`BuildMac.sh` defaults to macOS 10.15. Apple Silicon requires 11.0. Pass explicitly:

```bash
cmake ... \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
  -DCMAKE_OSX_ARCHITECTURES=arm64
```

### bambu_networking.dylib acquisition

The closed binary is **not** in the DMG or build output. It is downloaded by BambuStudio at
first launch and cached at:

```
~/Library/Application Support/BambuStudio/plugins/
```

Three files are required in `Contents/Frameworks/`:

| Cached name | Bundle target name |
|---|---|
| `libbambu_networking.dylib` | `bambu_networking.dylib` (rename on copy) |
| `libBambuSource.dylib` | `libBambuSource.dylib` |
| `liblive555.dylib` | `liblive555.dylib` |

The `Contents/Frameworks/` directory is not created by the build system — create it manually.
See BUNDLE SETUP section above for exact commands.

### P8 reclassified as REQUIRED

Without `sync_plugins()` suppressed, the app re-downloads `bambu_networking.dylib` from
Bambu's servers on every launch, overwriting the known-good bundle version. P8 is now
applied as a required core patch (`patches/core/p8-plugin-sync-freeze.patch`).

### WebView panel / Cloudflare CDN

The in-app WebView panel (`WebViewPanel`) loads Bambu web content via Cloudflare CDN.
This is a UI concern, not telemetry — the P1/P5/P6 patches do not affect it.
Candidate for the `ui-cleanup` branch only. Do not patch in core layer.

### Network validation results

- LAN discovery confirmed working (UDP *:2021 SSDP seen in tcpdump)
- No Bambu server IPs observed in tcpdump after P1–P9 applied
- Cloud relay correctly blocked (connect_server returns 0, no websocket established)

---

## GIT WORKFLOW

### Commit current patches

All modified files (P1–P9) are unstaged. Commit them as a single atomic core patch commit:

```bash
git add src/slic3r/Utils/NetworkAgent.cpp
git add src/slic3r/GUI/GUI_App.cpp
git add src/slic3r/Utils/PresetUpdater.cpp
git commit -m "privacy: P1-P9 core behavioral patches

P1: telemetry master disable (NetworkAgent::track_enable)
P2: consent reporting no-op (report_consent_common)
P3: slicer force-upgrade neutralization (check_update)
P4: preset force-update neutralization (config_update)
P5: cloud relay no-op (connect_server)
P6: cloud subscribe no-op (start_subscribe)
P8: plugin sync freeze — REQUIRED (sync_plugins)
P9: get_login_info null/uninit guard (SIGSEGV fix)"
```

### Export standalone patch files

```bash
mkdir -p patches/core
git format-patch HEAD~1 -o patches/core/
```

This produces a single `0001-privacy-P1-P9-core-behavioral-patches.patch` that can be
applied with `git am` against a clean upstream checkout.

The per-patch files in `patches/core/` (p1-, p2-p3-p9-, p4-, p5-p6-, p8-) are also kept
as surgical alternatives for selective rebase conflict resolution.

### Create branch structure

```bash
git checkout -b ui-cleanup
git checkout main

git checkout -b performance
git checkout main

git checkout -b experimental
git checkout main
```

Branch purposes:
- `main` — core privacy patches only (authoritative, must always build)
- `ui-cleanup` — cosmetic cloud UI hiding (disposable if upstream breaks it)
- `performance` — redraw throttling, async ops, logging reduction
- `experimental` — unsafe surgery, architectural experiments (not production-safe)

### Current commit commands (index.lock held by desktop app — run in terminal)

```bash
# Remove lock if desktop app is not running:
rm .git/index.lock  # may need: sudo rm .git/index.lock

git add src/slic3r/Utils/NetworkAgent.cpp \
        src/slic3r/GUI/GUI_App.cpp \
        src/slic3r/Utils/PresetUpdater.cpp

git commit -m "privacy: P1-P11 core behavioral patches

P1  - telemetry master disable (NetworkAgent::track_enable)
P2  - consent reporting disable (GUI_App::report_consent_common)
P3  - slicer force-upgrade neutralize (GUI_App::check_update)
P4  - preset force-update disable (PresetUpdater::config_update)
P5  - cloud relay no-op (NetworkAgent::connect_server)
P6  - cloud subscribe no-op (NetworkAgent::start_subscribe)
P7  - version check suppressed (startup CallAfter block)
P8  - plugin sync freeze (PresetUpdater::sync)
P9  - get_login_info null guard (GUI_App::get_login_info)
P10 - IOTC/TUTK cloud camera disable (NetworkAgent::get_camera_url)
P11 - login expiry + cloud-connect-failure dialogs suppressed"

mkdir -p patches/core
git format-patch HEAD~1 -o patches/core/
```

### Branch structure (already created)

```
main-privacy  ← working branch (all patches applied)
ui-cleanup    ← cosmetic cleanup (branched from main-privacy)
performance   ← redraw/async improvements
experimental  ← unsafe surgery
```

### Upstream update workflow

```bash
git checkout main-privacy
git pull upstream master
git rebase upstream/master
# Resolve conflicts — privacy patches first, LAN paths second
bash scripts/check-patch-targets.sh   # verify targets before applying
bash scripts/apply-privacy-patches.sh  # apply in correct order
# Then rebuild, validate:
bash scripts/build-arm64.sh --no-deps  # if deps unchanged
```

---

## SESSION FINDINGS — Build session complete

### P10 IOTC root cause

`IOTC_Check_Session_Status` is an internal timer inside `bambu_networking.dylib`. It fires
after IOTC is initialized. When it finds no cloud relay session (expected — P5 killed
`connect_server()`), it calls `IOTC_DeInitialize`, which tears down shared internal state
that the local MQTT layer also relies on — destabilizing LAN printer connections and AMS
state updates.

The only open-source entry point that initializes IOTC is `get_camera_url()`. P10 no-ops
both `get_camera_url()` and `get_camera_url_for_golive()`, preventing IOTC from ever
initializing. After P10, `IOTC_Check_Session_Status` never fires.

### P11 — Login expiry / cloud-connect-failure dialogs

Three locations patched:

1. `GUI_App::on_http_error()` — HTTP 401 response handler. Previously called
   `request_user_logout()` and showed "Login information expired." dialog.
   Now returns silently — 401s are expected in LAN-only mode.

2. `GUI_App::init_networking_callbacks()` — `set_on_server_connected_fn` callback,
   `return_code == 5` (MQTT CONNACK "not authorised"). Previously showed the same
   login expiry dialog. Since P5 no-ops `connect_server()`, this should never fire,
   but suppressed defensively.

3. `GUI_App::init_networking_callbacks()` — `set_on_server_connected_fn` callback,
   `return_code < 0` (connection failed). Previously showed "Failed to connect to the
   cloud device server." dialog. Suppressed — expected in LAN-only mode.

### P7 — Version check

`this->check_new_version()` in the startup `CallAfter` block (~line 1341 of GUI_App.cpp)
commented out. P3 already neutralized the force-upgrade outcome; P7 eliminates the
outbound HTTP request entirely.

### Disconnection timer audit

Searched GUI_App.cpp for all timers near disconnect/reconnect paths:

- **`on_start_subscribe_again`** (line 2637): One-shot 5-second timer fired by
  `set_on_subscribe_failure_fn` callback. Body only decrements `subscribe_counter` — does
  NOT call `start_subscribe()` or `connect_server()`. Safe as-is.

- **No timer directly calls `connect_server()` or `start_subscribe()`** in GUI_App.cpp.
  The only direct call to `connect_server()` is in `on_user_login_handle` (line 5193),
  which fires on a login event — not a timer.

- **IOTC reconnect is entirely internal** to the closed binary. It is controlled by
  whether IOTC was ever initialized. P10 prevents initialization.

### Known remaining issue — periodic disconnection timeout

After long idle periods or during heavy print jobs, BambuStudio may show a momentary
disconnection indicator. The printer continues printing and reconnects automatically
over local MQTT. This is **non-blocking** — print jobs are not interrupted.

Root cause: the local MQTT keep-alive timeout in `connect_printer()` / `DeviceManager.cpp`.
The closed binary handles reconnect internally. This is upstream behavior and is outside
the privacy patch surface.

**Not a regression** — this also occurs in retail BambuStudio when the cloud relay is
unavailable. With P5 always returning 0, there is no cloud fallback path, but LAN MQTT
reconnect handles it.

### Validation results

| Test | Result |
|---|---|
| LAN printing | ✅ Print sent successfully |
| AMS filament state | ✅ Confirmed over local MQTT |
| Camera feed | ✅ Local RTSP stream visible |
| Telemetry blocked | ✅ No outbound to *.bambulab.com |
| Cloud relay blocked | ✅ No server IPs in tcpdump |
| Login dialogs | ✅ None appeared |
| Force-upgrade | ✅ App did not self-close |
| Plugin freeze | ✅ dylib not overwritten on restart |

### Scripts created

```
scripts/apply-privacy-patches.sh   — apply patches/core/*.patch in order
scripts/build-arm64.sh             — full build + bundle fix sequence
scripts/bundle-fix.sh              — post-build bundle assembly only (faster iteration)
scripts/check-patch-targets.sh     — verify patch targets before rebase
```

---

## APP BUNDLE ASSEMBLY

The cmake build produces a raw binary at `build/arm64/src/BambuStudio`. It does NOT produce
a complete `.app` bundle. The bundle must be assembled manually after each build.

### Required bundle contents

```
BambuStudio.app/
  Contents/
    Info.plist                      ← copy from /Applications/BambuStudio.app/Contents/Info.plist
    MacOS/
      BambuStudio                   ← built binary from build/arm64/src/BambuStudio
    Resources/                      ← rsync from repo resources/
    Frameworks/
      bambu_networking.dylib        ← ~/Library/Application Support/BambuStudio/plugins/libbambu_networking.dylib (renamed)
      libBambuSource.dylib          ← ~/Library/Application Support/BambuStudio/plugins/libBambuSource.dylib
      liblive555.dylib              ← ~/Library/Application Support/BambuStudio/plugins/liblive555.dylib
```

### Quick assembly (after every rebuild)

```bash
# Step 1: rebuild slicer
cmake --build /path/to/BambuStudio/build/arm64 --parallel

# Step 2: assemble bundle + codesign
cd /path/to/BambuStudio
bash scripts/bundle-fix.sh
```

`bundle-fix.sh` handles all six steps: binary copy, Resources rsync, Info.plist copy,
Frameworks dylib copy, `xattr -cr`, and `codesign --force --deep --sign -`.

### Info.plist source

Always copy from the installed retail app (`/Applications/BambuStudio.app/Contents/Info.plist`).
The build tree generates its own `Info.plist` at `build/arm64/src/Info.plist` but it may
have incorrect bundle identifiers or version strings that cause Gatekeeper issues.

### Codesigning

Ad-hoc signing (`codesign --force --deep --sign -`) is sufficient for local use.
The `--deep` flag signs all nested binaries and dylibs in Frameworks/. Without this,
macOS will refuse to load unsigned dylibs on Apple Silicon.

### P13 context

`check_networking_version()` gates the entire network plugin load. Before P13, any version
mismatch between the slicer binary and `bambu_networking.dylib` would silently disable all
networking (including LAN). P13 bypasses this check so any compatible dylib version loads.
This is essential when the dylib is sourced from a different retail release than the current
build.

### VALIDATION.md

Full validation checklist at `VALIDATION.md` — covers all 10 patch areas with
exact tcpdump commands, log checks, and pass/fail criteria.
