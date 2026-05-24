# BambuStudio Privacy Fork — Validation Checklist

Run after every build and after every upstream rebase.
All items must pass before shipping a build.

---

## Prerequisites

```bash
# Start a tcpdump capture for network validation tests
sudo tcpdump -i en0 -n 'host bambulab.com or host bambu-lab.com or net 119.0.0.0/8' \
  -w /tmp/bbl-capture.pcap &
TCPDUMP_PID=$!

# Launch the app
open build/arm64/BambuStudio/BambuStudio.app

# Let it run for 60 seconds on the splash / main screen before checking
```

---

## 1. Telemetry Disable (P1)

**What it tests**: `NetworkAgent::track_enable()` always forces tracking off;
no `track_event` / `track_header` calls reach the closed binary with enable=true.

**Method**: Network capture + log check.

```bash
# Check for outbound analytics traffic
grep -c "analytics\|mixpanel\|amplitude\|segment\|track" /tmp/bbl-capture.pcap 2>/dev/null || \
  echo "No analytics domains seen"

# Check log for track_enable calls
grep "track_enable" ~/Library/Logs/BambuStudio/BambuStudio.log | tail -5
```

**Pass criteria**:
- [ ] No DNS queries to analytics domains in tcpdump
- [ ] `track_enable` log lines show enable=false or absent
- [ ] `track_event` calls may appear in log but must not produce outbound packets

---

## 2. Consent Reporting Disable (P2)

**What it tests**: `GUI_App::report_consent_common()` returns immediately;
no HTTP POST to Bambu's consent endpoint on startup or after dialogs.

**Method**: Network capture on startup.

```bash
# Look for POST to Bambu consent/privacy endpoints
tcpdump -r /tmp/bbl-capture.pcap -A 2>/dev/null | grep -i "consent\|privacy\|report" | head -10
```

**Pass criteria**:
- [ ] No outbound HTTP POST within first 10 seconds of startup
- [ ] No traffic to `*.bambulab.com` privacy or consent paths

---

## 3. Force-Upgrade Neutralization (P3 + P7)

**What it tests**: `check_update()` cannot force-close the app even if the
server returns `force_upgrade: true`; `check_new_version()` call is suppressed.

**Method**: Log check (no network call expected due to P7).

```bash
grep "check_new_version\|force_upgrade\|enter_force_upgrade" \
  ~/Library/Logs/BambuStudio/BambuStudio.log | tail -10
```

**Pass criteria**:
- [ ] No `check_new_version` request in log (P7 suppresses the call)
- [ ] If a version response somehow arrives, `force_upgrade` branch is never entered
- [ ] App does not close itself unprompted

---

## 4. Cloud Relay Blocked (P5 + P6)

**What it tests**: `connect_server()` and `start_subscribe()` return 0
immediately; no cloud MQTT websocket is established.

**Method**: Network capture + `is_server_connected()` behavioral check.

```bash
# Should see zero traffic to Bambu cloud MQTT endpoints (port 8883, 443)
tcpdump -r /tmp/bbl-capture.pcap -n 'port 8883 or port 443' 2>/dev/null | \
  grep -v "Apple\|iCloud\|cdnjs\|cloudflare" | head -20

# No Bambu server IPs
tcpdump -r /tmp/bbl-capture.pcap -n 2>/dev/null | \
  grep -E "119\.|cn-s3|mqtt.*bambu" | head -10
```

**Pass criteria**:
- [ ] No TCP connection to `*.bambulab.com:8883` (cloud MQTT)
- [ ] No cloud relay websocket established
- [ ] No Bambu server IPs in capture after startup completes

---

## 5. LAN Printing

**What it tests**: End-to-end print job over local MQTT; `connect_printer()`,
`start_local_print()`, and AMS filament routing all work correctly.

**Steps**:
1. Open BambuStudio
2. Ensure printer appears in device list (SSDP discovery working)
3. Open a 3MF or STL file
4. Slice it
5. Click Print → select printer
6. Confirm printer IP is shown (LAN mode indicator)
7. Send print job

```bash
# Confirm SSDP discovery traffic (UDP port 2021)
tcpdump -r /tmp/bbl-capture.pcap -n 'udp port 2021' | head -5

# Confirm local MQTT traffic to printer IP (port 8883)
# Replace PRINTER_IP with your printer's IP
PRINTER_IP="192.168.1.xxx"
tcpdump -r /tmp/bbl-capture.pcap -n "host ${PRINTER_IP}" | head -10
```

**Pass criteria**:
- [ ] Printer appears in device list without cloud login
- [ ] UDP SSDP traffic to/from printer IP visible in capture
- [ ] Print job sent successfully — printer starts printing
- [ ] Print status updates visible in BambuStudio during print
- [ ] No "Login required" dialog appears

---

## 6. AMS Filament State

**What it tests**: AMS filament state is received over local MQTT and displayed
correctly; the local MQTT parse loop in DeviceManager is unaffected.

**Steps**:
1. Select the printer in device list
2. Open the AMS panel / filament view
3. Confirm AMS slot colors and filament types match what is loaded

**Pass criteria**:
- [ ] AMS slot data visible in UI without cloud connection
- [ ] Filament type and color match physical AMS contents
- [ ] AMS state updates when filament is changed (test by re-selecting printer)

---

## 7. Local Camera (RTSP)

**What it tests**: Local RTSP camera stream via `bambu:///local/`,
`bambu:///rtsps___`, or `bambu:///rtsp___` — the path that bypasses
`get_camera_url()` (P10) entirely.

**Steps**:
1. Select printer in device list
2. Click the camera / liveview button
3. Confirm video stream starts
4. Check log for URL format

```bash
grep "bambu:///\|liveview\|MediaPlayCtrl" \
  ~/Library/Logs/BambuStudio/BambuStudio.log | grep -v "password\|passwd" | tail -10
```

**Pass criteria**:
- [ ] Camera stream starts without cloud login
- [ ] Log shows `bambu:///local/`, `bambu:///rtsps___`, or `bambu:///rtsp___` URL
- [ ] Log does NOT show `bambu:///tutk` or `bambu:///agora` URL
- [ ] No `get_camera_url` call proceeds to closed binary (confirmed by P10)

---

## 8. Firmware Update Prevention

**What it tests**: The slicer cannot auto-push firmware to the printer and cannot
force-close itself for a slicer update.

**Steps**:
1. Open the Device tab → firmware section
2. Confirm firmware version is shown
3. Confirm "Update" button is present but NOT auto-clicked

**Pass criteria**:
- [ ] No automatic firmware push (user must click to initiate)
- [ ] App does not pop a mandatory-update dialog that closes the app
- [ ] `DevUpgradeCtrl.cpp` functions only callable from user button presses

---

## 9. Login Expiry Dialogs Suppressed (P11)

**What it tests**: No "Login information expired" or "Failed to connect to
cloud device server" dialog appears during normal LAN-only operation.

**Steps**:
1. Run the app for 5+ minutes in LAN-only mode
2. Perform a print job
3. Confirm no unexpected dialogs appear

**Pass criteria**:
- [ ] No "Login information expired. Please login again." dialog
- [ ] No "Failed to connect to the cloud device server." dialog
- [ ] No HTTP 401 errors surfaced to user

---

## 10. Plugin Sync Freeze (P8)

**What it tests**: `bambu_networking.dylib` is not re-downloaded on launch;
the version in `Contents/Frameworks/` is stable across restarts.

```bash
APP="build/arm64/BambuStudio/BambuStudio.app"

# Record dylib modification time before launch
BEFORE=$(stat -f "%m" "${APP}/Contents/Frameworks/bambu_networking.dylib")

# Launch and quit
open "${APP}"
sleep 15
osascript -e 'quit app "BambuStudio"'
sleep 3

# Check modification time after quit
AFTER=$(stat -f "%m" "${APP}/Contents/Frameworks/bambu_networking.dylib")

if [[ "${BEFORE}" == "${AFTER}" ]]; then
    echo "PASS: dylib not modified"
else
    echo "FAIL: dylib was overwritten (P8 may not be applied)"
fi
```

**Pass criteria**:
- [ ] `bambu_networking.dylib` modification time unchanged after launch+quit
- [ ] No download traffic to Bambu plugin CDN in tcpdump

---

## Stop capture

```bash
kill ${TCPDUMP_PID} 2>/dev/null || true
echo "Capture saved: /tmp/bbl-capture.pcap"
```

---

## Validation Sign-off

| Test | Result | Date | Notes |
|------|--------|------|-------|
| 1. Telemetry disable | | | |
| 2. Consent reporting | | | |
| 3. Force-upgrade neutralization | | | |
| 4. Cloud relay blocked | | | |
| 5. LAN printing | | | |
| 6. AMS filament state | | | |
| 7. Local camera RTSP | | | |
| 8. Firmware update prevention | | | |
| 9. Login expiry dialogs | | | |
| 10. Plugin sync freeze | | | |
