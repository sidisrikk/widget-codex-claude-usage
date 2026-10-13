#!/bin/bash
set -euo pipefail
export HOME=/tmp/home XDG_CACHE_HOME=/tmp/cache XDG_CONFIG_HOME=/tmp/config XDG_DATA_HOME=/tmp/data XDG_RUNTIME_DIR=/tmp/runtime
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
mkdir -p "$HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
bash /opt/native/test-preflight.sh
bash /opt/native/preflight.sh
while IFS= read -r -d '' qml; do
    echo "qmllint: $qml"
    /usr/lib/qt5/bin/qmllint "$qml"
done < <(find /repo/contents/ui /repo/contents/config -name '*.qml' -print0 | sort -z)
# Byte-identical production QML; substitute only the backend in a disposable copy.
mkdir -p /tmp/fixture
cp -r /repo/contents /tmp/fixture/
cp /opt/native/backend.py /tmp/fixture/contents/scripts/fetch_usage.py
cp /opt/native/tst_smoke.qml /tmp/fixture/tst_smoke.qml
while IFS= read -r -d '' qml; do
    cmp "$qml" "/tmp/fixture/${qml#/repo/}"
done < <(find /repo/contents/ui /repo/contents/config -name '*.qml' -print0)
dbus-run-session -- /opt/native/native-smoke -input /tmp/fixture/tst_smoke.qml
