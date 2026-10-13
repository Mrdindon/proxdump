#!/usr/bin/env bash
# Installs proxdump and its dependencies on a Proxmox VE node.
#   ./install.sh              install or update
#   ./install.sh --uninstall  remove the tool (the configuration is kept)

set -euo pipefail

BIN=/usr/local/bin/proxdump
CONF_DIR=/etc/proxdump
RCLONE_MIN="1.65"
SRC_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

((EUID == 0)) || { echo "Must be run as root." >&2; exit 1; }

if [[ ${1:-} == --uninstall ]]; then
    rm -f "$BIN" /etc/cron.d/proxdump
    echo "proxdump removed."
    echo "Kept on purpose: $CONF_DIR (OneDrive token, passphrase) and /var/log/proxdump.log."
    echo "To erase everything: rm -rf $CONF_DIR /var/log/proxdump.log"
    exit 0
fi

command -v pveversion >/dev/null ||
    { echo "This script is meant for a Proxmox VE node (pveversion not found)." >&2; exit 1; }

pkgs=()
command -v whiptail >/dev/null || pkgs+=(whiptail)
command -v jq >/dev/null || pkgs+=(jq)
command -v curl >/dev/null || pkgs+=(curl)
if ((${#pkgs[@]})); then
    echo "Installing packages: ${pkgs[*]}"
    apt-get update -qq
    apt-get install -y "${pkgs[@]}"
fi

# Debian's rclone is too old for the current OneDrive API:
# install the official package if rclone is missing or older than $RCLONE_MIN.
rclone_ok() {
    local v
    command -v rclone >/dev/null || return 1
    v=$(rclone version 2>/dev/null | sed -n '1s/^rclone v\([0-9]*\.[0-9]*\).*/\1/p')
    [[ -n $v ]] && dpkg --compare-versions "$v" ge "$RCLONE_MIN"
}

if ! rclone_ok; then
    arch=$(dpkg --print-architecture)
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    echo "Installing rclone (official package, $arch)…"
    curl -fsSL -o "$tmp/rclone.deb" "https://downloads.rclone.org/rclone-current-linux-$arch.deb"
    dpkg -i "$tmp/rclone.deb"
fi

install -m 755 "$SRC_DIR/proxdump" "$BIN"
install -d -m 700 "$CONF_DIR"

echo
echo "proxdump $("$BIN" --version) installed in $BIN ($(rclone version | head -n1))."
echo "Run 'proxdump' then open the Configuration menu."
