# Notes for coding agents

proxdump is a bash 5 tool that backs up Proxmox VE guests with `vzdump` and
uploads them encrypted through `rclone`. Read these before changing code:

- `docs/DEVELOPMENT.md` — testing, design notes and lessons learned (bash
  pitfalls of this code base), translations, package, demo.
- `docs/USAGE.md`, `docs/CONNECTIONS.md`, `docs/ENCRYPTION.md` — what the
  tool promises to its users.

## Rules

- English everywhere (code, comments, docs, commit messages); user strings
  go through `t "…" args` with `{1}`, `{2}` placeholders, then
  `tools/i18n.py check` lists what is missing in `lang/*.sh`.
- `README.md` has five translations (`README.fr.md`, `.es.md`, `.de.md`,
  `.zh-CN.md`, `.ru.md`): update them in the same commit. `docs/` is in
  English only.
- Minimal footprint: bash, `rclone`, `jq`, and what a Proxmox VE node ships.
  No new dependency at run time.
- Dialogs only through the helpers (`msg`, `confirm`, `input`, `menu`,
  `checklist`, `ui_run`…); a new helper needs both the whiptail version in
  `proxdump` and the native one in `lib/tui.sh`.
- Never print, log or commit secrets (tokens, passphrase, keys). Test on a
  copy of the configuration in a private folder (`PROXDUMP_CONF_DIR`…), and
  delete the copy.
- Never back up to, prune or delete in the real folders of the user, and
  never destroy a guest, unless asked: use a separate remote folder and say
  what was left behind.

## Checks

```
bash -n proxdump lib/tui.sh && shellcheck -S warning proxdump lib/tui.sh install.sh
tools/i18n.py check       # every message translated, none obsolete
```

Then drive the interface in tmux as described in `docs/DEVELOPMENT.md`.
