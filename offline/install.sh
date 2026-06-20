#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    echo "run this installer as root" >&2
    exit 1
fi

PACKAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${BASE_DIR:-/opt}"
PANEL_DIR="${BASE_DIR}/1panel"
OFFLINE_APP_DIR="${PANEL_DIR}/resource/apps/remote"
PANEL_USERNAME="${PANEL_USERNAME:-admin}"
PANEL_PASSWORD="${PANEL_PASSWORD:-$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')}"
PANEL_ENTRANCE="${PANEL_ENTRANCE:-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')}"
PANEL_PORT="${PANEL_PORT:-9999}"
PANEL_VERSION="${PANEL_VERSION:-$(cat "${PACKAGE_DIR}/VERSION")}"

for command in docker systemctl sha256sum; do
    command -v "${command}" >/dev/null 2>&1 || {
        echo "missing required command: ${command}" >&2
        exit 1
    }
done

(cd "${PACKAGE_DIR}" && sha256sum -c SHA256SUMS)

install -m 0755 "${PACKAGE_DIR}/bin/1panel-core" /usr/local/bin/1panel-core
install -m 0755 "${PACKAGE_DIR}/bin/1panel-agent" /usr/local/bin/1panel-agent
mkdir -p "${OFFLINE_APP_DIR}" "${PANEL_DIR}/resource/offline" "${PANEL_DIR}/geo" "${PANEL_DIR}/conf"
cp -R "${PACKAGE_DIR}/catalog/." "${OFFLINE_APP_DIR}/"
cp "${PACKAGE_DIR}/appstore-data.yaml" "${PANEL_DIR}/resource/offline/data.yaml"

cat >"${PANEL_DIR}/conf/app.yaml" <<EOF
base:
  install_dir: ${BASE_DIR}
  mode: dev
  is_demo: false
  is_offline: true
  is_fxplay: false
  is_enterprise: false
  port: ${PANEL_PORT}
  username: ${PANEL_USERNAME}
  password: ${PANEL_PASSWORD}
  version: ${PANEL_VERSION}

conn:
  port: "${PANEL_PORT}"
  bindAddress: 0.0.0.0
  ipv6: Disable
  ssl: Disable
  entrance: ${PANEL_ENTRANCE}

log:
  level: info
  time_zone: Asia/Shanghai
  log_name: 1Panel
  log_suffix: .log
  max_backup: 10
EOF
chmod 0600 "${PANEL_DIR}/conf/app.yaml"

cat >/usr/local/bin/1pctl <<EOF
#!/usr/bin/env bash
BASE_DIR=${BASE_DIR}
LANGUAGE=zh
ORIGINAL_PORT=${PANEL_PORT}
ORIGINAL_VERSION=${PANEL_VERSION}
ORIGINAL_USERNAME=${PANEL_USERNAME}
ORIGINAL_PASSWORD=${PANEL_PASSWORD}
ORIGINAL_ENTRANCE=${PANEL_ENTRANCE}
case "\${1:-}" in
    start) systemctl start 1panel-agent 1panel-core ;;
    stop) systemctl stop 1panel-core 1panel-agent ;;
    restart) systemctl restart 1panel-agent 1panel-core ;;
    status) systemctl status 1panel-agent 1panel-core ;;
    user-info)
        echo "username: ${PANEL_USERNAME}"
        echo "password: ${PANEL_PASSWORD}"
        echo "port: ${PANEL_PORT}"
        echo "entrance: ${PANEL_ENTRANCE}"
        ;;
    *) echo "usage: 1pctl {start|stop|restart|status|user-info}" ;;
esac
EOF
chmod 0755 /usr/local/bin/1pctl

cat >/etc/systemd/system/1panel-agent.service <<EOF
[Unit]
Description=1Panel Agent (Offline)
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=/usr/local/bin/1panel-agent
Restart=always
RestartSec=5
IPAddressDeny=any
IPAddressAllow=localhost
IPAddressAllow=10.0.0.0/8
IPAddressAllow=172.16.0.0/12
IPAddressAllow=192.168.0.0/16
IPAddressAllow=169.254.0.0/16
IPAddressAllow=fc00::/7
IPAddressAllow=fe80::/10

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/1panel-core.service <<EOF
[Unit]
Description=1Panel Core (Offline)
After=1panel-agent.service
Requires=1panel-agent.service

[Service]
Type=simple
ExecStart=/usr/local/bin/1panel-core --language zh
Restart=always
RestartSec=5
IPAddressDeny=any
IPAddressAllow=localhost
IPAddressAllow=10.0.0.0/8
IPAddressAllow=172.16.0.0/12
IPAddressAllow=192.168.0.0/16
IPAddressAllow=169.254.0.0/16
IPAddressAllow=fc00::/7
IPAddressAllow=fe80::/10

[Install]
WantedBy=multi-user.target
EOF

for archive in "${PACKAGE_DIR}"/images/*.tar; do
    [[ -e "${archive}" ]] || continue
    echo "importing $(basename "${archive}")"
    docker image load -i "${archive}"
done

systemctl daemon-reload
systemctl enable --now 1panel-agent 1panel-core

echo "1Panel offline edition installed."
echo "URL: http://<server-ip>:${PANEL_PORT}/${PANEL_ENTRANCE}"
echo "Username: ${PANEL_USERNAME}"
echo "Password: ${PANEL_PASSWORD}"
echo "Run '1pctl status' to inspect services."
