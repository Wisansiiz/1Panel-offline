#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "$#" -ne 3 ]]; then
    echo "usage: prepare-builtin-catalog.sh <arch> <apps-directory> <data-yaml>" >&2
    exit 1
fi

ARCH="$1"
APPS_DIR="$2"
DATA_YAML="$3"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPSTORE_REPOSITORY="${APPSTORE_REPOSITORY:-1Panel-dev/appstore}"
OPENRESTY_APPSTORE_REF="${OPENRESTY_APPSTORE_REF:-e955e97acbf552ffcdc35f9e14f987bc46471ae0}"
OPENRESTY_VERSION="1.27.1.2-2-3-focal"

for command in curl jq; do
    command -v "${command}" >/dev/null 2>&1 || {
        echo "missing required command: ${command}" >&2
        exit 1
    }
done

case "${ARCH}" in
    amd64|arm64) ;;
    *)
        echo "unsupported architecture: ${ARCH}" >&2
        exit 1
        ;;
esac

mkdir -p "${APPS_DIR}/openresty"
cp "${ROOT_DIR}/core/cmd/server/app/logo.png" "${APPS_DIR}/openresty/logo.png"

cat >"${DATA_YAML}" <<'EOF'
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

cat >"${APPS_DIR}/openresty/data.yml" <<EOF
additionalProperties:
  key: openresty
  name: OpenResty
  tags:
    - Server
  shortDescZh: 离线 OpenResty Web 服务器
  shortDescEn: Offline OpenResty web server
  description:
    en: OpenResty installed from a bundled offline image
    zh: 使用离线包内置镜像安装的 OpenResty Web 服务器
    zh-hant: 使用離線包內置映像安裝的 OpenResty Web 伺服器
  type: runtime
  crossVersionUpdate: false
  limit: 1
  recommend: 1
  website: ""
  github: ""
  document: ""
  architectures:
    - ${ARCH}
EOF

cat >"${APPS_DIR}/openresty/README.md" <<'EOF'
# OpenResty（离线）

该应用只使用离线包内置的 OpenResty 镜像，不会在线构建或拉取镜像。
安装后可在 1Panel 的“已安装应用”中统一管理。
EOF

openresty_dir="${APPS_DIR}/openresty/${OPENRESTY_VERSION}"
mkdir -p "${openresty_dir}"

tree_json="$(mktemp)"
trap 'rm -f "${tree_json}"' EXIT
github_headers=(-H "Accept: application/vnd.github+json")
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    github_headers+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi
curl --fail --silent --show-error --location \
    --retry 3 --retry-delay 2 --retry-all-errors \
    "${github_headers[@]}" \
    "https://api.github.com/repos/${APPSTORE_REPOSITORY}/git/trees/${OPENRESTY_APPSTORE_REF}?recursive=1" \
    -o "${tree_json}"

version_prefix="apps/openresty/${OPENRESTY_VERSION}/"
download_openresty_file() {
    local remote_path="$1"
    local relative_path destination
    relative_path="${remote_path#${version_prefix}}"
    destination="${openresty_dir}/${relative_path}"
    mkdir -p "$(dirname "${destination}")"
    curl --fail --silent --show-error --location \
        --retry 3 --retry-delay 2 --retry-all-errors \
        "https://raw.githubusercontent.com/${APPSTORE_REPOSITORY}/${OPENRESTY_APPSTORE_REF}/${remote_path}" \
        -o "${destination}"
}
export -f download_openresty_file
export APPSTORE_REPOSITORY OPENRESTY_APPSTORE_REF openresty_dir version_prefix

jq -r --arg prefix "${version_prefix}" '
    .tree[]
    | select(.type == "blob")
    | select(.path | startswith($prefix))
    | select((.path | startswith($prefix + "build/")) | not)
    | .path
' "${tree_json}" | xargs -P 12 -n 1 bash -c 'download_openresty_file "$1"' _

cat >"${openresty_dir}/docker-compose.yml" <<'EOF'
services:
  openresty:
    image: 1panel/openresty:1.27.1.2-2-3-focal
    container_name: ${CONTAINER_NAME}
    restart: always
    network_mode: host
    volumes:
      - ./conf/nginx.conf:/usr/local/openresty/nginx/conf/nginx.conf
      - ./conf/fastcgi_params:/usr/local/openresty/nginx/conf/fastcgi_params
      - ./conf/fastcgi-php.conf:/usr/local/openresty/nginx/conf/fastcgi-php.conf
      - ./conf/mime.types:/usr/local/openresty/nginx/conf/mime.types
      - ./conf/default:/usr/local/openresty/nginx/conf/default/
      - ./conf/ssl:/usr/local/openresty/nginx/conf/ssl/
      - ./log:/var/log/nginx
      - ./root:/usr/share/nginx/html
      - /etc/localtime:/etc/localtime
      - ./1pwaf/data:/usr/local/openresty/1pwaf/data
      - ${WEBSITE_DIR}:/www
      - ${WEBSITE_DIR}/conf.d:/usr/local/openresty/nginx/conf/conf.d/
    labels:
      createdBy: Apps
EOF
