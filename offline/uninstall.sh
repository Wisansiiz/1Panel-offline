#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: sudo 1panel-uninstall [options]

Options:
  --yes             Do not ask for confirmation
  --keep-data       Preserve 1Panel data and the Docker runtime for a later reinstall
  --keep-docker     Preserve Docker while deleting 1Panel data
  --purge-data      Compatibility option; data removal is now the default
  --remove-docker   Compatibility option; bundled Docker removal is now the default
  --help            Show this help

The default is a complete uninstall: 1Panel services, executables, data,
managed containers and images are removed. Docker/containerd and their data
are also removed when they were installed by this offline package. A Docker
installation that existed before 1Panel is never removed.
EOF
}

ASSUME_YES=0
KEEP_DATA=0
KEEP_DOCKER=0
REMOVE_DOCKER_REQUESTED=0
for arg in "$@"; do
    case "${arg}" in
        --yes) ASSUME_YES=1 ;;
        --keep-data) KEEP_DATA=1; KEEP_DOCKER=1 ;;
        --keep-docker) KEEP_DOCKER=1 ;;
        --purge-data) KEEP_DATA=0 ;;
        --remove-docker) KEEP_DOCKER=0; REMOVE_DOCKER_REQUESTED=1 ;;
        --help|-h) usage; exit 0 ;;
        *) echo "unknown option: ${arg}" >&2; usage >&2; exit 1 ;;
    esac
done

if [[ "${KEEP_DATA}" == "1" && "${REMOVE_DOCKER_REQUESTED}" == "1" ]]; then
    echo "--keep-data cannot be combined with --remove-docker" >&2
    exit 1
fi

if [[ "${EUID}" -ne 0 ]]; then
    echo "run this command as root" >&2
    exit 1
fi

BASE_DIR="${BASE_DIR:-/opt}"
PANEL_DIR="${BASE_DIR%/}/1panel"
PANEL_STATE_FILE="${PANEL_DIR}/offline-install.env"
OFFLINE_STATE_DIR="/var/lib/1panel-offline"
DOCKER_STATE_FILE="${OFFLINE_STATE_DIR}/install.env"
MANAGED_IMAGES_FILE="${PANEL_DIR}/resource/offline/images.txt"

case "${PANEL_DIR}" in
    ""|/|/1panel)
        echo "refusing unsafe panel directory: ${PANEL_DIR}" >&2
        exit 1
        ;;
esac

read_state_flag() {
    local file="$1"
    local key="$2"
    [[ -f "${file}" ]] || return 0
    awk -F= -v wanted="${key}" '
        $1 == wanted && ($2 == "0" || $2 == "1") { value = $2 }
        END { if (value != "") print value }
    ' "${file}"
}

BUNDLED_DOCKER_INSTALLED=0
BUNDLED_COMPOSE_INSTALLED=0
COMPOSE_STATE_FOUND=0
for state_file in "${PANEL_STATE_FILE}" "${DOCKER_STATE_FILE}"; do
    docker_state="$(read_state_flag "${state_file}" BUNDLED_DOCKER_INSTALLED)"
    compose_state="$(read_state_flag "${state_file}" BUNDLED_COMPOSE_INSTALLED)"
    if [[ "${docker_state}" == "1" ]]; then
        BUNDLED_DOCKER_INSTALLED=1
    fi
    if [[ -n "${compose_state}" ]]; then
        COMPOSE_STATE_FOUND=1
        if [[ "${compose_state}" == "1" ]]; then
            BUNDLED_COMPOSE_INSTALLED=1
        fi
    fi
done
# Older offline releases only recorded Docker ownership. Their Compose plugin
# was installed by the same code path, so treat it as package-owned too.
if [[ "${BUNDLED_DOCKER_INSTALLED}" == "1" && "${COMPOSE_STATE_FOUND}" == "0" ]]; then
    BUNDLED_COMPOSE_INSTALLED=1
fi
# Releases before the external ownership marker removed offline-install.env
# even though they kept the bundled Docker runtime. Recover that state only
# when the offline config and both exact static-runtime units agree.
legacy_bundled_docker_detected() {
    [[ -f "${PANEL_DIR}/conf/app.yaml" \
        && -f /etc/systemd/system/docker.service \
        && -f /etc/systemd/system/containerd.service ]] || return 1
    grep -Eq '^[[:space:]]*is_offline:[[:space:]]*true[[:space:]]*$' "${PANEL_DIR}/conf/app.yaml" \
        && grep -Fq 'ExecStart=/usr/local/bin/dockerd --host=unix:///var/run/docker.sock --containerd=/run/containerd/containerd.sock' /etc/systemd/system/docker.service \
        && grep -Fq 'ExecStart=/usr/local/bin/containerd' /etc/systemd/system/containerd.service
}
if [[ "${BUNDLED_DOCKER_INSTALLED}" == "0" ]] && legacy_bundled_docker_detected; then
    BUNDLED_DOCKER_INSTALLED=1
    BUNDLED_COMPOSE_INSTALLED=1
fi

if [[ "${ASSUME_YES}" != "1" ]]; then
    echo "This completely uninstalls the 1Panel offline edition."
    if [[ "${KEEP_DATA}" == "1" ]]; then
        echo "1Panel data and Docker will be preserved for a later reinstall: ${PANEL_DIR}"
    else
        echo "WARNING: ${PANEL_DIR} and all application data under it will be deleted."
        if [[ "${BUNDLED_DOCKER_INSTALLED}" == "1" && "${KEEP_DOCKER}" != "1" ]]; then
            echo "WARNING: bundled Docker/containerd and all data in /var/lib/docker and /var/lib/containerd will be deleted."
        elif [[ "${KEEP_DOCKER}" == "1" ]]; then
            echo "Docker is being kept; only resources managed by 1Panel will be removed from it."
        else
            echo "The pre-existing system Docker installation will be kept."
        fi
    fi
    read -r -p "Continue? [y/N] " answer
    [[ "${answer}" == "y" || "${answer}" == "Y" ]] || exit 0
fi

systemctl disable --now \
    1panel-core.service \
    1panel-agent.service \
    1panel-offline-egress.service 2>/dev/null || true

managed_containers=()
managed_projects=()
managed_images=()
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    mapfile -t managed_containers < <(
        {
            docker ps -aq --filter label=createdBy=Apps
            docker ps -aq --filter label=createdBy=1Panel
            while IFS= read -r container_id; do
                [[ -n "${container_id}" ]] || continue
                workdir="$(
                    docker inspect --format \
                        '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' \
                        "${container_id}" 2>/dev/null || true
                )"
                case "${workdir}" in
                    "${PANEL_DIR}"|"${PANEL_DIR}"/*) printf '%s\n' "${container_id}" ;;
                esac
            done < <(docker ps -aq --filter label=com.docker.compose.project.working_dir)
        } | awk 'NF && !seen[$0]++'
    )

    if [[ "${#managed_containers[@]}" -gt 0 ]]; then
        mapfile -t managed_projects < <(
            for container_id in "${managed_containers[@]}"; do
                docker inspect --format \
                    '{{ index .Config.Labels "com.docker.compose.project" }}' \
                    "${container_id}" 2>/dev/null || true
            done | awk 'NF && !seen[$0]++'
        )
        mapfile -t managed_images < <(
            {
                for container_id in "${managed_containers[@]}"; do
                    docker inspect --format '{{.Config.Image}}' \
                        "${container_id}" 2>/dev/null || true
                done
                if [[ -f "${MANAGED_IMAGES_FILE}" ]]; then
                    sed '/^[[:space:]]*$/d' "${MANAGED_IMAGES_FILE}"
                fi
            } | awk 'NF && !seen[$0]++'
        )
    elif [[ -f "${MANAGED_IMAGES_FILE}" ]]; then
        mapfile -t managed_images < <(
            sed '/^[[:space:]]*$/d' "${MANAGED_IMAGES_FILE}" | awk '!seen[$0]++'
        )
    fi

    if [[ "${#managed_containers[@]}" -gt 0 ]]; then
        if [[ "${KEEP_DATA}" == "1" ]]; then
            docker stop "${managed_containers[@]}" >/dev/null
            echo "Stopped ${#managed_containers[@]} managed application container(s)."
        else
            docker rm -f -v "${managed_containers[@]}" >/dev/null
            echo "Removed ${#managed_containers[@]} managed application container(s)."
        fi
    fi

    if [[ "${KEEP_DATA}" != "1" ]]; then
        for project in "${managed_projects[@]}"; do
            mapfile -t project_volumes < <(
                docker volume ls -q --filter "label=com.docker.compose.project=${project}"
            )
            if [[ "${#project_volumes[@]}" -gt 0 ]]; then
                docker volume rm "${project_volumes[@]}" >/dev/null 2>&1 || true
            fi
            mapfile -t project_networks < <(
                docker network ls -q --filter "label=com.docker.compose.project=${project}"
            )
            if [[ "${#project_networks[@]}" -gt 0 ]]; then
                docker network rm "${project_networks[@]}" >/dev/null 2>&1 || true
            fi
        done
        docker network rm 1panel-network >/dev/null 2>&1 || true
        for image_name in "${managed_images[@]}"; do
            # Do not force image removal: Docker will preserve an image if a
            # non-1Panel container still references it.
            docker image rm "${image_name}" >/dev/null 2>&1 || true
        done
    fi
elif [[ "${KEEP_DATA}" != "1" && "${BUNDLED_DOCKER_INSTALLED}" != "1" ]]; then
    echo "WARNING: Docker is unavailable; existing 1Panel containers and images could not be removed." >&2
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
    /usr/local/sbin/1panel-offline-egress \
    /etc/1panel/agent.sock

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

if [[ "${KEEP_DOCKER}" == "1" ]]; then
    if [[ "${BUNDLED_DOCKER_INSTALLED}" == "1" || "${BUNDLED_COMPOSE_INSTALLED}" == "1" ]]; then
        install -d -m 0700 "${OFFLINE_STATE_DIR}"
        cat >"${DOCKER_STATE_FILE}" <<EOF
BUNDLED_DOCKER_INSTALLED=${BUNDLED_DOCKER_INSTALLED}
BUNDLED_COMPOSE_INSTALLED=${BUNDLED_COMPOSE_INSTALLED}
EOF
        chmod 0600 "${DOCKER_STATE_FILE}"
    fi
elif [[ "${BUNDLED_DOCKER_INSTALLED}" == "1" ]]; then
    systemctl disable --now docker.socket docker.service containerd.service 2>/dev/null || true
    rm -f /etc/systemd/system/docker.service /etc/systemd/system/containerd.service
    if [[ "${BUNDLED_COMPOSE_INSTALLED}" == "1" ]]; then
        rm -f /usr/local/lib/docker/cli-plugins/docker-compose
    fi
    for binary in containerd containerd-shim-runc-v2 ctr docker docker-init docker-proxy dockerd runc; do
        rm -f "/usr/local/bin/${binary}"
    done
    rm -rf -- /var/lib/docker /var/lib/containerd /run/docker /run/containerd
    rm -f /var/run/docker.sock
    rm -f "${DOCKER_STATE_FILE}"
    rmdir "${OFFLINE_STATE_DIR}" 2>/dev/null || true
    rmdir /etc/docker 2>/dev/null || true
elif [[ "${BUNDLED_COMPOSE_INSTALLED}" == "1" ]]; then
    rm -f /usr/local/lib/docker/cli-plugins/docker-compose
    rm -f "${DOCKER_STATE_FILE}"
    rmdir "${OFFLINE_STATE_DIR}" 2>/dev/null || true
fi

if [[ "${KEEP_DATA}" == "1" ]]; then
    echo "Preserved data for reinstall: ${PANEL_DIR}"
else
    rm -rf -- "${PANEL_DIR}"
    rm -rf -- /etc/1panel
fi

systemctl daemon-reload
echo "1Panel offline edition completely uninstalled."
if [[ "${BUNDLED_DOCKER_INSTALLED}" == "1" && "${KEEP_DOCKER}" != "1" ]]; then
    echo "Removed the bundled Docker runtime and its container data."
elif [[ "${KEEP_DOCKER}" == "1" ]]; then
    echo "Preserved Docker as requested."
else
    echo "Preserved the pre-existing system Docker installation."
fi
