#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${ROOT_DIR}/offline/app-bundles.tsv"
APPSTORE_REPOSITORY="${APPSTORE_REPOSITORY:-1Panel-dev/appstore}"
APPSTORE_REF="${APPSTORE_REF:-37797c685344fe97ee0819e019ddd744d1846257}"
OUTPUT_DIR="${OUTPUT_DIR:-${ROOT_DIR}/dist/offline-apps}"

if [[ "$#" -ne 2 ]]; then
    echo "usage: build-app-bundle.sh <bundle> <amd64|arm64>" >&2
    exit 1
fi

BUNDLE="$1"
ARCH="$2"
case "${ARCH}" in
    amd64|arm64) ;;
    *) echo "unsupported architecture: ${ARCH}" >&2; exit 1 ;;
esac

row="$(
    awk -F '\t' -v bundle="${BUNDLE}" \
        '$1 == bundle { print $0; exit }' "${CONFIG_FILE}"
)"
if [[ -z "${row}" ]]; then
    echo "unknown application bundle: ${BUNDLE}" >&2
    exit 1
fi
IFS=$'\t' read -r _ APP VERSION IMAGE ARCHITECTURES <<<"${row}"

case ",${ARCHITECTURES}," in
    *",${ARCH},"*) ;;
    *)
        echo "${BUNDLE} ${VERSION} does not support linux/${ARCH}" >&2
        exit 1
        ;;
esac

for command in awk curl docker jq sha256sum tar; do
    command -v "${command}" >/dev/null 2>&1 || {
        echo "missing required command: ${command}" >&2
        exit 1
    }
done

SAFE_VERSION="$(printf '%s' "${VERSION}" | tr -c 'A-Za-z0-9._-' '-')"
BUNDLE_NAME="1panel-app-${BUNDLE}-${SAFE_VERSION}-linux-${ARCH}"
WORK_DIR="${OUTPUT_DIR}/${BUNDLE_NAME}"
SOURCE_DIR="$(mktemp -d)"
trap 'rm -rf "${SOURCE_DIR}"' EXIT

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}/apps/${APP}" "${WORK_DIR}/images"

github_api() {
    local url="$1"
    local headers=(-H "Accept: application/vnd.github+json")
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        headers+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    fi
    curl --fail --silent --show-error --location \
        --retry 3 --retry-delay 2 --retry-all-errors \
        "${headers[@]}" "${url}"
}

download_file() {
    local remote_path="$1"
    local destination="$2"
    local required="${3:-1}"
    local url="https://raw.githubusercontent.com/${APPSTORE_REPOSITORY}/${APPSTORE_REF}/${remote_path}"
    mkdir -p "$(dirname "${destination}")"
    if ! curl --fail --silent --show-error --location \
        --retry 3 --retry-delay 2 --retry-all-errors \
        --output "${destination}" "${url}"; then
        rm -f "${destination}"
        if [[ "${required}" == "1" ]]; then
            echo "official app definition is missing ${remote_path}" >&2
            exit 1
        fi
    fi
}

download_directory() {
    local remote_path="$1"
    local destination="$2"
    local encoded_path="${remote_path// /%20}"
    local listing
    listing="$(
        github_api \
            "https://api.github.com/repos/${APPSTORE_REPOSITORY}/contents/${encoded_path}?ref=${APPSTORE_REF}"
    )"
    while IFS=$'\t' read -r item_type item_name item_path; do
        if [[ "${item_type}" == "dir" ]]; then
            download_directory "${item_path}" "${destination}/${item_name}"
        elif [[ "${item_type}" == "file" ]]; then
            download_file "${item_path}" "${destination}/${item_name}"
        fi
    done < <(jq -r '.[] | [.type, .name, .path] | @tsv' <<<"${listing}")
}

APP_SOURCE="${SOURCE_DIR}/apps/${APP}"
VERSION_SOURCE="${APP_SOURCE}/${VERSION}"
download_file "apps/${APP}/data.yml" "${APP_SOURCE}/data.yml"
download_file "apps/${APP}/logo.png" "${APP_SOURCE}/logo.png"
download_file "apps/${APP}/README.md" "${APP_SOURCE}/README.md"
download_file "apps/${APP}/README_en.md" "${APP_SOURCE}/README_en.md" 0
download_directory "apps/${APP}/${VERSION}" "${VERSION_SOURCE}"

cp "${APP_SOURCE}/data.yml" "${APP_SOURCE}/logo.png" "${APP_SOURCE}/README.md" \
    "${WORK_DIR}/apps/${APP}/"
if [[ -f "${APP_SOURCE}/README_en.md" ]]; then
    cp "${APP_SOURCE}/README_en.md" "${WORK_DIR}/apps/${APP}/"
fi
cp -R "${VERSION_SOURCE}" "${WORK_DIR}/apps/${APP}/"

compose_image="$(
    awk '$1 == "image:" { print $2; exit }' \
        "${WORK_DIR}/apps/${APP}/${VERSION}/docker-compose.yml"
)"
compose_image="${compose_image//\$\{JAVA_VERSION\}/${VERSION}}"
if [[ "${compose_image}" != "${IMAGE}" ]]; then
    echo "configured image ${IMAGE} does not match official compose image ${compose_image}" >&2
    exit 1
fi

echo "pulling ${IMAGE} for linux/${ARCH}"
docker pull --platform "linux/${ARCH}" "${IMAGE}"
docker image save -o "${WORK_DIR}/images/${BUNDLE}-${SAFE_VERSION}-${ARCH}.tar" "${IMAGE}"

cat >"${WORK_DIR}/data.yaml" <<'EOF'
additionalProperties:
  version: offline
  tags:
    - key: Database
      name: Database
      sort: 1
      locales:
        en: Database
        zh: 数据库
        zh-hant: 資料庫
    - key: Server
      name: Server
      sort: 2
      locales:
        en: Web Server
        zh: Web 服务器
        zh-hant: Web 伺服器
    - key: Runtime
      name: Runtime
      sort: 3
      locales:
        en: Runtime
        zh: 运行环境
        zh-hant: 執行環境
EOF

cat >"${WORK_DIR}/MANIFEST" <<EOF
bundle=${BUNDLE}
app=${APP}
version=${VERSION}
image=${IMAGE}
architecture=${ARCH}
appstore_repository=${APPSTORE_REPOSITORY}
appstore_ref=${APPSTORE_REF}
EOF

(
    cd "${WORK_DIR}"
    find . -type f ! -name SHA256SUMS -print0 \
        | LC_ALL=C sort -z \
        | xargs -0 sha256sum >SHA256SUMS
)

tar -C "${OUTPUT_DIR}" -czf "${WORK_DIR}.tar.gz" "${BUNDLE_NAME}"
echo "created ${WORK_DIR}.tar.gz"
