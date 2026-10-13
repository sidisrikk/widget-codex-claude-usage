#!/bin/bash
set -euo pipefail
fail() { echo "Qt5 preflight: $*; rebuild tests/native/Dockerfile (host wrappers are insufficient)." >&2; exit 1; }
qtbin=${QT5_BIN:-/usr/lib/qt5/bin}
version=$("$qtbin/qmake" -query QT_VERSION) || fail 'qmake failed'
[[ $version == 5.* ]] || fail "expected Qt5, got $version"
lint_version=$("$qtbin/qmllint" --version 2>&1) || fail 'qmllint missing or broken'
# Qt5 qmllint reports its tool version (1.0), not the Qt library version.
for tool in qmllint qmltestrunner; do
    linked=$(ldd "$qtbin/$tool" 2>&1) || fail "$tool has no executable Qt5 linkage"
    [[ $linked == *libQt5Core.so* && $linked != *libQt6* && $linked != *'not found'* ]] \
        || fail "$tool missing/broken/wrong Qt major linkage: $linked"
done
"$qtbin/qmltestrunner" -help >/dev/null 2>&1 || fail 'qmltestrunner missing or broken'
mkdir -p /tmp/preflight
cat > /tmp/preflight/tst_tools.qml <<'QML'
import QtQuick 2.15
import QtTest 1.2
TestCase {
    name: "Qt5Tools"
    function test_execution() { compare(2 + 2, 4) }
}
QML
"$qtbin/qmllint" /tmp/preflight/tst_tools.qml || fail 'qmllint execution failed'
probe=$("$qtbin/qmltestrunner" -input /tmp/preflight 2>&1) || fail "Qt Quick Test execution failed: $probe"
echo "$probe"
[[ $probe == *'Using QtTest library 5.'* && $probe == *', Qt 5.'* ]] || fail 'Qt Quick Test runtime is not Qt5'
echo "Qt5 preflight passed ($version; $lint_version)"
