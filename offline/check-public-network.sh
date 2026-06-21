#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

failed=0

if grep -RInE \
    --include='*.ts' \
    --include='*.vue' \
    "window\\.open\\(['\"]https?://|href=['\"]https?://|href=\"https?://" \
    frontend/src; then
    echo "hard-coded public frontend navigation is forbidden" >&2
    failed=1
fi

if find frontend/src \
    -path frontend/src/lang/modules -prune -o \
    -type f \( -name '*.ts' -o -name '*.vue' \) \
    -exec grep -nHE \
    "registry\\.npmjs\\.org|registry\\.npmmirror\\.com|mirrors\\.cloud\\.tencent\\.com|repo\\.packagist\\.org|archive\\.ubuntu\\.com|deb\\.debian\\.org" \
    {} +; then
    echo "public package repository defaults are forbidden in the offline frontend" >&2
    failed=1
fi

if grep -RInE \
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

grep -q "IPAddressDeny=any" offline/install.sh || {
    echo "systemd public egress restriction is missing" >&2
    failed=1
}
grep -q "DOCKER-USER" offline/install.sh || {
    echo "container public egress restriction is missing" >&2
    failed=1
}
grep -q "ip6tables" offline/install.sh || {
    echo "IPv6 container public egress restriction is missing" >&2
    failed=1
}
grep -q "Content-Security-Policy" core/init/router/router.go || {
    echo "browser content security policy is missing" >&2
    failed=1
}

exit "${failed}"
