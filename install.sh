#!/usr/bin/env bash
# Ubuntu 24.04 only. Does not start/restart the relay or configure networking.
set -euo pipefail

usage() {
    cat <<'TEXT'
Usage: sudo bash install.sh [--skip-packages]

Installs the fixed UDP MPEG-TS -> Compass relay for Ubuntu 24.04.
Preserves /etc/compass-relay/relay.env if it exists.
Backs up an existing unit/runtime before updating them.
Does not start or restart the service. Configure it, then enable and restart it.

--skip-packages  Skip apt; still verify all required GStreamer elements.
TEXT
}

skip_packages=false
case "${1:-}" in
    --help|-h) usage; exit 0 ;;
    --skip-packages) skip_packages=true ;;
    "") ;;
    *) usage >&2; exit 64 ;;
esac
[[ $# -le 1 ]] || { usage >&2; exit 64; }
[[ $EUID -eq 0 ]] || { printf 'Run this installer with sudo.\n' >&2; exit 1; }

# This file is supplied by the OS, not by the repository.
. /etc/os-release
[[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 24.04 ]] || {
    printf 'Supported target: Ubuntu 24.04. Detected: %s\n' "${PRETTY_NAME:-unknown}" >&2
    exit 1
}
[[ -d /run/systemd/system ]] || {
    printf 'Run this on the Ubuntu Pi with systemd running, not in a container/chroot.\n' >&2
    exit 1
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
packages=(
    gstreamer1.0-tools
    gstreamer1.0-plugins-base
    gstreamer1.0-plugins-good
    gstreamer1.0-plugins-bad
    gstreamer1.0-plugins-ugly
    gstreamer1.0-rtsp
)
for file in relay.sh compass-relay.service relay.env.example simulate-camera.sh; do
    [[ -f "$script_dir/$file" ]] || {
        printf 'Incomplete bundle; missing %s\n' "$file" >&2
        exit 1
    }
done

if ! "$skip_packages"; then
    apt-get update
    if ! apt-get install -y --no-install-recommends "${packages[@]}"; then
        printf '\nPackage installation failed. Check apt output and internet access.\n' >&2
        printf 'For missing Universe packages, see the README troubleshooting instructions.\n' >&2
        exit 1
    fi
fi
bash "$script_dir/relay.sh" --check-plugins
bash "$script_dir/simulate-camera.sh" --check-plugins

if ! getent group compass-relay >/dev/null; then
    groupadd --system compass-relay
fi
if ! id compass-relay >/dev/null 2>&1; then
    useradd --system --gid compass-relay --no-create-home \
        --home-dir /nonexistent --shell /usr/sbin/nologin compass-relay
fi
[[ "$(id -u compass-relay)" != 0 ]] || {
    printf 'Refusing to use a compass-relay account with UID 0.\n' >&2
    exit 1
}

config_dir=/etc/compass-relay
runtime_dir=/usr/local/lib/compass-relay
unit_path=/etc/systemd/system/compass-relay.service
backup_root=/var/backups/compass-relay
backup_dir=""

if [[ -e "$unit_path" || -L "$unit_path" || -d "$runtime_dir" || -e "$config_dir/relay.env" ]]; then
    install -d -m 0700 "$backup_root"
    backup_dir="$(mktemp -d "$backup_root/$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")"
    if [[ -e "$unit_path" || -L "$unit_path" ]]; then
        cp -a -- "$unit_path" "$backup_dir/compass-relay.service"
    fi
    if [[ -d "$runtime_dir" ]]; then
        cp -a -- "$runtime_dir" "$backup_dir/runtime"
    fi
    if [[ -e "$config_dir/relay.env" ]]; then
        cp -a -- "$config_dir/relay.env" "$backup_dir/relay.env"
    fi
    printf 'Backup: %s\n' "$backup_dir"
fi

install -d -m 0755 "$config_dir" "$runtime_dir" /var/lib/compass-relay
if [[ ! -e "$config_dir/relay.env" ]]; then
    install -o root -g root -m 0600 "$script_dir/relay.env.example" "$config_dir/relay.env"
    printf 'Created configuration using the dedicated bench endpoint.\n'
else
    printf 'Preserved existing %s/relay.env.\n' "$config_dir"
fi
install -o root -g root -m 0755 "$script_dir/relay.sh" "$runtime_dir/relay.sh"
install -o root -g root -m 0644 "$script_dir/compass-relay.service" "$unit_path"

systemd-analyze verify "$unit_path"
systemctl daemon-reload

{
    printf 'Installed UTC: %s\n' "$(date -u +%FT%TZ)"
    printf 'OS: %s\n' "$PRETTY_NAME"
    printf 'Architecture: %s\n' "$(dpkg --print-architecture)"
    gst-launch-1.0 --version
    dpkg-query -W -f='${binary:Package}\t${Version}\n' "${packages[@]}"
} > /var/lib/compass-relay/installed-versions.txt

cat <<'TEXT'

Installed. Any currently running relay keeps its existing process until restarted.
Review the destination and port:
  sudo nano /etc/compass-relay/relay.env

Stop any manually launched diagnostic relay using UDP 15004, then apply:
  sudo systemctl enable compass-relay.service
  sudo systemctl restart compass-relay.service
  systemctl status compass-relay.service --no-pager

Follow new messages (Ctrl+C exits only the log viewer):
  sudo journalctl -u compass-relay.service -n 0 -f

The service runs as compass-relay, independently of your login or repository path.
TEXT
