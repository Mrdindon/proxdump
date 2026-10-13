#!/usr/bin/env bash
# Builds the Debian package of proxdump: dist/proxdump_<version>_all.deb
#   tools/make-deb.sh
# Needs dpkg-deb only. Must be run as root so that the files of the package
# belong to root (or under fakeroot).

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VERSION=$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$ROOT/proxdump")
[[ -n $VERSION ]] || { echo "version not found in proxdump" >&2; exit 1; }
((EUID == 0)) || [[ -n ${FAKEROOTKEY:-} ]] ||
    { echo "run as root or under fakeroot" >&2; exit 1; }

OUT="$ROOT/dist"
PKG=$(mktemp -d)
trap 'rm -rf "$PKG"' EXIT
chmod 755 "$PKG"

install -d -m 755 "$PKG/DEBIAN" "$PKG/usr/bin" \
    "$PKG/usr/share/proxdump/lang" "$PKG/usr/share/proxdump/lib" \
    "$PKG/usr/share/proxdump/themes" "$PKG/usr/share/doc/proxdump"
install -m 755 "$ROOT/proxdump" "$PKG/usr/bin/proxdump"
install -m 644 "$ROOT"/lang/*.sh "$PKG/usr/share/proxdump/lang/"
install -m 644 "$ROOT"/lib/*.sh "$PKG/usr/share/proxdump/lib/"
install -m 644 "$ROOT"/themes/*.sh "$PKG/usr/share/proxdump/themes/"
install -m 644 "$ROOT"/README*.md "$ROOT"/docs/*.md "$PKG/usr/share/doc/proxdump/"

cat >"$PKG/usr/share/doc/proxdump/copyright" <<EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: proxdump
Source: https://github.com/Mrdindon/proxdump

Files: *
Copyright: 2026 proxdump contributors
License: AGPL-3+
 This program is free software: you can redistribute it and/or modify it
 under the terms of the GNU Affero General Public License as published by
 the Free Software Foundation, either version 3 of the License, or (at your
 option) any later version.
 .
 This program is distributed in the hope that it will be useful, but WITHOUT
 ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License
 for more details: https://www.gnu.org/licenses/agpl-3.0.html
EOF

# rclone is only recommended: the version of Debian is too old for OneDrive,
# so it cannot be required; postinst says what to do.
cat >"$PKG/DEBIAN/control" <<EOF
Package: proxdump
Version: $VERSION
Section: admin
Priority: optional
Architecture: all
Depends: bash (>= 5.0), whiptail, jq, openssh-client
Recommends: rclone (>= 1.65), curl
Maintainer: Mrdindon <5002201+Mrdindon@users.noreply.github.com>
Homepage: https://github.com/Mrdindon/proxdump
Installed-Size: $(du -sk "$PKG/usr" | cut -f1)
Description: encrypted backup of Proxmox VE guests to cloud storage
 proxdump backs up the virtual machines and containers of a Proxmox VE node
 with vzdump, encrypts the archives on the server and uploads them to
 Microsoft OneDrive, Google Drive, Dropbox, an S3-compatible storage or an
 SFTP server, from menus in the terminal.
EOF

cat >"$PKG/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = configure ]; then
    v=$(rclone version 2>/dev/null | sed -n '1s/^rclone v\([0-9]*\.[0-9]*\).*/\1/p')
    if [ -z "$v" ] || ! dpkg --compare-versions "$v" ge 1.65; then
        arch=$(dpkg --print-architecture)
        echo "proxdump: rclone 1.65 or later is required (found: ${v:-none})."
        echo "proxdump: Debian's package is too old; install the official one:"
        echo "  curl -fsSLO https://downloads.rclone.org/rclone-current-linux-$arch.deb"
        echo "  dpkg -i rclone-current-linux-$arch.deb"
    fi
fi
exit 0
EOF

# The schedules call the tool: they go with it. The configuration holds the
# passphrase of the backups and is never removed by the package.
cat >"$PKG/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
case "$1" in
remove | purge)
    rm -f /etc/cron.d/proxdump
    if [ -d /etc/proxdump ]; then
        echo "proxdump: /etc/proxdump (credentials, passphrase) and /var/log/proxdump.log are kept."
        echo "proxdump: to erase them: rm -rf /etc/proxdump /var/log/proxdump.log"
    fi
    ;;
esac
exit 0
EOF
chmod 755 "$PKG/DEBIAN/postinst" "$PKG/DEBIAN/postrm"

mkdir -p "$OUT"
dpkg-deb --build --root-owner-group "$PKG" "$OUT/proxdump_${VERSION}_all.deb" >/dev/null
echo "$OUT/proxdump_${VERSION}_all.deb"
