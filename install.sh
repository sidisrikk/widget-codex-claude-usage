#!/usr/bin/env bash
set -e

APPLET_ID="org.kde.plasma.codexusage"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${HOME}/.local/share/plasma/plasmoids/${APPLET_ID}"

echo "=========================================="
echo "Installing/Updating Codex Weekly Usage Widget"
echo "=========================================="
echo "Source: ${SCRIPT_DIR}"

# 1. Ensure fetcher script is executable
chmod +x "${SCRIPT_DIR}/contents/scripts/fetch_usage.py"

# 2. Register/Update with kpackagetool5 or fallback copy
if command -v kpackagetool5 >/dev/null 2>&1; then
    if [ -d "${TARGET_DIR}" ]; then
        echo "Upgrading existing applet..."
        kpackagetool5 --type Plasma/Applet --upgrade "${SCRIPT_DIR}"
    else
        echo "Installing applet..."
        kpackagetool5 --type Plasma/Applet --install "${SCRIPT_DIR}"
    fi
    echo "✓ Successfully registered ${APPLET_ID} with KDE Plasma"
else
    # Fallback to direct directory copy
    echo "kpackagetool5 not found, copying directly to plasmoids directory..."
    mkdir -p "${TARGET_DIR}"
    rm -rf "${TARGET_DIR:?}"/*
    cp -r "${SCRIPT_DIR}/contents" "${TARGET_DIR}/"
    cp "${SCRIPT_DIR}/metadata.json" "${TARGET_DIR}/"
    echo "✓ Copied widget files to ${TARGET_DIR}"
fi

# Clean non-runtime dev files from installed directory and ensure script executable
rm -rf "${TARGET_DIR}/tests" "${TARGET_DIR}/.git" "${TARGET_DIR}/AGENTS.md" \
       "${TARGET_DIR}/install.sh" "${TARGET_DIR}/uninstall.sh" 2>/dev/null || true
chmod +x "${TARGET_DIR}/contents/scripts/fetch_usage.py" 2>/dev/null || true

# 3. Clear QML bytecode cache and reload plasmashell if active
rm -rf "${HOME}/.cache/plasmashell/qmlcache" 2>/dev/null || true

if systemctl --user is-active plasma-plasmashell.service >/dev/null 2>&1; then
    echo "Reloading KDE Plasma Shell..."
    systemctl --user restart plasma-plasmashell.service
    echo "✓ Plasma Shell reloaded"
fi

echo ""
echo "=========================================="
echo "Installation complete! The widget is now ready."
echo "=========================================="
echo "How to use:"
echo "1. Instant test in a floating window:"
echo "   plasmawindowed ${APPLET_ID}"
echo ""
echo "2. Add to your KDE Panel or Desktop:"
echo "   - Right-click panel or desktop -> 'Add Widgets...'"
echo "   - Search for 'Codex Weekly Usage' and drag it onto your panel or desktop."
echo "=========================================="
