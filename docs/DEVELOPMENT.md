# Development

[← proxdump](../README.md)

## Testing

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

The interface can be driven and read from a script with tmux: start the tool
in a detached session (`tmux new-session -d -s t -x 100 -y 30 ./proxdump`),
send keys with `tmux send-keys`, read the screen with `tmux capture-pane -p`.
Restart the session after editing the script: bash reads it as it runs.

What was exercised on a real Proxmox VE 9 node: backup, verification,
retention, listing, deletion and download with OneDrive and Google Drive;
backup and restore of a container under a new ID with OneDrive; S3 and SFTP
against local test servers (`rclone serve s3`, `rclone serve sftp`). Not
exercised: restoring a virtual machine, Dropbox beyond its authorization,
real S3 providers and real SSH servers.

## Design notes and lessons learned

- **Everything goes through rclone remotes.** A destination is an rclone
  remote named after its id, with a `crypt` remote `<id>-crypt` on top; the
  functions that read or write remote files work on the *current*
  destination set by `use_dest`. Adding a destination starts with the
  tables at the top of `proxdump`.
- **The dialogs are a thin layer.** The tool only calls `msg`, `confirm`,
  `input`, `password`, `menu`, `checklist`, `textbox`, `busy`, `ui_run`
  (an operation behind a progress window) and `screen` (plain terminal, for
  text that must be copied or pasted). `lib/tui.sh` redefines them for the
  native interface; nothing else knows which style is in use.
- **Operations report through `log`.** From the menus, each message becomes
  the step shown in the progress window, and the summary is built from the
  messages: lines ending in `…` are steps and are left out, lines starting
  with `ERROR` are kept. Translations must keep that final `…`.
- **`set -o pipefail` and functions that end on a test.** A function whose
  last command is a failed `[[ … ]] && …` returns 1; read through a
  pipeline, it made every destination look unconfigured. Such functions end
  with `return 0`.
- **`read -t` returns what it has read when it times out.** A reader that
  polls with a timeout must keep that partial line and prepend it to the
  next one, or a line-based protocol goes out of step (the progress window
  lost its text that way).
- **whiptail puts the terminal in raw mode and undefines the interrupt
  key.** Ctrl-C does nothing behind a gauge until `stty isig intr '^C'` is
  run after it has started. It also does not follow a change of size: the
  gauge is restarted by a relay.
- **`stty size` reads its standard input.** In a process that reads a pipe
  it must be given `</dev/tty`, otherwise the size falls back to 80×24.
- **bash 5.2 treats `&` in the replacement of `${var//pattern/text}` as the
  match.** The replacement is quoted wherever it is user text (`t`).
- **Character ranges follow the collation of the locale.** Counting
  double-width characters with `[$'\u0001'-$'\u2e7f']` needs
  `LC_COLLATE=C` locally.
- **Secrets never go on a command line.** Sections holding a passphrase or
  a key are written straight into `rclone.conf`, and tests use a copy of the
  configuration in a private folder.

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
