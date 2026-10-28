# Codex & Claude Usage - KDE Plasma Widget (Ubuntu 24.04 LTS)

A native KDE Plasma 5.27 widget that shows two providers side by side:

- **Codex / ChatGPT**: weekly usage percentage remaining, countdown until reset, subscription tier and available reset credits.
- **Claude**: the 5-hour session limit and weekly limit from your Claude Code login, plus the per-model weekly limits (Sonnet, Opus) when your plan has them.

<p align="center">
  <img src="contents/icons/codex.png" alt="Codex Usage Icon" width="96" height="96" />
</p>

## Features

- **Weekly % Remaining**: Automatically tracks your Codex 7-day rolling quota (e.g. `56% left`).
- **Claude limits**: One Quota/Time pair per Claude limit window (Session 5h, Weekly, and per-model weekly limits when present). Each pair's header shows its own reset countdown (e.g. `resets 3h 12m`); hover it for the local reset date.
- **Reset Countdown**: Shows humanized remaining time (e.g. `6d 11h 47m`) and local reset timestamp (`Sun, 11 Oct 12:34`).
- **Dynamic Color Indicator**:
  - 🟢 **Green**: More than 40% remaining and above the warning threshold.
  - 🟠 **Orange**: Above the warning threshold and at most 40% remaining, or offline.
  - 🔴 **Red**: At or below the warning threshold (20% by default), a reached limit, or an authentication error.
- **Dual Representation**:
  - **Panel / Taskbar**: Two rings side by side, Codex and Claude, each with its own percentage badge and status color. On vertical panels they are stacked. The Codex ring shows its weekly quota; the Claude ring shows its lowest remaining window. The percentage can show remaining or used quota. Hover for a tooltip covering both providers when a status needs attention.
  - **Desktop / Popup**: A Codex section (`[icon] Codex Usage`, quota/time card, reset list) above a Claude section (`[icon] Claude Usage`, one quota/time pair per window). Each section header has its own ⟳ refresh button, and its logo can also be clicked or focused and activated with Space. Each one refreshes only its own provider. Status stays right-aligned in each fixed-height header through loading, failures, and recovery.
- **Low Footprint**: Driven directly by Plasma's event engine and Python 3 without running background Node or Electron daemons.
- **Offline & Cache Tolerant**: Saves snapshots to `~/.cache/codex_usage.json` and `~/.cache/claude_usage.json` for instant cold starts.
- **Independent providers**: Each provider has its own request, retry backoff and server cooldown, so a Claude outage never blocks Codex refreshes and vice versa.
- **All resets visible**: Quota and time stay in place with “—” and empty gauges until data arrives. The popup grows to show every reset without scrolling; long labels and status summaries are elided instead of expanding the width.
- **Transparent retries**: The header identifies retained quota as saved and shows a short status or retry countdown. Hover or keyboard-focus the header status for the full saved date/time, error, and cooldown explanation. Server cooldowns disable manual refresh; ordinary retry backoff can be overridden manually.
- **Progressive recovery**: Temporary failures wait 15, 30, 60, 120, 300, then 600 seconds between attempts, measured from completion. HTTP 429 cooldowns are a minimum wait. Successful quota resets the schedule; credential and permanent failures retain normal polling.

---

## Requirements

- **OS**: Ubuntu 24.04 LTS with KDE Plasma 5.27+
- **Python**: Python 3.8+ (uses standard library only)
- **Codex / ChatGPT**: Authenticated session in `~/.codex/auth.json` (created automatically by `codex login` or the ChatGPT desktop app).
- **Claude**: A Claude Code login (`claude` → `/login`) with a Pro/Max subscription, stored in `~/.claude/.credentials.json`. The widget only reads this file. It never refreshes or rewrites tokens. Claude Code renews its access token while it runs. If the token has expired, the Claude section shows *Sign-in required* and keeps your last saved numbers until Claude Code refreshes the token. Usage comes from `https://api.anthropic.com/api/oauth/usage`, the same undocumented endpoint Claude Code's `/usage` uses, so it may change without notice.

---

## Installation

1. In the repository directory, run:
```bash
./install.sh
```

This installs the widget into `~/.local/share/plasma/plasmoids/org.kde.plasma.codexusage` and registers it with KDE Plasma.

---

## How to Use

### Quick Preview
To test the widget right away in a floating test window:
```bash
plasmawindowed org.kde.plasma.codexusage
```

### Add to KDE Panel (Taskbar)
1. Right-click an empty area on your KDE Panel.
2. Select **Add Widgets...** (or press <kbd>Ctrl</kbd> + <kbd>F12</kbd>).
3. Search for **Codex & Claude Usage**.
4. Drag and drop it onto your panel.

### Add to Desktop
1. Right-click on your desktop wallpaper.
2. Select **Add Widgets...**.
3. Drag and drop **Codex & Claude Usage** onto your desktop.

---

## Configuration

Right-click the widget and select **Configure Codex & Claude Usage...** to customize these settings, which apply to both providers:
- **Refresh Interval**: Default 10 minutes (`600s`).
- **Display Style**: Toggle between `% Remaining` and `% Used`.
- **Alert Threshold**: Define low quota warning percentage.

---

## Uninstallation

To remove the widget completely:
```bash
./uninstall.sh
```

Alternatively, you can remove it manually via:
```bash
kpackagetool5 --type Plasma/Applet --remove org.kde.plasma.codexusage
```

---

## Development Checks

These mocked checks need Python 3 and Node.js, but do not access live credentials or the API:

```bash
python3 -m unittest discover -s tests -v
node tests/test_scheduler.js
python3 -m py_compile contents/scripts/*.py
```

The scheduler checks execute production QML functions/bindings, including synthetic backend payloads. They do not replace native Qt/Plasma rendering checks.

### Isolated Native Qt5 Validation (Docker)

To run the isolated native Qt5 and KF5 smoke checks in Docker:

```bash
bash tests/native/run.sh
```

Requires a working Docker daemon accessible to your user; no host Qt installation or sudo is needed. The Ubuntu 24.04 image installs Qt5 tools and KDE Frameworks/Plasma QML modules. Preflight executes `qmake`, `qmllint`, and `qmltestrunner`, verifying tool linkage, QML syntax, and layout bindings.

---

## License

This project is licensed under the [MIT License](LICENSE).
