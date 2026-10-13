# Reference

[← proxdump](../README.md)

## Files and security

| File | Contents | Permissions |
|---|---|---|
| `/usr/local/bin/proxdump` | The tool | 755 |
| `/etc/proxdump/rclone.conf` | **Access tokens, S3 keys, SFTP password and passphrase** | 600, folder 700 |
| `/etc/proxdump/sftp_key` | **Private SSH key** used for the SFTP server | 600 |
| `/etc/proxdump/sftp_known_hosts` | Host keys of the SFTP server | 600 |
| `/etc/proxdump/config` | Settings (no secrets) | 600 |
| `/usr/local/share/proxdump/lang/` | Translations of the interface | 644 |
| `/usr/local/share/proxdump/lib/`, `themes/` | Native interface and its colour themes | 644 |
| `/etc/cron.d/proxdump` | Schedules and daily token refreshes | 644 |
| `/var/log/proxdump.log` | Operations log | — |

Good to know:

- In `rclone.conf`, the passphrase is only *obscured* by rclone, not
  encrypted: anyone who reads that file can decrypt the backups and access
  the OneDrive. It is readable by root only; do not copy it elsewhere
  unprotected and never commit it.
- Encryption protects your data from OneDrive and from anyone who gains
  access to the account. It does not protect against someone who is root on
  the Proxmox server.
- During a backup or a restore, the archive exists **in plaintext** in the
  local staging folder; it is deleted as soon as the operation ends,
  including on error or interruption.
- File names (guest IDs and names, backup dates), sizes and upload dates
  remain visible on the OneDrive side; only the contents are encrypted.
- This repository contains no credentials, token or passphrase: all of that
  lives only in `/etc/proxdump`, and the `.gitignore` excludes those files.

## Troubleshooting

| Symptom | What to try |
|---|---|
| "The OneDrive connection and the encryption must be configured…" | Complete steps 1 and 2 of the configuration |
| The pasted token is rejected | Use the same rclone version on both sides; paste it on a single line, or go through a file |
| Connection test fails after a few months | Token expired or revoked: redo **OneDrive connection** |
| `vzdump` fails for lack of space | Change the **local staging folder** to a larger storage |
| Very slow upload or 429 errors | Microsoft is throttling; rclone retries by itself. Avoid peak hours |
| Empty list although OneDrive contains files | Wrong passphrase or wrong **Folder on the destinations** |
| "Another proxdump operation is already in progress" | Wait for the scheduled backup to finish, or check with `ps aux \| grep proxdump` |
| Restoring under the original ID fails | The existing guest must be stopped and not locked |

The details of each operation (`vzdump` and `rclone` output) are in
`/var/log/proxdump.log`, also viewable through the **Log** menu.

## Known limitations

- One node at a time: the tool backs up the guests of the node it runs on.
- Full backups only (no incremental, no deduplication): each version takes
  its whole compressed size on the destination.
- Maximum file size on OneDrive: 250 GB per archive. Google Drive accepts
  larger files but limits uploads to 750 GB per day. Dropbox: 350 GB per
  archive.
- A single S3 bucket and a single SFTP server can be configured.
- Local space for the compressed archive is needed, for backup as well as
  for restore.
- Restore only exists in the menus (no subcommand).
