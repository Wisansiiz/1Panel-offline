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

for command in install sha256sum systemctl uname; do
    command -v "${command}" >/dev/null 2>&1 || {
        echo "missing required command: ${command}" >&2
        exit 1
    }
done

(cd "${PACKAGE_DIR}" && sha256sum -c SHA256SUMS)

EXPECTED_ARCH="$(cat "${PACKAGE_DIR}/ARCH")"
case "$(uname -m)" in
    x86_64) HOST_ARCH="amd64" ;;
    aarch64|arm64) HOST_ARCH="arm64" ;;
    *) echo "unsupported host architecture: $(uname -m)" >&2; exit 1 ;;
esac
if [[ "${HOST_ARCH}" != "${EXPECTED_ARCH}" ]]; then
    echo "package architecture ${EXPECTED_ARCH} does not match host ${HOST_ARCH}" >&2
    exit 1
fi

install_compose_plugin() {
    install -d -m 0755 /usr/local/lib/docker/cli-plugins
    install -m 0755 "${PACKAGE_DIR}/runtime/cli-plugins/docker-compose" \
        /usr/local/lib/docker/cli-plugins/docker-compose
}

install_docker_engine() {
    if ! command -v iptables >/dev/null 2>&1; then
        echo "iptables is required by Docker but is not installed on this host" >&2
        echo "install the operating system's iptables compatibility package before continuing" >&2
        exit 1
    fi

    for binary in "${PACKAGE_DIR}"/runtime/docker/*; do
        [[ -f "${binary}" ]] || continue
        install -m 0755 "${binary}" "/usr/local/bin/$(basename "${binary}")"
    done
    install_compose_plugin
    install -d -m 0755 /etc/docker /var/lib/docker /var/lib/containerd

    cat >/etc/systemd/system/containerd.service <<'EOF'
[Unit]
Description=containerd container runtime
After=network.target local-fs.target

[Service]
ExecStart=/usr/local/bin/containerd
Delegate=yes
KillMode=process
Restart=always
RestartSec=5
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity

[Install]
WantedBy=multi-user.target
EOF

    cat >/etc/systemd/system/docker.service <<'EOF'
[Unit]
Description=Docker Application Container Engine
After=network-online.target containerd.service
Wants=network-online.target
Requires=containerd.service

[Service]
Type=simple
ExecStart=/usr/local/bin/dockerd --host=unix:///var/run/docker.sock --containerd=/run/containerd/containerd.sock
ExecReload=/bin/kill -s HUP $MAINPID
Restart=always
RestartSec=5
TimeoutStartSec=0
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
Delegate=yes
KillMode=process
OOMScoreAdjust=-500

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now containerd.service docker.service
}

wait_for_docker() {
    local attempt
    for ((attempt = 1; attempt <= 30; attempt++)); do
        if docker info >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    systemctl --no-pager --full status docker.service || true
    echo "Docker daemon did not become ready" >&2
    exit 1
}

if [[ "${FORCE_BUNDLED_DOCKER:-0}" != "1" ]] \
    && command -v docker >/dev/null 2>&1 \
    && command -v dockerd >/dev/null 2>&1 \
    && systemctl cat docker.service >/dev/null 2>&1; then
    echo "using existing Docker installation"
    systemctl enable --now docker.service
    if ! docker compose version >/dev/null 2>&1; then
        echo "Docker Compose plugin is missing; installing bundled plugin"
        install_compose_plugin
    fi
else
    echo "Docker is not installed; installing bundled offline runtime"
    install_docker_engine
fi
wait_for_docker
docker compose version

install_container_egress_policy() {
    iptables -N 1PANEL-OFFLINE 2>/dev/null || true
    iptables -F 1PANEL-OFFLINE
    iptables -A 1PANEL-OFFLINE -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A 1PANEL-OFFLINE -d 10.0.0.0/8 -j ACCEPT
    iptables -A 1PANEL-OFFLINE -d 172.16.0.0/12 -j ACCEPT
    iptables -A 1PANEL-OFFLINE -d 192.168.0.0/16 -j ACCEPT
    iptables -A 1PANEL-OFFLINE -d 169.254.0.0/16 -j ACCEPT
    iptables -A 1PANEL-OFFLINE -d 127.0.0.0/8 -j ACCEPT
    iptables -A 1PANEL-OFFLINE -j REJECT
    iptables -C DOCKER-USER -j 1PANEL-OFFLINE 2>/dev/null \
        || iptables -I DOCKER-USER 1 -j 1PANEL-OFFLINE
    if command -v ip6tables >/dev/null 2>&1 && ip6tables -nL DOCKER-USER >/dev/null 2>&1; then
        ip6tables -N 1PANEL-OFFLINE 2>/dev/null || true
        ip6tables -F 1PANEL-OFFLINE
        ip6tables -A 1PANEL-OFFLINE -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        ip6tables -A 1PANEL-OFFLINE -d fc00::/7 -j ACCEPT
        ip6tables -A 1PANEL-OFFLINE -d fe80::/10 -j ACCEPT
        ip6tables -A 1PANEL-OFFLINE -d ::1/128 -j ACCEPT
        ip6tables -A 1PANEL-OFFLINE -j REJECT
        ip6tables -C DOCKER-USER -j 1PANEL-OFFLINE 2>/dev/null \
            || ip6tables -I DOCKER-USER 1 -j 1PANEL-OFFLINE
    fi

    cat >/usr/local/sbin/1panel-offline-egress <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
iptables -N 1PANEL-OFFLINE 2>/dev/null || true
iptables -F 1PANEL-OFFLINE
iptables -A 1PANEL-OFFLINE -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A 1PANEL-OFFLINE -d 10.0.0.0/8 -j ACCEPT
iptables -A 1PANEL-OFFLINE -d 172.16.0.0/12 -j ACCEPT
iptables -A 1PANEL-OFFLINE -d 192.168.0.0/16 -j ACCEPT
iptables -A 1PANEL-OFFLINE -d 169.254.0.0/16 -j ACCEPT
iptables -A 1PANEL-OFFLINE -d 127.0.0.0/8 -j ACCEPT
iptables -A 1PANEL-OFFLINE -j REJECT
iptables -C DOCKER-USER -j 1PANEL-OFFLINE 2>/dev/null || iptables -I DOCKER-USER 1 -j 1PANEL-OFFLINE
if command -v ip6tables >/dev/null 2>&1 && ip6tables -nL DOCKER-USER >/dev/null 2>&1; then
    ip6tables -N 1PANEL-OFFLINE 2>/dev/null || true
    ip6tables -F 1PANEL-OFFLINE
    ip6tables -A 1PANEL-OFFLINE -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    ip6tables -A 1PANEL-OFFLINE -d fc00::/7 -j ACCEPT
    ip6tables -A 1PANEL-OFFLINE -d fe80::/10 -j ACCEPT
    ip6tables -A 1PANEL-OFFLINE -d ::1/128 -j ACCEPT
    ip6tables -A 1PANEL-OFFLINE -j REJECT
    ip6tables -C DOCKER-USER -j 1PANEL-OFFLINE 2>/dev/null || ip6tables -I DOCKER-USER 1 -j 1PANEL-OFFLINE
fi
EOF
    chmod 0755 /usr/local/sbin/1panel-offline-egress

    cat >/etc/systemd/system/1panel-offline-egress.service <<'EOF'
[Unit]
Description=1Panel Offline Container Egress Policy
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/1panel-offline-egress
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now 1panel-offline-egress.service
}

install_container_egress_policy

install -m 0755 "${PACKAGE_DIR}/bin/1panel-core" /usr/local/bin/1panel-core
install -m 0755 "${PACKAGE_DIR}/bin/1panel-agent" /usr/local/bin/1panel-agent
install -m 0755 "${PACKAGE_DIR}/import-app.sh" /usr/local/bin/1panel-import-app
mkdir -p "${OFFLINE_APP_DIR}" "${PANEL_DIR}/resource/offline" "${PANEL_DIR}/geo" "${PANEL_DIR}/conf"
if find "${PACKAGE_DIR}/catalog" -mindepth 1 -print -quit | grep -q .; then
    cp -R "${PACKAGE_DIR}/catalog/." "${OFFLINE_APP_DIR}/"
fi
if [[ -f "${PACKAGE_DIR}/appstore-data.yaml" ]]; then
    cp "${PACKAGE_DIR}/appstore-data.yaml" "${PANEL_DIR}/resource/offline/data.yaml"
fi

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

IMAGE_ARCHIVE="${PACKAGE_DIR}/images/images.tar"
if [[ -f "${IMAGE_ARCHIVE}" ]]; then
    echo "importing bundled application images"
    docker image load -i "${IMAGE_ARCHIVE}"
fi

systemctl daemon-reload
systemctl enable --now 1panel-agent 1panel-core

echo "1Panel offline edition installed."
echo "URL: http://<server-ip>:${PANEL_PORT}/${PANEL_ENTRANCE}"
echo "Username: ${PANEL_USERNAME}"
echo "Password: ${PANEL_PASSWORD}"
echo "Run '1pctl status' to inspect services."
echo "Run 'sudo 1panel-import-app <bundle-directory>' to add custom offline applications."
