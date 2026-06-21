#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="${1:-amd64}"
OUTPUT_DIR="${OUTPUT_DIR:-${ROOT_DIR}/dist/offline}"
CATALOG_DIR="${CATALOG_DIR:-${ROOT_DIR}/offline/catalog}"
DOCKER_VERSION="${DOCKER_VERSION:-29.6.0}"
COMPOSE_VERSION="${COMPOSE_VERSION:-v2.40.3}"
SOURCE_VERSION="$(awk '/^[[:space:]]*version:/ {print $2; exit}' "${ROOT_DIR}/core/cmd/server/conf/app.yaml")"
BUILD_VERSION="${BUILD_VERSION:-${SOURCE_VERSION}}"
SAFE_VERSION="$(printf '%s' "${BUILD_VERSION}" | tr -c 'A-Za-z0-9._-' '-')"
WORK_DIR="${OUTPUT_DIR}/1panel-offline-${SAFE_VERSION}-linux-${ARCH}"
IMAGE_DIR="${WORK_DIR}/images"
RUNTIME_DIR="${WORK_DIR}/runtime"

case "${ARCH}" in
    amd64)
        DOCKER_ARCH="x86_64"
        COMPOSE_ARCH="x86_64"
        DEFAULT_DOCKER_SHA256="4d2f6782406b56eb43a519ad5078a6a79abe4d663328acb69136aceff5e05224"
        DEFAULT_COMPOSE_SHA256="dba9d98e1ba5bfe11d88c99b9bd32fc4a0624a30fafe68eea34d61a3e42fd372"
        ;;
    arm64)
        DOCKER_ARCH="aarch64"
        COMPOSE_ARCH="aarch64"
        DEFAULT_DOCKER_SHA256="17aede86d504841427b92e52d8ebb50d3fa67e5fd6d6a90a4224dfc81cd79ebc"
        DEFAULT_COMPOSE_SHA256="d26373b19e89160546d15407516cc59f453030d9bc5b43ba7faf16f7b4980137"
        ;;
    *) echo "unsupported architecture: ${ARCH}" >&2; exit 1 ;;
esac
DOCKER_SHA256="${DOCKER_SHA256:-${DEFAULT_DOCKER_SHA256}}"
COMPOSE_SHA256="${COMPOSE_SHA256:-${DEFAULT_COMPOSE_SHA256}}"

for command in curl docker go npm tar; do
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

verify_checksum() {
    local file="$1"
    local expected="$2"
    local actual
    actual="$(checksum "${file}" | awk '{print $1}')"
    if [[ "${actual}" != "${expected}" ]]; then
        echo "checksum mismatch for ${file}: expected ${expected}, got ${actual}" >&2
        exit 1
    fi
}

download_verified() {
    local url="$1"
    local destination="$2"
    local expected="$3"
    echo "downloading ${url}"
    curl --fail --location --retry 3 --retry-delay 2 --output "${destination}" "${url}"
    verify_checksum "${destination}" "${expected}"
}

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}/bin" "${IMAGE_DIR}" "${WORK_DIR}/catalog" \
    "${RUNTIME_DIR}/docker" "${RUNTIME_DIR}/cli-plugins"

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

if [[ -d "${CATALOG_DIR}/apps" ]]; then
    cp -R "${CATALOG_DIR}/apps/." "${WORK_DIR}/catalog/"
fi
if [[ -f "${CATALOG_DIR}/data.yaml" ]]; then
    cp "${CATALOG_DIR}/data.yaml" "${WORK_DIR}/appstore-data.yaml"
fi

IMAGES=()
while IFS=$'\t' read -r image_arch image; do
    [[ -z "${image_arch}" || "${image_arch}" == \#* || "${image_arch}" != "${ARCH}" ]] && continue
    IMAGES+=("${image}")
done < "${ROOT_DIR}/offline/images.tsv"

printf '%s\n' "${IMAGES[@]}" > "${IMAGE_DIR}/images.txt"
if [[ "${#IMAGES[@]}" -gt 0 ]]; then
    for image in "${IMAGES[@]}"; do
        echo "packing ${image} for linux/${ARCH}"
        docker pull --platform "linux/${ARCH}" "${image}"
    done
    echo "saving ${#IMAGES[@]} bundled images into one archive"
    docker image save -o "${IMAGE_DIR}/images.tar" "${IMAGES[@]}"
else
    echo "no application images configured for ${ARCH}; building base runtime only"
fi

DOCKER_ARCHIVE="${RUNTIME_DIR}/docker-${DOCKER_VERSION}.tgz"
COMPOSE_BINARY="${RUNTIME_DIR}/cli-plugins/docker-compose"
download_verified \
    "https://download.docker.com/linux/static/stable/${DOCKER_ARCH}/docker-${DOCKER_VERSION}.tgz" \
    "${DOCKER_ARCHIVE}" \
    "${DOCKER_SHA256}"
tar -xzf "${DOCKER_ARCHIVE}" -C "${RUNTIME_DIR}/docker" --strip-components=1
rm -f "${DOCKER_ARCHIVE}"
for binary in containerd containerd-shim-runc-v2 ctr docker docker-init docker-proxy dockerd runc; do
    if [[ ! -x "${RUNTIME_DIR}/docker/${binary}" ]]; then
        echo "Docker static package is missing executable: ${binary}" >&2
        exit 1
    fi
done

download_verified \
    "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-${COMPOSE_ARCH}" \
    "${COMPOSE_BINARY}" \
    "${COMPOSE_SHA256}"
chmod 0755 "${COMPOSE_BINARY}"
if [[ ! -x "${COMPOSE_BINARY}" ]]; then
    echo "Docker Compose plugin is not executable" >&2
    exit 1
fi
cat > "${RUNTIME_DIR}/VERSIONS" <<EOF
Docker Engine ${DOCKER_VERSION}
Docker Compose ${COMPOSE_VERSION}
EOF

cp "${ROOT_DIR}/offline/install.sh" "${WORK_DIR}/install.sh"
cp "${ROOT_DIR}/offline/import-app.sh" "${WORK_DIR}/import-app.sh"
cp "${ROOT_DIR}/offline/images.tsv" "${WORK_DIR}/images.tsv"
cp "${ROOT_DIR}/offline/README.md" "${WORK_DIR}/README.md"
printf '%s\n' "${BUILD_VERSION}" > "${WORK_DIR}/VERSION"
printf '%s\n' "${ARCH}" > "${WORK_DIR}/ARCH"
chmod +x "${WORK_DIR}/install.sh" "${WORK_DIR}/import-app.sh"

(
    cd "${WORK_DIR}"
    : > SHA256SUMS
    while IFS= read -r file; do
        checksum "${file}" >> SHA256SUMS
    done < <(find . -type f ! -name SHA256SUMS -print | LC_ALL=C sort)
)

tar -C "${OUTPUT_DIR}" -czf "${WORK_DIR}.tar.gz" "$(basename "${WORK_DIR}")"
echo "created ${WORK_DIR}.tar.gz"
du -h "${RUNTIME_DIR}/docker" "${COMPOSE_BINARY}" "${WORK_DIR}.tar.gz"
