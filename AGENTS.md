# PROJECT KNOWLEDGE BASE

**Generated:** 2026-10-28
**Commit:** b9c2361
**Branch:** main

## OVERVIEW

KDE Plasma 5.27 applet `org.kde.plasma.codexusage` (displayed as "Codex & Claude Usage") shows Codex/ChatGPT weekly quota and reset credits alongside Claude session and weekly limits. The two providers are independent. Python 3 fetches strict JSON; QtQuick 2.15 and Plasma/Kirigami QML own presentation and completion-based polling.

## STRUCTURE

```text
widget-codex-usage/
├── contents/
│   ├── scripts/                # One-shot backends; no persistent daemon
│   │   ├── fetch_usage.py        # Codex quota + reset credits
│   │   ├── fetch_claude_usage.py # Claude session/weekly windows (read-only Claude Code token)
│   │   └── usage_common.py       # Shared HTTP, retry-after, atomic cache write, failure classification
│   ├── ui/                     # Per-provider controller, sections and two representations
│   ├── config/                 # KConfig schema and category registration
│   └── icons/                  # codex.png, claude.svg applet-local images
├── tests/
│   ├── test_fetch_usage.py     # Mocked Codex backend boundary tests
│   ├── test_fetch_claude_usage.py # Mocked Claude backend boundary tests
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
| Codex auth, HTTP, cache, payload | `contents/scripts/fetch_usage.py` | Stdlib only; quota required, credit request optional; validates 0..100% ranges and positive durations; delegates atomic write and format to usage_common.py |
| Claude auth, HTTP, cache, windows | `contents/scripts/fetch_claude_usage.py` | Reads `~/.claude/.credentials.json` only; expired token → `auth_expired` without request; validates 0..100% and strict boolean `has_data` |
| Shared fetch helpers | `contents/scripts/usage_common.py` | `run()` classifies failures (401 → `auth_expired`, 403 → `auth_error`) and prints one JSON object; `write_json_atomic()` fsyncs and replaces caches; integer `format_relative_time()` |
| State, retries, response validation | `contents/ui/UsageController.qml` | One instance per provider; owns executable source, `shellQuote` (URL-decoded, apostrophe-safe), deadlines, snapshot age, `colorFor` |
| Provider wiring, tooltip, refresh action | `contents/ui/main.qml` | Exposes `root.codex`, `root.claude`, `root.providers` |
| Panel gauges and percentages | `contents/ui/CompactRepresentation.qml`, `contents/ui/UsageRing.qml` | One ring per provider; horizontal/vertical layouts; hides unavailable quota |
| Popup layout | `contents/ui/FullRepresentation.qml` | Stacks `CodexSection` and `ClaudeSection` |
| Section header, status, refresh buttons | `contents/ui/SectionHeader.qml` | Fixed height; logo + ⟳ refresh only this provider; `objectName`s prefixed `codex`/`claude` |
| Codex quota/time card and resets | `contents/ui/CodexSection.qml` | All resets visible |
| Claude quota/time pairs | `contents/ui/ClaudeSection.qml` | One pair per window with its reset countdown; placeholder Session/Weekly pairs without data |
| Settings | `contents/ui/configGeneral.qml`, `contents/config/main.xml` | Keep `cfg_*` aliases and schema names aligned |
| Settings category | `contents/config/config.qml` | Registers `configGeneral.qml` as General |
| Plugin entry and packaging | `metadata.json`, `install.sh` | `X-Plasma-MainScript` is `ui/main.qml` |
| Fast regressions | `tests/test_fetch_usage.py`, `tests/test_fetch_claude_usage.py`, `tests/test_scheduler.js` | Mocked HTTP/time, fsync/atomic replace, strict validation and production-function VM |
| Native runtime regressions | `tests/native/check.sh`, `tests/native/tst_smoke.qml` | Real Qt5/KF5 modules; disposable production copy |
| Native dependencies and shell fixture | `tests/native/Dockerfile`, `tests/native/runner.cpp` | Executable data engine needs `plasma-workspace` |
| Qt5 tool/runtime validation | `tests/native/preflight.sh`, `tests/native/test-preflight.sh` | Linkage, runtime-major checks and negative probes |
| Development check commands | `README.md` | Mocked checks and separate native Qt5 Docker gate |

## CODE MAP

Python definitions/imports were checked with AST search; JavaScript symbols/references with LSP. Python LSP is not installed; Python and QML semantic centrality is unmeasured.

| Symbol | Type | Location | Refs | Role |
|--------|------|----------|------|------|
| `run` | Function | `contents/scripts/usage_common.py` | Unmeasured | Classifies failures (401, 403, network, TLS) and prints one JSON result |
| `write_json_atomic` | Function | `contents/scripts/usage_common.py` | Unmeasured | Fsyncs temporary file and replaces destination cache atomically |
| `format_relative_time` | Function | `contents/scripts/usage_common.py` | Unmeasured | Formats fractional durations as whole integer seconds |
| `fetch` | Function | `contents/scripts/fetch_usage.py`, `fetch_claude_usage.py` | Unmeasured | Calls `run` with provider-specific loaders/messages |
| `fetch_result` | Function | `contents/scripts/fetch_usage.py` | Unmeasured | Reads credentials and requests live quota |
| `build_snapshot` | Function | `contents/scripts/fetch_usage.py` | Unmeasured | Builds quota, cycle and sorted reset entries; validates 0..100% and durations |
| `valid_cached_snapshot` | Function | `contents/scripts/fetch_usage.py`, `fetch_claude_usage.py` | Unmeasured | Enforces strict boolean `has_data is True` and `0 <= used_percent, left_percent <= 100` |
| `parse_retry_after` | Function | `contents/scripts/usage_common.py` | Unmeasured | Parses seconds or HTTP date for 429 cooldown |
| `build_window` | Function | `contents/scripts/fetch_claude_usage.py` | Unmeasured | Maps one Claude limit window to a quota/time pair |
| `shellQuote` | Function | `contents/ui/UsageController.qml` | Unmeasured | URL-decodes and single-quotes script paths safely including apostrophes |
| `harness` | Function | `tests/test_scheduler.js` | Unmeasured | Runs extracted `UsageController.qml` functions/bindings per provider with fake time |

## CONVENTIONS

- Settings defaults: `refreshInterval=600`, `showPercentageLeft=true`, `warningThreshold=20`; shared by both providers; the form binds strictly through `cfg_<entryName>` aliases.
- Use `PlasmaCore.Units` and `PlasmaCore.Theme` for layout/font/theming changes; wrap QML user-facing text in `i18n`.
- Status colors (`UsageController.colorFor`): red for auth errors (`auth_error`, `auth_expired`, `no_auth`, `no_token`), reached limits or quota at/below configured threshold; offline is orange; remaining quota above threshold through 40% is orange, above 40% green. Claude's top-level `left_percent` is the lowest window.
- Fetcher stdout is one finite JSON object. Diagnostics use stderr; serialization uses `allow_nan=False`.
- Percentage ranges: `used_percent` and `left_percent` must be finite numbers in `0..100` across live snapshots and cache validators.
- Cache writes: always use atomic replacement (`usage_common.write_json_atomic`) via temporary sibling file, explicit `fsync`, and `os.replace`.
- Cache validation: `has_data` must be boolean `True` strictly (`data.get("has_data") is True`), rejecting truthy strings or objects.
- Script paths: `UsageController` resolves script URLs via `Qt.resolvedUrl`, decodes URI encoding (`decodeURIComponent`), and shell-quotes via `shellQuote` to handle spaces and apostrophes safely.
- Relative durations: fractional seconds are truncated to whole integer seconds before formatting as compact countdown strings.
- Unknown reset countdowns use JSON `null`, never Infinity; credit records require string IDs. Legacy cache normalization happens in `load_cache`.

## ANTI-PATTERNS (THIS PROJECT)

- Never leave a source connected after `onNewData`: disconnect before filtering the active usage command, including unrelated launcher completions.
- Never start overlapping fetches or bypass server cooldown. Only request completion creates the next poll/retry deadline.
- Never replace live in-memory quota with same-age/older cached quota on failure. Live success is authoritative even after a backwards clock change.
- Never turn missing quota into a displayed 100% balance; `hasData` gates quota content.
- Never let optional reset-credit failures invalidate an otherwise successful quota request.
- Never refresh, rotate or write Claude Code credentials; Claude Code owns token renewal.
- Never couple providers: one provider's request, backoff or cooldown must not block the other's refresh.
- Never write cache files in place without atomic fsync and replace (`write_json_atomic`).
- Never evaluate cache `has_data` with loose truthiness; enforce `has_data is True`.
- Never accept unconstrained percentages outside 0..100 in quota payloads or cache validation.
- Never map HTTP 403 to generic error: 403 is `auth_error` requiring re-login.
- Never pass raw, unquoted, or URL-escaped script paths to `executableSource`.
- Never make popup geometry depend on fetch status: retain the fixed-height header statuses. The reset list and Claude pairs fit without scrolling; Claude placeholders reserve the two-window size.
- Native checks must not mount host credentials/cache or alter production QML; only the backends in the disposable copy are replaced.
- Keep `contents/scripts/fetch_usage.py`, `contents/scripts/fetch_claude_usage.py` and `install.sh` executable.

## UNIQUE STYLES

- `main.qml` exposes the shared `root` context (`root.codex`, `root.claude`) consumed by both representation components; each `UsageController` runs its own completion-based schedule.
- Polling is single-shot and completion-based: retry waits are 15/30/60/120/300/600 seconds, capped at 600; ordinary polling has a 60-second minimum.
- Server `Retry-After` sets a minimum deadline; manual refresh can override ordinary backoff but not an active request or cooldown.
- Deadlines are QML `real` milliseconds; timer intervals wake in signed-int-sized chunks without truncating the deadline.
- Payload distinguishes `attempted_at` from successful `updated_at`, and failure metadata from retained snapshot fields.
- Each popup section header is `[icon] <Provider> Usage … status [⟳]`; the logo and ⟳ are keyboard-accessible manual-refresh buttons for that provider only, disabled during its requests and server cooldown. Status is a right-aligned, elided header summary; hover or keyboard-focus it for full saved-quota date/time, error and cooldown details.
- Native layout assertions synchronize with window/frame signals rather than fixed sleeps; production QML remains byte-identical in the disposable fixture.

## COMMANDS

Run from the repository root:

```bash
python3 -m unittest discover -s tests -v
node tests/test_scheduler.js
python3 -m py_compile contents/scripts/*.py
bash tests/native/run.sh
./install.sh
plasmawindowed org.kde.plasma.codexusage
```

## NOTES

- Native checks require an accessible Docker daemon; image build uses network, execution uses no network, read-only filesystems and disposable HOME/XDG paths. `QT_NATIVE_IMAGE` overrides the image tag.
- Native preflight executes Qt5 tools and checks linkage/runtime major before syntax lint and smoke; missing, broken or Qt6 tools fail with image-rebuild guidance.
- Native smoke replaces only the shell-owned Plasmoid attached object; Qt Quick/Test, layouts, Canvas, controls, DataSource and Kirigami are installed implementations. It is offscreen smoke, not visual acceptance or live-shell integration.
- Codex auth comes from `~/.codex/auth.json`; successful snapshots go to `~/.cache/codex_usage.json`. Claude auth comes from `~/.claude/.credentials.json` (`claudeAiOauth`); snapshots go to `~/.cache/claude_usage.json`. Direct backend execution uses real credentials/API and can update those caches.
- Claude usage endpoint `GET https://api.anthropic.com/api/oauth/usage` (header `anthropic-beta: oauth-2025-04-20`) is undocumented; `five_hour`, `seven_day`, `seven_day_sonnet`, `seven_day_opus` carry `utilization` and `resets_at`; other keys are ignored.
- Installer uses `kpackagetool5` when available, otherwise copies into the user plasmoid directory; it clears `~/.cache/plasmashell/qmlcache` and restarts `plasma-plasmashell.service` only when active.
- Reopening without clearing compiled QML cache/restarting the shell can show stale edits; `install.sh` performs that refresh.
- All tracked-content directories including root were analyzed at depth at most 3. Child scores stayed below 8, so this file covers the repository without redundant nested guidance.
