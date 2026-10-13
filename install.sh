#!/usr/bin/env bash
# Installe onedrivepbs et ses dépendances sur un nœud Proxmox VE.
#   ./install.sh              installe ou met à jour
#   ./install.sh --uninstall  retire l'outil (la configuration est conservée)

set -euo pipefail

BIN=/usr/local/bin/onedrivepbs
CONF_DIR=/etc/onedrivepbs
RCLONE_MIN="1.65"
SRC_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

((EUID == 0)) || { echo "À lancer en root." >&2; exit 1; }

if [[ ${1:-} == --uninstall ]]; then
    rm -f "$BIN" /etc/cron.d/onedrivepbs
    echo "onedrivepbs retiré."
    echo "Conservés volontairement : $CONF_DIR (jeton OneDrive, phrase secrète) et /var/log/onedrivepbs.log."
    echo "Pour tout effacer : rm -rf $CONF_DIR /var/log/onedrivepbs.log"
    exit 0
fi

command -v pveversion >/dev/null ||
    { echo "Ce script est prévu pour un nœud Proxmox VE (pveversion introuvable)." >&2; exit 1; }

pkgs=()
command -v whiptail >/dev/null || pkgs+=(whiptail)
command -v jq >/dev/null || pkgs+=(jq)
command -v curl >/dev/null || pkgs+=(curl)
if ((${#pkgs[@]})); then
    echo "Installation des paquets : ${pkgs[*]}"
    apt-get update -qq
    apt-get install -y "${pkgs[@]}"
fi

# Le rclone de Debian est trop ancien pour l'API OneDrive actuelle :
# on installe le paquet officiel si rclone est absent ou antérieur à $RCLONE_MIN.
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
    echo "Installation de rclone (paquet officiel, $arch)…"
    curl -fsSL -o "$tmp/rclone.deb" "https://downloads.rclone.org/rclone-current-linux-$arch.deb"
    dpkg -i "$tmp/rclone.deb"
fi

install -m 755 "$SRC_DIR/onedrivepbs" "$BIN"
install -d -m 700 "$CONF_DIR"

echo
echo "onedrivepbs $("$BIN" --version) installé dans $BIN ($(rclone version | head -n1))."
echo "Lancez « onedrivepbs » puis ouvrez le menu Configuration."
