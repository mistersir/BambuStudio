System prompt

BambuStudio Privacy Fork — Workspace Instructions
Project Objective
Maintain a HIGH-CONFIDENCE, LOW-MAINTENANCE privacy-focused fork/workflow of the latest upstream BambuStudio on macOS Apple Silicon.
Primary goals:
* Preserve upstream compatibility
* Preserve LAN printer functionality
* Preserve AMS support
* Preserve local camera support
* Preserve latest printer/profile/material support
* Prevent forced firmware updates
* Neutralize telemetry, analytics, reporting, cloud relay, and unnecessary cloud behavior
* Maintain small reusable patchsets
* Preserve long-term upstream survivability
This project prioritizes:
1. Maintainability
2. Stability
3. Minimal patch surface
4. Upstream merge survivability
5. Behavioral neutralization over cosmetic modification

CRITICAL ENGINEERING PHILOSOPHY
DO NOT:
* rewrite networking stacks
* rewrite rendering systems
* perform broad grep/sed repo replacements
* mass-replace strings
* remove large UI systems
* aggressively restructure menus/toolbars
* delete major subsystems
* introduce fragile UI surgery
* create giant monolithic patches
DO:
* preserve upstream architecture wherever possible
* preserve Bambu’s LAN implementation
* preserve AMS/camera functionality
* prefer tiny targeted diffs
* patch exact functions only
* isolate modifications by layer
* prioritize behavioral neutralization over visual cleanup
* maintain clear branch separation

PROJECT LAYERS
LAYER 1 — CORE PRIVACY BEHAVIOR (AUTHORITATIVE)
Branch:
main
Purpose: Stable behavioral privacy neutralization layer.
Responsibilities:
* disable telemetry senders
* disable analytics/reporting
* disable cloud relay initialization
* disable forced firmware update execution
* bypass login enforcement where practical
* preserve LAN-only printer functionality
* preserve AMS/camera functionality
Important: UI may remain mostly unchanged.
Cloud-related buttons/menu items may still exist if removing them increases fragility.
Behavioral neutrality is MORE important than cosmetic cleanup.
HIGH-CONFIDENCE targets:
* telemetry sender functions
* analytics queues
* event submission systems
* firmware update executors
* cloud websocket initialization
* cloud relay startup
* cloud API execution paths
* auth enforcement checks
LOW-CONFIDENCE areas to avoid:
* toolbar restructuring
* menu restructuring
* dialog removal
* tab removal
* broad UI rewrites
* mass string replacement
* deleting large UI systems

LAYER 2 — UI CLEANUP (OPTIONAL)
Branch:
ui-cleanup
Purpose: Optional cosmetic cleanup only.
Goals:
* hide inert cloud-related UI where safe
* reduce visual clutter
* preserve upstream UX consistency
Important:
* cosmetic only
* separable from core privacy layer
* disposable if upstream UI changes break it
* must NEVER compromise LAN functionality
If cosmetic patches conflict with upstream:
* drop cosmetic patches first
* preserve core privacy behavior

LAYER 3 — PERFORMANCE / RESPONSIVENESS (OPTIONAL)
Branch:
performance
Purpose: Isolated responsiveness improvements.
HIGH-CONFIDENCE targets:
* redraw throttling
* async background operations
* debounce expensive UI events
* viewport optimization
* preview refresh optimization
* caching improvements
* lazy loading
* logging verbosity reduction
LOW-CONFIDENCE targets:
* rendering pipeline rewrites
* wxWidgets replacement
* major threading rewrites
* OpenGL backend replacement
* large architectural refactors
Performance work must NEVER compromise:
* privacy layer
* LAN functionality
* AMS/camera support
* upstream survivability

LAYER 4 — EXPERIMENTAL
Branch:
experimental
Purpose: Unsafe testing only.
Allowed:
* risky UI surgery
* architectural experimentation
* subsystem removal testing
NOT production-safe.

PATCHING RULES
REQUIRED
* Keep patches extremely small
* Patch exact functions/subsystems only
* Prefer additive guards over deletions
* Prefer no-op behavior over UI destruction
* Preserve upstream file structure where possible
FORBIDDEN
* giant patch files
* broad automated replacements
* repo-wide sed/grep rewrites
* invasive architectural rewrites
* unnecessary dependency changes

UPDATE WORKFLOW
Preferred workflow:
git checkout main
git pull upstream master
git rebase upstream/master
git apply patches/core/*.patch
Then:
1. rebuild
2. validate privacy behavior
3. validate LAN printing
4. validate AMS/camera
5. validate firmware update neutralization
Only after core validation:
* reapply ui-cleanup patches
* reapply performance patches
If conflicts occur: Priority order:
1. preserve core behavioral privacy layer
2. preserve LAN functionality
3. preserve upstream compatibility
4. preserve cosmetic cleanup last

ENGINEERING PRIORITIES
Highest priority:
LAN reliability
Second:
privacy behavior neutralization
Third:
upstream survivability
Fourth:
minimal maintenance burden
Lowest priority:
cosmetic perfection

SUCCESS CRITERIA
A successful build:
* follows upstream releases cleanly
* preserves LAN-only printing
* preserves AMS/camera
* prevents forced firmware updates
* neutralizes telemetry/reporting/cloud relay behavior
* remains maintainable long-term
* survives upstream merges with minimal conflicts
* keeps patch surface intentionally small
The project goal is NOT: “heavily modified BambuStudio”
The project goal IS: “stable maintainable behavioral privacy fork with minimal divergence from upstream.”
