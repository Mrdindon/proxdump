# Development

[← proxdump](../README.md)

The script passes `shellcheck` with no warnings. To try the tool without
touching the real configuration or a real OneDrive account, you can redirect
its files and use a local folder as a fake OneDrive:

```bash
export PROXDUMP_CONF_DIR=/tmp/odp/conf PROXDUMP_LOG=/tmp/odp/log \
       PROXDUMP_LOCK=/tmp/odp/lock PROXDUMP_CRON=/tmp/odp/cron
mkdir -p /tmp/odp/conf /tmp/odp/fake-onedrive
printf '[onedrive]\ntype = alias\nremote = /tmp/odp/fake-onedrive\n' > /tmp/odp/conf/rclone.conf
./proxdump      # then Configuration → Encryption, and a trial backup
```

## Translations

English is the source language: the messages are written in English in
`proxdump`, wrapped in the function `t`, and each `lang/<code>.sh` holds
their translations, one `_m 'English' 'translation'` line per message. A
message without translation is displayed in English.

```bash
tools/i18n.py list     # numbered list of the messages found in proxdump
tools/i18n.py check    # missing and obsolete entries of each catalogue
```

After adding or changing a message, run `tools/i18n.py check` and complete
the catalogues it reports. The translations were not reviewed by native
speakers: corrections are welcome.

The presentation exists in six languages (`README.md`, `README.fr.md`,
`README.es.md`, `README.de.md`, `README.zh-CN.md`, `README.ru.md`): update
them together. The pages of `docs/` are in English only.

## Debian package

```bash
tools/make-deb.sh      # as root: builds dist/proxdump_<version>_all.deb
```

The package installs the tool in `/usr/bin` and its files in
`/usr/share/proxdump`. It only recommends `rclone`, because the version of
Debian is too old for OneDrive: its installation script says how to install
the official package when rclone is missing or older than 1.65. Removing
the package deletes the schedules but keeps `/etc/proxdump`.

## Demo animation

`docs/demo.gif` is built by `tools/make-demo.py` from screens of a tmux pane
saved at regular intervals with `tmux capture-pane -p -e` while the tool is
driven with `tmux send-keys`. The script needs Pillow (`python3-pil`) and the
DejaVu Sans Mono font; it merges identical screens and speeds up the long
operations.
