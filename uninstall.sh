#!/usr/bin/env bash
set -e

APPLET_ID="org.kde.plasma.codexusage"
TARGET_DIR="${HOME}/.local/share/plasma/plasmoids/${APPLET_ID}"

echo "=========================================="
echo "Uninstalling Codex Weekly Usage Widget"
echo "=========================================="

if command -v kpackagetool5 >/dev/null 2>&1; then
    kpackagetool5 --type Plasma/Applet --remove "${APPLET_ID}" 2>/dev/null || true
fi

rm -rf "${TARGET_DIR}"
rm -rf "${HOME}/.cache/plasmashell/qmlcache" 2>/dev/null || true

if systemctl --user is-active plasma-plasmashell.service >/dev/null 2>&1; then
    echo "Reloading KDE Plasma Shell..."
    systemctl --user restart plasma-plasmashell.service
    echo "✓ Plasma Shell reloaded"
fi

echo "✓ Successfully uninstalled ${APPLET_ID}"
