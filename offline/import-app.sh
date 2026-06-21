#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    echo "run this command as root" >&2
    exit 1
fi

if [[ "$#" -ne 1 ]]; then
    echo "usage: 1panel-import-app <bundle-directory>" >&2
    exit 1
fi

BUNDLE_DIR="$(cd "$1" && pwd)"
BASE_DIR="${BASE_DIR:-/opt}"
PANEL_DIR="${BASE_DIR}/1panel"
APP_DIR="${PANEL_DIR}/resource/apps/remote"
OFFLINE_DIR="${PANEL_DIR}/resource/offline"

if [[ ! -d "${BUNDLE_DIR}/apps" ]]; then
    echo "missing apps directory: ${BUNDLE_DIR}/apps" >&2
    exit 1
fi
if find "${BUNDLE_DIR}/apps" -type l -print -quit | grep -q .; then
    echo "symbolic links are not allowed in an application bundle" >&2
    exit 1
fi

mkdir -p "${APP_DIR}" "${OFFLINE_DIR}"
cp -R "${BUNDLE_DIR}/apps/." "${APP_DIR}/"
if [[ -f "${BUNDLE_DIR}/data.yaml" ]]; then
    cp "${BUNDLE_DIR}/data.yaml" "${OFFLINE_DIR}/data.yaml"
fi

if [[ -d "${BUNDLE_DIR}/images" ]]; then
    for archive in "${BUNDLE_DIR}"/images/*.tar; do
        [[ -f "${archive}" ]] || continue
        echo "importing $(basename "${archive}")"
        docker image load -i "${archive}"
    done
fi

systemctl restart 1panel-agent
echo "custom offline applications imported"
