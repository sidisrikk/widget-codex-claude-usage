# Codex Dynamic Multi-Window Quota Support (Plus & Pro)

## Problem Statement
How might we dynamically support both ChatGPT Plus (5h session + 7d weekly) and Pro (7d weekly only) in Codex so users see their true short-term limits without breaking weekly runway, reset credits, or panel gauges?

## Recommended Direction
1. **Duration-Based Window Detection (`fetch_usage.py`):**
   - Inspect both `rate_limit.primary_window` and `rate_limit.secondary_window`.
   - Classify windows dynamically by duration (`limit_window_seconds <= 21600` for 5h session; `>= 86400` for 7d weekly).
   - If a session window exists, expose `has_session: true`, calculate 5h metrics (`session_used_percent`, `session_left_percent`, `session_reset_in`, `session_reset_formatted`), and append a "Session" item to `resets`.
   - Calculate 7-day cycle runway metrics strictly from the weekly window.
   - Set top-level `used_percent` and `left_percent` to the bottleneck window (`min(session_left, weekly_left)`).
2. **Controller Contract (`UsageController.qml`):**
   - Expose properties: `hasSession`, `sessionUsedPercent`, `sessionLeftPercent`, `sessionResetIn`, `sessionResetFormatted`.
   - Update `validCodexSnapshot()` to accept optional session fields safely.
3. **Dual-Card Visual Representation (`CodexSection.qml`):**
   - Render a dedicated "5 Hours Session" card whenever `codex.hasSession` is true.
   - Keep the existing "7 Days Cycle" card and "All Resets" list.
   - Automatically hide the 5-hour card on Pro accounts where only weekly exists.

## Key Assumptions to Validate
- [x] **API Consistency:** Validated against live Plus account. OpenAI returns 5h in `primary_window` (18,000s) and 7d in `secondary_window` (604,800s).
- [x] **Reset Credits Behavior:** ChatGPT reset credits apply to primary/weekly limits and remain valid in the combined `resets` list.
- [x] **Height & Window Expansion:** Dual cards fit cleanly within the Plasma popup without clipping.

## MVP Scope
### Included (In)
- Dynamic duration inspection for `primary_window` and `secondary_window` in `fetch_usage.py`.
- Optional session fields in snapshot schema and cache validation.
- Conditionally rendered 5-Hour Session card in `CodexSection.qml`.
- Bottleneck percentage driving the compact panel ring in `CompactRepresentation.qml`.
- Python unit test fixtures for both Plus (dual-window) and Pro (single-window) in `test_fetch_usage.py`.
- QML scheduler assertions in `test_scheduler.js`.

### Excluded (Not Doing & Why)
- **Do not merge Codex into `WindowsSection.qml`:** Codex contains unique reset credit tokens and cycle runway metrics that generic window cards do not support.
- **Do not split panel into dual rings for Codex:** Panel space is constrained; single bottleneck ring preserves visual consistency with Claude and Antigravity.
- **Do not hardcode `"plus"` vs `"pro"` string checks:** OpenAI frequently alters plan names (Team, Enterprise, Edu). Window duration matching is resilient to plan renames.

## Open Questions
- None.
