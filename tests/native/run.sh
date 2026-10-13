#!/bin/bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
image=${QT_NATIVE_IMAGE:-codex-usage-qt5-native}
docker build --tag "$image" "$repo/tests/native"
docker run --rm --network none --read-only --cap-drop ALL \
    --security-opt no-new-privileges --tmpfs /tmp:rw,exec,nosuid,size=256m \
    --mount "type=bind,source=$repo,target=/repo,readonly" "$image"
