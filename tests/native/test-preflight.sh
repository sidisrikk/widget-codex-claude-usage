#!/bin/bash
set -euo pipefail
# Negative probes deliberately replace executables, not PATH discovery. Each
# must be rejected with actionable output before production QML is touched.
preflight=/opt/native/preflight.sh
fake=/tmp/preflight-negative/bin
mkdir -p "$fake"
reset_tools() {
    local tool
    rm -f "$fake"/*
    for tool in qmake qmllint qmltestrunner; do
        ln -s "/usr/lib/qt5/bin/$tool" "$fake/$tool"
    done
}
stub() {
    rm -f "$fake/$1"
    printf '#!/bin/bash\n%s\n' "$2" > "$fake/$1"
    chmod +x "$fake/$1"
}
reject() {
    local output
    if output=$(QT5_BIN="$fake" bash "$preflight" 2>&1); then
        echo "FAIL: preflight accepted $1" >&2
        exit 1
    fi
    [[ $output == *'Qt5 preflight:'* && $output == *'rebuild tests/native/Dockerfile'* ]] || {
        echo "FAIL: no actionable preflight diagnostic for $1: $output" >&2
        exit 1
    }
    echo "PASS: preflight rejected $1"
}
for tool in qmake qmllint qmltestrunner; do
    reset_tools
    rm "$fake/$tool"
    reject "missing $tool"
    reset_tools
    stub "$tool" 'exit 42'
    reject "broken $tool"
done
reset_tools
stub qmake 'echo 6.8.0'
reject 'Qt6 qmake'
reset_tools
stub qmllint 'echo "qmllint 6.8.0"'
reject 'Qt6 qmllint'
reset_tools
stub qmltestrunner 'echo "Config: Using QtTest library 6.8.0, Qt 6.8.0"'
reject 'Qt6 qmltestrunner'
