#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

failed=0

if rg -n \
    "window\\.open\\(['\"]https?://|href=['\"]https?://|href=\"https?://" \
    frontend/src \
    --glob '*.{ts,vue}'; then
    echo "hard-coded public frontend navigation is forbidden" >&2
    failed=1
fi

if rg -n \
    "registry\\.npmjs\\.org|registry\\.npmmirror\\.com|mirrors\\.cloud\\.tencent\\.com|repo\\.packagist\\.org|archive\\.ubuntu\\.com|deb\\.debian\\.org" \
    frontend/src \
    --glob '*.{ts,vue}' \
    --glob '!lang/modules/*.ts'; then
    echo "public package repository defaults are forbidden in the offline frontend" >&2
    failed=1
fi

if rg -n \
    "resource\\.fit2cloud\\.com|resource\\.1panel\\.pro|apps-assets\\.fit2cloud\\.com|apps\\.1panel\\.pro" \
    core/global agent/global; then
    echo "hard-coded upstream repositories are forbidden" >&2
    failed=1
fi

for file in offline/install.sh core/init/router/router.go frontend/src/utils/offline-network.ts; do
    [[ -s "${file}" ]] || {
        echo "missing offline network guard: ${file}" >&2
        failed=1
    }
done

rg -q "IPAddressDeny=any" offline/install.sh || {
    echo "systemd public egress restriction is missing" >&2
    failed=1
}
rg -q "DOCKER-USER" offline/install.sh || {
    echo "container public egress restriction is missing" >&2
    failed=1
}
rg -q "ip6tables" offline/install.sh || {
    echo "IPv6 container public egress restriction is missing" >&2
    failed=1
}
rg -q "Content-Security-Policy" core/init/router/router.go || {
    echo "browser content security policy is missing" >&2
    failed=1
}

exit "${failed}"
