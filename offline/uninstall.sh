#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: sudo 1panel-uninstall [options]

Options:
  --yes             Do not ask for confirmation
  --purge-data      Delete /opt/1panel (or BASE_DIR/1panel), including app data
  --remove-docker   Remove Docker/containerd only when installed by this offline package
  --help            Show this help

By default, panel services and executables are removed while application data
and Docker are preserved.
EOF
}

ASSUME_YES=0
PURGE_DATA=0
REMOVE_DOCKER=0
for arg in "$@"; do
    case "${arg}" in
        --yes) ASSUME_YES=1 ;;
        --purge-data) PURGE_DATA=1 ;;
        --remove-docker) REMOVE_DOCKER=1 ;;
        --help|-h) usage; exit 0 ;;
        *) echo "unknown option: ${arg}" >&2; usage >&2; exit 1 ;;
    esac
done

if [[ "${EUID}" -ne 0 ]]; then
    echo "run this command as root" >&2
    exit 1
fi

BASE_DIR="${BASE_DIR:-/opt}"
PANEL_DIR="${BASE_DIR}/1panel"
STATE_FILE="${PANEL_DIR}/offline-install.env"
BUNDLED_DOCKER_INSTALLED=0
if [[ -f "${STATE_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${STATE_FILE}"
fi

if [[ "${ASSUME_YES}" != "1" ]]; then
    echo "This removes the 1Panel offline services and executables."
    if [[ "${PURGE_DATA}" == "1" ]]; then
        echo "WARNING: ${PANEL_DIR} and all application data under it will be deleted."
    else
        echo "Application data under ${PANEL_DIR} will be preserved."
    fi
    read -r -p "Continue? [y/N] " answer
    [[ "${answer}" == "y" || "${answer}" == "Y" ]] || exit 0
fi

systemctl disable --now 1panel-core.service 1panel-agent.service 1panel-offline-egress.service 2>/dev/null || true
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    mapfile -t managed_containers < <(docker ps -aq --filter label=createdBy=Apps)
    if [[ "${#managed_containers[@]}" -gt 0 ]]; then
        if [[ "${PURGE_DATA}" == "1" ]]; then
            docker rm -f "${managed_containers[@]}" >/dev/null
        else
            docker stop "${managed_containers[@]}" >/dev/null
            echo "Stopped ${#managed_containers[@]} managed application container(s); application data is preserved."
        fi
    fi
fi
rm -f \
    /etc/systemd/system/1panel-core.service \
    /etc/systemd/system/1panel-agent.service \
    /etc/systemd/system/1panel-offline-egress.service \
    /usr/local/bin/1panel-core \
    /usr/local/bin/1panel-agent \
    /usr/local/bin/1panel-import-app \
    /usr/local/bin/1panel-uninstall \
    /usr/local/bin/1pctl \
    /usr/local/sbin/1panel-offline-egress

if command -v iptables >/dev/null 2>&1; then
    while iptables -C DOCKER-USER -j 1PANEL-OFFLINE >/dev/null 2>&1; do
        iptables -D DOCKER-USER -j 1PANEL-OFFLINE
    done
    iptables -F 1PANEL-OFFLINE 2>/dev/null || true
    iptables -X 1PANEL-OFFLINE 2>/dev/null || true
fi
if command -v ip6tables >/dev/null 2>&1; then
    while ip6tables -C DOCKER-USER -j 1PANEL-OFFLINE >/dev/null 2>&1; do
        ip6tables -D DOCKER-USER -j 1PANEL-OFFLINE
    done
    ip6tables -F 1PANEL-OFFLINE 2>/dev/null || true
    ip6tables -X 1PANEL-OFFLINE 2>/dev/null || true
fi

if [[ "${REMOVE_DOCKER}" == "1" ]]; then
    if [[ "${BUNDLED_DOCKER_INSTALLED:-0}" != "1" ]]; then
        echo "Docker was not recorded as installed by this offline package; leaving it unchanged." >&2
    else
        systemctl disable --now docker.service containerd.service 2>/dev/null || true
        rm -f /etc/systemd/system/docker.service /etc/systemd/system/containerd.service
        rm -f /usr/local/lib/docker/cli-plugins/docker-compose
        for binary in containerd containerd-shim-runc-v2 ctr docker docker-init docker-proxy dockerd runc; do
            rm -f "/usr/local/bin/${binary}"
        done
    fi
fi

if [[ "${PURGE_DATA}" == "1" ]]; then
    rm -rf "${PANEL_DIR}"
else
    rm -f "${STATE_FILE}"
fi

systemctl daemon-reload
echo "1Panel offline edition uninstalled."
if [[ "${PURGE_DATA}" != "1" ]]; then
    echo "Preserved data: ${PANEL_DIR}"
fi
