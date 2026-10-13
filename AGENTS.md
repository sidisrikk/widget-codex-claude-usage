# PROJECT KNOWLEDGE BASE

**Generated:** 2026-10-13
**Commit:** 80f5ebe
**Branch:** main

## OVERVIEW

KDE Plasma 5.27 applet `org.kde.plasma.codexusage` displays Codex/ChatGPT weekly quota and reset credits. Python 3 fetches strict JSON; QtQuick 2.15 and Plasma/Kirigami QML own presentation and completion-based polling.

## STRUCTURE

```text
widget-codex-usage/
├── contents/
│   ├── scripts/fetch_usage.py   # One-shot backend; no persistent daemon
│   ├── ui/                     # Shared controller and two representations
│   ├── config/                 # KConfig schema and category registration
│   └── icons/codex.png          # Applet-local image
├── tests/
│   ├── test_fetch_usage.py     # Mocked backend boundary tests
│   ├── test_scheduler.js       # Executes production QML JavaScript in Node
│   └── native/                 # Docker-backed Qt5/KF5 smoke and syntax lint
├── metadata.json              # Plasma plugin identity and main-script pointer
├── install.sh                 # Package install/upgrade and shell reload
├── uninstall.sh               # Applet removal and shell reload
└── LICENSE                    # MIT License
```

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| Auth, HTTP, cache, payload | `contents/scripts/fetch_usage.py` | Stdlib only; quota required, credit request optional |
| State, retries, response validation | `contents/ui/main.qml` | Owns executable source, deadlines, snapshot age |
| Panel gauge and percentage | `contents/ui/CompactRepresentation.qml` | Horizontal/vertical layouts; hides unavailable quota |
| Expanded quota/time card and resets | `contents/ui/FullRepresentation.qml` | Fixed header status, all resets visible, title-icon refresh guard |
| Settings | `contents/ui/configGeneral.qml`, `contents/config/main.xml` | Keep `cfg_*` aliases and schema names aligned |
| Settings category | `contents/config/config.qml` | Registers `configGeneral.qml` as General |
| Plugin entry and packaging | `metadata.json`, `install.sh` | `X-Plasma-MainScript` is `ui/main.qml` |
| Fast regressions | `tests/test_fetch_usage.py`, `tests/test_scheduler.js` | Mocked HTTP/time and production-function VM |
| Native runtime regressions | `tests/native/check.sh`, `tests/native/tst_smoke.qml` | Real Qt5/KF5 modules; disposable production copy |
| Native dependencies and shell fixture | `tests/native/Dockerfile`, `tests/native/runner.cpp` | Executable data engine needs `plasma-workspace` |
| Qt5 tool/runtime validation | `tests/native/preflight.sh`, `tests/native/test-preflight.sh` | Linkage, runtime-major checks and negative probes |
| Development check commands | `README.md` | Mocked checks and separate native Qt5 Docker gate |

## CODE MAP

Python definitions/imports were checked with AST search; JavaScript symbols/references with LSP. Python LSP is not installed; Python and QML semantic centrality is unmeasured.

| Symbol | Type | Location | Refs | Role |
|--------|------|----------|------|------|
| `fetch` | Function | `contents/scripts/fetch_usage.py` | Unmeasured | Classifies failures and prints one JSON result |
| `fetch_result` | Function | `contents/scripts/fetch_usage.py` | Unmeasured | Reads credentials and requests live quota |
| `build_snapshot` | Function | `contents/scripts/fetch_usage.py` | Unmeasured | Builds quota, cycle and sorted reset entries |
| `valid_cached_snapshot` | Function | `contents/scripts/fetch_usage.py` | Unmeasured | Matches frontend snapshot shape |
| `parse_retry_after` | Function | `contents/scripts/fetch_usage.py` | Unmeasured | Parses seconds or HTTP date for 429 cooldown |
| `harness` | Function | `tests/test_scheduler.js` | 13 | Runs extracted production functions/bindings with fake time |

## CONVENTIONS

- Settings defaults: `refreshInterval=600`, `showPercentageLeft=true`, `warningThreshold=20`; the form binds strictly through `cfg_<entryName>` aliases.
- Use `PlasmaCore.Units` and `PlasmaCore.Theme` for layout/font/theming changes; wrap QML user-facing text in `i18n`.
- Status colors: red for auth errors, reached limits or quota at/below configured threshold; offline is orange; remaining quota above threshold through 40% is orange, above 40% green.
- Fetcher stdout is one finite JSON object. Diagnostics use stderr; serialization uses `allow_nan=False`.
- Unknown reset countdowns use JSON `null`, never Infinity; credit records require string IDs. Legacy cache normalization happens in `load_cache`.

## ANTI-PATTERNS (THIS PROJECT)

- Never leave a source connected after `onNewData`: disconnect before filtering the active usage command, including unrelated launcher completions.
- Never start overlapping fetches or bypass server cooldown. Only request completion creates the next poll/retry deadline.
- Never replace live in-memory quota with same-age/older cached quota on failure. Live success is authoritative even after a backwards clock change.
- Never turn missing quota into a displayed 100% balance; `hasData` gates quota content.
- Never let optional reset-credit failures invalidate an otherwise successful quota request.
- Never make popup geometry depend on fetch status: retain the fixed-height header status. The reset list fits every reset without scrolling.
- Native checks must not mount host credentials/cache or alter production QML; only the backend in the disposable copy is replaced.
- Keep `contents/scripts/fetch_usage.py` and `install.sh` executable.

## UNIQUE STYLES

- `main.qml` exposes the shared `root` context consumed by both representation components.
- Polling is single-shot and completion-based: retry waits are 15/30/60/120/300/600 seconds, capped at 600; ordinary polling has a 60-second minimum.
- Server `Retry-After` sets a minimum deadline; manual refresh can override ordinary backoff but not an active request or cooldown.
- Deadlines are QML `real` milliseconds; timer intervals wake in signed-int-sized chunks without truncating the deadline.
- Payload distinguishes `attempted_at` from successful `updated_at`, and failure metadata from retained snapshot fields.
- Popup title is `[icon] Codex Usage`; the Codex icon is a keyboard-accessible manual-refresh button, disabled during requests and server cooldown. Status is a right-aligned, elided header summary; hover or keyboard-focus it for full saved-quota date/time, error and cooldown details.
- Native layout assertions synchronize with window/frame signals rather than fixed sleeps; production QML remains byte-identical in the disposable fixture.

## COMMANDS

Run from the repository root:

```bash
python3 -m unittest discover -s tests -v
node tests/test_scheduler.js
python3 -m py_compile contents/scripts/fetch_usage.py
bash tests/native/run.sh
./install.sh
plasmawindowed org.kde.plasma.codexusage
```

## NOTES

- Native checks require an accessible Docker daemon; image build uses network, execution uses no network, read-only filesystems and disposable HOME/XDG paths. `QT_NATIVE_IMAGE` overrides the image tag.
- Native preflight executes Qt5 tools and checks linkage/runtime major before syntax lint and smoke; missing, broken or Qt6 tools fail with image-rebuild guidance.
- Native smoke replaces only the shell-owned Plasmoid attached object; Qt Quick/Test, layouts, Canvas, controls, DataSource and Kirigami are installed implementations. It is offscreen smoke, not visual acceptance or live-shell integration.
- Auth comes from `~/.codex/auth.json`; successful snapshots go to `~/.cache/codex_usage.json`. Direct backend execution uses real credentials/API and can update that cache.
- Installer uses `kpackagetool5` when available, otherwise copies into the user plasmoid directory; it clears `~/.cache/plasmashell/qmlcache` and restarts `plasma-plasmashell.service` only when active.
- Reopening without clearing compiled QML cache/restarting the shell can show stale edits; `install.sh` performs that refresh.
- All tracked-content directories including root were analyzed at depth at most 3. Child scores stayed below 8, so this file covers the repository without redundant nested guidance.
