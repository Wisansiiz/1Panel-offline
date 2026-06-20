#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="${1:-amd64}"
OUTPUT_DIR="${OUTPUT_DIR:-${ROOT_DIR}/dist/offline}"
CATALOG_DIR="${CATALOG_DIR:-${ROOT_DIR}/offline/catalog}"
APPSTORE_REPO_URL="${APPSTORE_REPO_URL:-https://github.com/1Panel-dev/appstore.git}"
SOURCE_VERSION="$(awk '/^[[:space:]]*version:/ {print $2; exit}' "${ROOT_DIR}/core/cmd/server/conf/app.yaml")"
BUILD_VERSION="${BUILD_VERSION:-${SOURCE_VERSION}}"
SAFE_VERSION="$(printf '%s' "${BUILD_VERSION}" | tr -c 'A-Za-z0-9._-' '-')"
WORK_DIR="${OUTPUT_DIR}/1panel-offline-${SAFE_VERSION}-linux-${ARCH}"
IMAGE_DIR="${WORK_DIR}/images"

case "${ARCH}" in
    amd64|arm64) ;;
    *) echo "unsupported architecture: ${ARCH}" >&2; exit 1 ;;
esac

for command in docker git go npm tar; do
    command -v "${command}" >/dev/null 2>&1 || {
        echo "missing required command: ${command}" >&2
        exit 1
    }
done

if command -v sha256sum >/dev/null 2>&1; then
    checksum() { sha256sum "$1"; }
elif command -v shasum >/dev/null 2>&1; then
    checksum() { shasum -a 256 "$1"; }
else
    echo "missing SHA-256 tool (sha256sum or shasum)" >&2
    exit 1
fi

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}/bin" "${IMAGE_DIR}" "${WORK_DIR}/catalog"

(
    cd "${ROOT_DIR}/frontend"
    npm ci
    npm run build:pro
)

(
    cd "${ROOT_DIR}/core"
    CGO_ENABLED=0 GOOS=linux GOARCH="${ARCH}" go build -trimpath -ldflags "-s -w" \
        -o "${WORK_DIR}/bin/1panel-core" ./cmd/server
)

(
    cd "${ROOT_DIR}/agent"
    CGO_ENABLED=0 GOOS=linux GOARCH="${ARCH}" go build -trimpath -ldflags "-s -w" \
        -o "${WORK_DIR}/bin/1panel-agent" ./cmd/server
)

CATALOG_SOURCE="${CATALOG_DIR}"
CATALOG_DATA="${CATALOG_DIR}/data.yaml"
if [[ -d "${CATALOG_DIR}/apps" ]]; then
    CATALOG_SOURCE="${CATALOG_DIR}/apps"
fi
if ! find "${CATALOG_SOURCE}" -mindepth 1 -maxdepth 1 -type d -print -quit 2>/dev/null | grep -q .; then
    APPSTORE_CHECKOUT="${OUTPUT_DIR}/appstore"
    rm -rf "${APPSTORE_CHECKOUT}"
    git clone --depth 1 "${APPSTORE_REPO_URL}" "${APPSTORE_CHECKOUT}"
    CATALOG_SOURCE="${APPSTORE_CHECKOUT}/apps"
    CATALOG_DATA="${APPSTORE_CHECKOUT}/data.yaml"
fi
cp -R "${CATALOG_SOURCE}/." "${WORK_DIR}/catalog/"
if [[ -f "${CATALOG_DATA}" ]]; then
    cp "${CATALOG_DATA}" "${WORK_DIR}/appstore-data.yaml"
else
    echo "missing appstore data.yaml next to catalog" >&2
    exit 1
fi

while IFS=$'\t' read -r image_arch image; do
    [[ -z "${image_arch}" || "${image_arch}" == \#* || "${image_arch}" != "${ARCH}" ]] && continue
    safe_name="$(printf '%s' "${image}" | tr '/:' '__')"
    echo "packing ${image} for linux/${ARCH}"
    docker pull --platform "linux/${ARCH}" "${image}"
    docker image save -o "${IMAGE_DIR}/${safe_name}.tar" "${image}"
done < "${ROOT_DIR}/offline/images.tsv"

cp "${ROOT_DIR}/offline/install.sh" "${WORK_DIR}/install.sh"
cp "${ROOT_DIR}/offline/images.tsv" "${WORK_DIR}/images.tsv"
cp "${ROOT_DIR}/offline/README.md" "${WORK_DIR}/README.md"
printf '%s\n' "${BUILD_VERSION}" > "${WORK_DIR}/VERSION"
chmod +x "${WORK_DIR}/install.sh"

(
    cd "${WORK_DIR}"
    : > SHA256SUMS
    while IFS= read -r file; do
        checksum "${file}" >> SHA256SUMS
    done < <(find . -type f ! -name SHA256SUMS -print | LC_ALL=C sort)
)

tar -C "${OUTPUT_DIR}" -czf "${WORK_DIR}.tar.gz" "$(basename "${WORK_DIR}")"
echo "created ${WORK_DIR}.tar.gz"
