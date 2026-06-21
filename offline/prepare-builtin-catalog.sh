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

case "${ARCH}" in
    amd64)
        MYSQL_VERSIONS=(8.4.6 8.0.43 5.7.44 5.6.51)
        ;;
    arm64)
        MYSQL_VERSIONS=(8.4.6 8.0.43)
        ;;
    *)
        echo "unsupported architecture: ${ARCH}" >&2
        exit 1
        ;;
esac

mkdir -p "${APPS_DIR}/mysql" "${APPS_DIR}/openresty"
cp "${ROOT_DIR}/core/cmd/server/app/logo.png" "${APPS_DIR}/mysql/logo.png"
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
EOF

cat >"${APPS_DIR}/mysql/data.yml" <<EOF
additionalProperties:
  key: mysql
  name: MySQL
  tags:
    - Database
  shortDescZh: 离线 MySQL 数据库
  shortDescEn: Offline MySQL database
  description:
    en: MySQL database installed from a bundled offline image
    zh: 使用离线包内置镜像安装的 MySQL 数据库
    zh-hant: 使用離線包內置映像安裝的 MySQL 資料庫
  type: runtime
  crossVersionUpdate: false
  limit: 0
  recommend: 5
  website: ""
  github: ""
  document: ""
  architectures:
    - ${ARCH}
EOF

cat >"${APPS_DIR}/mysql/README.md" <<'EOF'
# MySQL（离线）

该应用只使用已导入本机的 MySQL 镜像，不会拉取远程镜像。
安装后可在 1Panel 的“已安装应用”中启动、停止、重启、备份和卸载。
EOF

for version in "${MYSQL_VERSIONS[@]}"; do
    version_dir="${APPS_DIR}/mysql/${version}"
    mkdir -p "${version_dir}"
    cat >"${version_dir}/data.yml" <<'EOF'
additionalProperties:
  formFields:
    - default: mysql
      envKey: PANEL_DB_ROOT_PASSWORD
      labelEn: Root Password
      labelZh: Root 密码
      random: true
      required: true
      type: password
      label:
        en: Root Password
        zh: Root 密码
        zh-hant: Root 密碼
    - default: 3306
      envKey: PANEL_APP_PORT_HTTP
      labelEn: Port
      labelZh: 端口
      required: true
      rule: paramPort
      type: number
      label:
        en: Port
        zh: 端口
        zh-hant: 端口
EOF
    cat >"${version_dir}/docker-compose.yml" <<EOF
services:
  mysql:
    image: mysql:${version}
    container_name: \${CONTAINER_NAME}
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: \${PANEL_DB_ROOT_PASSWORD}
    networks:
      - 1panel-network
    ports:
      - \${PANEL_APP_PORT_HTTP}:3306
    volumes:
      - ./data:/var/lib/mysql
      - /etc/localtime:/etc/localtime:ro
    labels:
      createdBy: Apps
networks:
  1panel-network:
    external: true
EOF
done

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

openresty_dir="${APPS_DIR}/openresty/1.27.1.2-2-3-focal"
mkdir -p "${openresty_dir}"
cat >"${openresty_dir}/data.yml" <<'EOF'
additionalProperties:
  supportVersion: 2.0
  formFields:
    - default: 80
      envKey: PANEL_APP_PORT_HTTP
      labelEn: HTTP Port
      labelZh: HTTP 端口
      required: true
      rule: paramPort
      type: number
      label:
        en: HTTP Port
        zh: HTTP 端口
        zh-hant: HTTP 端口
    - default: 443
      envKey: PANEL_APP_PORT_HTTPS
      labelEn: HTTPS Port
      labelZh: HTTPS 端口
      required: true
      rule: paramPort
      type: number
      label:
        en: HTTPS Port
        zh: HTTPS 端口
        zh-hant: HTTPS 端口
    - default: www
      envKey: WEBSITE_DIR
      labelEn: Website Directory
      labelZh: 网站目录
      required: true
      type: text
      label:
        en: Website Directory
        zh: 网站目录
        zh-hant: 網站目錄
EOF
cat >"${openresty_dir}/docker-compose.yml" <<'EOF'
services:
  openresty:
    image: 1panel/openresty:1.27.1.2-2-3-focal
    container_name: ${CONTAINER_NAME}
    restart: always
    ports:
      - ${PANEL_APP_PORT_HTTP}:80
      - ${PANEL_APP_PORT_HTTPS}:443
    networks:
      - 1panel-network
    volumes:
      - ./html:/usr/local/openresty/nginx/html
      - ./log:/usr/local/openresty/nginx/logs
      - ${WEBSITE_DIR}:/www
      - /etc/localtime:/etc/localtime:ro
    labels:
      createdBy: Apps
networks:
  1panel-network:
    external: true
EOF
