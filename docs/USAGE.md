# Using proxdump

[← proxdump](../README.md)

## How it works

For each selected guest:

1. `vzdump` creates the archive (and its log) in a temporary subfolder;
2. `rclone` uploads it through a `crypt` *remote*: the file is encrypted
   locally (XSalsa20-Poly1305, key derived from the passphrase with scrypt),
   so the destination only receives unreadable data;
3. `rclone cryptcheck` compares the local and remote checksums;
4. retention is applied to that guest (the oldest versions beyond the
   configured number are deleted);
5. steps 2 to 4 are repeated for each destination selected, then the
   temporary subfolder is deleted.

OneDrive shows this:

```
pve-backups/<node>/
├── 100_web/
│   ├── vzdump-qemu-100-2026_10_12-02_00_03.vma.zst.encrypted
│   └── vzdump-qemu-100-2026_10_12-02_00_03.log.encrypted
└── 101_dns/
    ├── vzdump-lxc-101-2026_10_12-02_04_41.tar.zst.encrypted
    └── vzdump-lxc-101-2026_10_12-02_04_41.log.encrypted
```

`vzdump` itself decides what goes into an archive, so Proxmox's per-disk
backup setting is honoured: a VM disk with "Backup" unticked (`backup=0`) is
left out, and a container mount point is only included if it has `backup=1`
(the root disk always is). Disks left out are not in the archive and are
therefore not restored.

The archives are standard `vzdump` archives: once downloaded and decrypted,
they can also be restored with `qmrestore` / `pct restore` or the Proxmox web
interface, without this tool.


## Language

The interface and the log follow the language of the system (`LANG`) when it
is one of English, French, Spanish, German, Chinese (simplified) or Russian,
and fall back to English otherwise. **Configuration → Language** selects
another one; the choice also applies to the scheduled backups. The
`PROXDUMP_LANG` environment variable (`en`, `fr`, `es`, `de`, `zh`, `ru`)
overrides both for one run.

The command-line help, the installer and the detailed documentation are in
English; the presentation (`README`) exists in the six languages.
In the Google Drive instructions, the names of the Google console menus are
given in English whatever the language. Chinese and Russian need a terminal
whose font has those characters, which rules out the physical console of the
server.

## Appearance

**Configuration → Appearance of the interface** offers two styles:

- **Classic**: the dialogs of `whiptail`;
- **Native** (the default): dialogs drawn by proxdump itself, with a header
  bar, a window with rounded borders, the available keys at the bottom of
  the screen, an animated progress window, the mouse (click to open or tick,
  wheel to scroll) and a choice of colour themes: Default, Dracula, Nord,
  Gruvbox, Catppuccin, Tokyo Night, Solarized, Light and Basic (8 colours).
  If its files are missing, the classic style is used instead.

The style applies from the next start. Both follow the size of the terminal
when it changes, including during a backup. `PROXDUMP_UI=native` (or
`whiptail`), `PROXDUMP_THEME=<name>` and `PROXDUMP_GLYPHS=ascii` override
the settings for one run; ASCII characters are used by themselves on the
Linux console. With the mouse enabled, hold Shift to select text with the
terminal, or disable the mouse in the same menu.

A theme is a file of `themes/` that lists the colours differing from the
default theme defined in `lib/tui.sh`.

## Encryption

A single passphrase protects every destination.

**Configuration → Encryption** offers to generate a random passphrase
(recommended) or to enter your own.

> **Write this passphrase down off the server** (password manager, paper).
> It is required to restore if this server is lost. Without it, the backups
> are permanently unreadable — nobody, not even the storage provider, can decrypt them.

The same menu lets you display the passphrase again later, or change it.
The passphrase is shown on the plain terminal, outside the dialogs, so that
it can be selected with the mouse and copied.
Note: existing backups remain encrypted with the old passphrase.

The algorithms, what stays visible on the destination and where the secrets
are kept are described in [Encryption](ENCRYPTION.md).

### File names

rclone's `crypt` encrypts the contents of every file (XSalsa20-Poly1305,
256-bit key). The names are left as they are, followed by `.encrypted`, so
the OneDrive folder stays easy to browse:
`100_web/vzdump-qemu-100-….vma.zst.encrypted`. Guest IDs, guest names,
backup dates, file sizes and upload dates are therefore visible to anyone
with access to the OneDrive account.

An installation made with an earlier version, which could encrypt the names,
is detected when the menus open: the tool offers to rename the existing
backups in place, without uploading them again.

## Folders and options

| Setting | Default | Purpose |
|---|---|---|
| Folder on the destinations | `pve-backups/<node>` | Where the backups live, on each destination |
| Local staging folder | `/var/lib/vz/dump` | Where `vzdump` writes the archive before upload. Pick a storage with enough free space |
| vzdump mode | `snapshot` | `snapshot` (no downtime), `suspend` or `stop` |
| Compression | `zstd` | `zstd`, `gzip`, `lzo` or none |
| Upload rate limit | none | E.g. `10M` to avoid saturating the connection |
| Verify after upload | yes | Checksum comparison |

## Backing up

Menu **1 – Back up virtual machines and containers**: select the guests (space bar),
confirm. When several destinations are configured, the tool first asks which
ones to use; the archive is created once and uploaded to each of them.

Every operation started from the menus (backup, restore, download,
deletion, retention) runs behind a progress dialog that shows the guest
being processed, the current step, and its details: percentage, size, speed
and remaining time. A container archive reports no percentage, so the size
written so far is shown instead; the verification shows the time elapsed. At
the end, a summary gives the outcome and what failed, and the complete
output is kept in the log (menu **6 – Log**). **Ctrl-C** interrupts the
operation and cleans up the staging folder.

A failure on one guest does not stop the following ones; the summary gives
the number of successes.

Tip: run the tool inside `tmux` or `screen` for large backups, so that a
dropped SSH session does not interrupt the upload.

## Managing the stored backups

When several destinations are configured, the tool first asks which one to
manage; each destination has its own list, and the retention settings apply
to each of them separately.

Menu **3 – Manage the stored backups**:

| Entry | Effect |
|---|---|
| List the backups | ID, type, name, date and size of each backup, and the total |
| Delete backups | Deletes the ones you select (with confirmation) |
| Retention policy | Number of versions kept per guest: default value, and per-guest value |
| Apply the retention policy now | Immediate pruning according to the settings |
| Storage used on OneDrive | Account quota |

Retention rules:

- the default is **3** versions per guest;
- a per-guest value overrides the default for that guest;
- **0** means "keep everything";
- retention is applied automatically after each successful backup of the
  guest concerned, never after a failure;
- deleted files go through the OneDrive recycle bin (still encrypted) and
  keep counting against the quota until it is emptied.

## Restoring

Menu **2 – Restore a backup**: choose the backup, then:

| Choice | Effect |
|---|---|
| Restore under the original ID | Recreates the guest. If it already exists, it is **overwritten** after confirmation (it must be stopped) |
| Restore under a new ID | Creates a copy; the tool suggests the next free ID and new MAC addresses |
| Download the decrypted archive only | Puts the decrypted archive in the given folder, without restoring |

The tool then asks for the target storage for the disks, downloads and
decrypts the archive into the staging folder, runs `qmrestore` (VM) or
`pct restore` (container), then deletes the temporary archive.

After restoring under a new ID, remember to check the IP address and host
name before starting the copy if the original is still running.

## Scheduling and command line

Menu **4 – Automatic scheduling** lists the schedules and lets you add or
remove them. Selecting a schedule also offers:

- **Run this schedule now**, which backs up its guests immediately, with the
  progress on screen, without changing the schedule;
- **Change the frequency and time**, which keeps its guests and
  destinations; the current time is offered as the default;
- **Change the guests included**, which keeps its frequency, time and
  destinations. A guest of the schedule that is no longer on the node is
  shown ticked, as "not found on this node", so that it can be removed.

Several schedules can coexist, for instance a daily one for a critical
guest and a weekly one for everything. Each schedule defines:

- the destinations, among those that are configured (the question is
  skipped when there is only one);
- the frequency: daily, weekly on a given day, monthly on a given day (1 to
  28, so that no month is skipped), yearly on a given date, or **manual**:
  a manual schedule never runs by itself and is started with **Run this
  schedule now**; it keeps its last time, should it become automatic again;
- the start time (HH:MM), except for a manual schedule;
- the guests: either **all guests on the node**, which includes those added
  later, or **a selection** of guests.

The schedules are stored in `/etc/cron.d/proxdump`, one line each; a
manual schedule is its line commented out with `#manual`. A
schedule that starts while another backup is still running waits for its
turn (up to 12 hours).

Subcommands you can use in your own scripts:

```
proxdump backup --all                      # every guest on the node
proxdump backup 100 101                    # specific guests
proxdump backup --to gdrive --all          # one destination only
proxdump backup --to onedrive,gdrive 100   # several destinations
proxdump list                              # stored backups
proxdump prune                             # apply retention
proxdump keepalive                         # renew the tokens that can lapse
proxdump update                            # install the latest release
proxdump update --check                    # only tell whether one exists
```

Destinations are named `onedrive`, `gdrive`, `dropbox`, `s3` and `sftp`.
Without `--to`, every
configured destination is used; `list` and `prune` accept `--to` as well.

`update` compares this version with the latest release published on GitHub
and, if it is newer, installs it the way the tool was installed: the Debian
package of the release, checked against the SHA-256 digest that GitHub
publishes for it, or the archive of the release and its `install.sh`. It does
not run while a backup or a restore is in progress, and leaves a copy run
from a git clone to `git pull`. The configuration is not touched.

The menus check the latest release when they open (for at most 5 seconds)
and say in the title bar whether this is the latest version: *yes*,
*please update (x.y.z)*, or *unknown* when GitHub could not be reached.
When a newer release exists, the main menu offers **U – Update proxdump**,
which does the same as `proxdump update`, shows what it prints, then
reopens the menus with the new version.

`backup` returns the number of failures as its exit status (0 = everything
succeeded). A lock prevents two operations from running at the same time:
`backup` waits for the operation in progress, the other subcommands give up.
