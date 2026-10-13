# proxdump

**Encrypted** backup of the virtual machines and containers of a
**Proxmox VE** node to **Microsoft OneDrive**, **Google Drive**,
**Dropbox**, any **S3-compatible storage** (Backblaze B2, Cloudflare R2,
Wasabi, Amazon S3, MinIO…) or an **SFTP server**, driven by `whiptail` menus.

- backs up VMs (QEMU) and containers (LXC) with `vzdump`;
- encrypts the contents on the server *before* upload; file names stay
  legible and carry an `.encrypted` suffix;
- one archive can be uploaded to several destinations in the same run;
- progress and results displayed in dialogs, for `vzdump` and for the
  transfers alike;
- credentials and passphrase are stored locally for subsequent runs;
- manages the backups already uploaded: list, delete, number of versions
  kept (global or per guest);
- restores under the original ID, under a new ID, or simply downloads;
- cron scheduling and non-interactive subcommands.

```
┌───────────────────────── proxdump 1.0.0 ──────────────────────────┐
│ Encrypted backup of Proxmox VE to cloud storage (node: pve)       │
│                                                                   │
│        1  Back up virtual machines and containers                 │
│        2  Restore a backup                                        │
│        3  Manage the stored backups                               │
│        4  Automatic scheduling                                    │
│        5  Configuration                                           │
│        6  Log                                                     │
│                                                                   │
│                  <Ok>                    <Quit>                   │
└───────────────────────────────────────────────────────────────────┘
```

## Contents

1. [How it works](#how-it-works)
2. [Requirements](#requirements)
3. [Installation](#installation)
4. [Initial configuration](#initial-configuration)
5. [Backing up](#backing-up)
6. [Managing the stored backups](#managing-the-stored-backups)
7. [Restoring](#restoring)
8. [Disaster recovery](#disaster-recovery-server-lost)
9. [Scheduling and command line](#scheduling-and-command-line)
10. [Files and security](#files-and-security)
11. [Troubleshooting](#troubleshooting)
12. [Known limitations](#known-limitations)
13. [Development and testing](#development-and-testing)

## How it works

```
 guest (VM/CT)                 local staging folder             destination(s)
┌─────────────┐   vzdump     ┌─────────────────────────┐  rclone  ┌──────────────────────┐
│ 100 web     │ ───────────▶ │ vzdump-qemu-100-….vma.zst│ ──────▶ │ pve-backups/<node>/  │
└─────────────┘              │ (plaintext, deleted after)│  crypt │  ….vma.zst.encrypted │
                             └─────────────────────────┘          └──────────────────────┘
```

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

## Requirements

- a Proxmox VE node (developed and tested on PVE 9 / Debian 13), root access;
- at least one destination with enough space: a Microsoft OneDrive
  account (personal or business), a Google account, a Dropbox account, a
  bucket on an S3-compatible service, or an account on an SFTP server;
- a local folder that can temporarily hold the largest archive;
- for the first connection to OneDrive, Google Drive or Dropbox: a computer
  with a web browser and [rclone](https://rclone.org/downloads/) (Windows,
  macOS or Linux). S3 and SFTP need nothing else than their keys.

Dependencies installed by `install.sh` if missing: `rclone` (official
package, Debian's being too old for OneDrive), `jq`, `whiptail`, `curl`.

## Installation

```bash
git clone https://github.com/Mrdindon/proxdump.git
cd proxdump
./install.sh
```

The script copies the tool to `/usr/local/bin/proxdump` and creates
`/etc/proxdump` (mode 700). To update: `git pull && ./install.sh`.
To remove: `./install.sh --uninstall` (the configuration is kept).

## Initial configuration

Run `proxdump` as root and open **Configuration**. Three steps: connect
at least one destination (as many as you wish), define the
encryption passphrase, and review the folders and options.

### 1. OneDrive connection

proxdump reaches OneDrive through [rclone](https://rclone.org/). Microsoft
only grants access through a sign-in page in a web browser, and a Proxmox
server has none. The authorization is therefore performed **once, on another
computer**, which produces a *token*; that token is then pasted into
proxdump on the server.

```
 Your computer (browser + rclone)                Proxmox server (proxdump)
 ────────────────────────────────                ────────────────────────────
 rclone authorize "onedrive"
   └─ browser: Microsoft sign-in, "Accept"
   └─ terminal: prints the token   ──── copy / paste ────►  Token > …
                                                            drive selection
                                                            connection test
```

#### Before you start

- A computer with a web browser (Windows, macOS or Linux) on which you can
  install rclone.
- The Microsoft account that will hold the backups (personal, or work/school).
- A terminal on the Proxmox server that accepts pasted text: an SSH session
  is the most convenient. The Proxmox web console also works, but pasting a
  long text into it is less reliable.

#### Step 1 — Install rclone on your computer

| System | Command |
|---|---|
| Windows | `winget install Rclone.Rclone`, or download the zip from <https://rclone.org/downloads/> and run `rclone.exe` from its folder |
| macOS | `brew install rclone` |
| Linux | `sudo -v ; curl https://rclone.org/install.sh \| sudo bash` |

Prefer the same version as on the server; the authorization screen of
proxdump displays it (`rclone version` shows yours). Nothing has to be
configured in rclone on your computer.

#### Step 2 — Start the guided configuration on the server

Run `proxdump`, then **Configuration → OneDrive connection → Guided
configuration**. The tool displays the instructions below and waits at the
`Token >` prompt. Leave it there.

#### Step 3 — Authorize on your computer

In a terminal on your computer (PowerShell on Windows), run:

```
rclone authorize "onedrive"
```

Your browser opens on the Microsoft sign-in page; if it does not, open the
`http://127.0.0.1:53682/auth…` address that rclone displays. Sign in with
the account that will hold the backups and accept the permissions requested
by rclone (read and write your files, and keep that access). The browser
then shows **Success!** and can be closed.

#### Step 4 — Copy the token to the server

Back in the terminal of your computer, rclone has displayed:

```
Paste the following into your remote machine --->
{"access_token":"EwB…","token_type":"Bearer","refresh_token":"M.C5…","expiry":"2026-…"}
<---End paste
```

Copy the whole block between the two markers (it is one very long line,
from `{` to `}`) and paste it at the `Token >` prompt on the server.

- Line breaks added by the terminal, and the markers themselves if they were
  copied too, are ignored.
- An incomplete token is detected and asked for again.
- If pasting does not work, save the block to a file, copy the file to the
  server (`scp token.txt root@server:/root/`) and enter its path at the
  prompt instead. Delete the file afterwards.
- Pressing Enter on an empty line cancels; the previous connection, if any,
  is kept.

> The token gives access to the files of the account: treat it as a
> password. Do not send it by e-mail or leave it in a file.

#### Step 5 — Select the drive

The tool then relays rclone's questions:

1. the account type: choose `onedrive` for a personal or a work/school
   OneDrive;
2. the drive: Microsoft's technical drives are filtered out, and the question
   is skipped when a single drive remains;
3. a final confirmation showing the drive that was found.

#### Step 6 — Connection test

The tool ends with a test that displays the total and free space of the
account. It can be run again at any time with **Configuration → Test the
connections**.

The token is saved in `/etc/proxdump/rclone.conf`, readable by root only,
and rclone renews it automatically. The authorization only has to be redone
if access is withdrawn or if the token goes unused for more than 90 days.

Special cases (SharePoint library, your own Azure application…): choose
**Manual rclone configuration** instead and create a remote named `onedrive`.

#### Replacing or removing the connection

Once a connection exists, **Configuration → OneDrive connection** offers:

- **Replace the connection**: repeats the steps above, for instance to sign
  in again or to use another account;
- **Remove the connection from this server**: deletes the token stored in
  `rclone.conf`. The backups on OneDrive and the encryption passphrase are
  kept; scheduled backups fail until a connection is configured again.

Removing the connection erases the token from the server, but the
authorization granted to rclone stays registered with Microsoft. To withdraw
it as well, remove `rclone` from the applications authorized on the account:

- personal account: <https://account.microsoft.com/privacy/app-access>;
- work or school account: <https://myapps.microsoft.com>.

Withdrawing it there invalidates every rclone token of that account,
including the one used by another server.

### 1b. Google Drive connection

**Configuration → Google Drive connection → Guided configuration** follows
the same principle as OneDrive: the authorization is granted in a browser on
another computer and the token is pasted on the server. One preliminary step
is specific to Google: creating an OAuth client.

#### Create your OAuth client (once)

Google Drive is accessed through an OAuth client that you create in your own
Google Cloud project. It is free and only identifies "your copy of rclone"
to Google.

The guided configuration displays these steps on screen and waits for the
two values they produce.

1. Open <https://console.cloud.google.com/> and sign in to a Google account
   (it does not have to be the one that holds the Drive). Create a project:
   **Select a project → New project**, any name.
2. **APIs & Services → Library**: search for **Google Drive API**, open it
   and click **Enable**.
3. **APIs & Services → OAuth consent screen → Get started**: enter an
   application name (for instance `rclone`) and your e-mail address, choose
   the audience **External**, accept the terms and click **Create**.
4. **Data Access → Add or remove scopes**: tick the scope ending in
   `/auth/drive`, then **Update** and **Save**.
5. **Branding**: Google only lets you publish once this page is complete.
   Fill in **Application home page** and **Application privacy policy
   link** with addresses of a domain of yours (for instance
   `https://example.org` and `https://example.org/privacy`), add that
   domain under **Authorized domains**, then **Save**. Google may then
   report that the branding could not be verified (pages unreachable, domain
   not registered to you): ignore it and do not request a re-verification.
   That check only decides whether your application name is shown to users;
   publishing works without it.
6. **Audience → Publish app → Confirm**. A published application needs no
   test users, and its authorization does not expire; left in *Testing*,
   Google cancels the authorization after 7 days and the backups stop.
7. **Clients → Create client**: application type **Desktop app**, then
   **Create**. Google displays the **client ID** (ending in
   `.apps.googleusercontent.com`) and the **client secret**.

There is no need to add test users: the console may even refuse your own
address ("Ineligible accounts not added"), which is of no consequence once
the application is published.

At sign-in, Google then shows an "unverified app" warning (**Advanced → Go
to rclone**): this is expected for a personal client and needs no
verification.

Google renames these menus from time to time; the reference procedure, kept
up to date by the rclone project, is at
<https://rclone.org/drive/#making-your-own-client-id>.

#### Connect

1. Start the guided configuration; at the `Client ID >` and
   `Client secret >` prompts, enter the two values obtained above.
2. The authorization screen displays the exact command to run on your
   computer. Unlike OneDrive, it carries a second argument that encodes your
   client, so copy it as displayed:
   ```
   rclone authorize "drive" "eyJjbGllbnRfaWQiOi…"
   ```
3. Sign in to Google in the browser, accept, then paste the token on the
   server, exactly as in steps 3 and 4 of the OneDrive procedure.
4. The tool asks whether to configure a Shared Drive (answer No for a
   personal drive), then tests the connection.

Replacing and removing the connection work as for OneDrive. To withdraw the
authorization on Google's side: <https://myaccount.google.com/connections>.

### 1c. Dropbox connection

**Configuration → Dropbox connection → Guided configuration** works exactly
like OneDrive, without the drive selection: run on your computer the command
displayed (`rclone authorize "dropbox"`), sign in to Dropbox in the browser,
then paste the token on the server. To withdraw the authorization on
Dropbox's side: <https://www.dropbox.com/account/connected_apps>.

### 1d. S3-compatible storage

No browser is involved: the connection uses an access key created in the
console of the provider. **Configuration → S3 storage connection** asks for:

| Question | What to enter |
|---|---|
| Provider | Backblaze B2, Cloudflare R2, Wasabi, Amazon S3, Hetzner, OVHcloud, Scaleway, MinIO, or another S3-compatible service |
| Endpoint | The address of the service, shown by the provider next to the bucket (not asked for Amazon S3) |
| Region | Required for Amazon S3; otherwise only if the provider asks for one |
| Access key ID and secret access key | A key allowed to read, write and delete in the bucket |
| Bucket | The name of a bucket that **already exists**; the tool does not create it |

With **Backblaze B2**: create the bucket (private), then under
**Application Keys** add a key restricted to that bucket with *Read and
Write* access. The *keyID* is the access key ID, the *applicationKey* is the
secret access key, and the endpoint is displayed on the bucket
(`s3.<region>.backblazeb2.com`).

The tool then lists the bucket to check the settings; settings that do not
work are discarded unless you ask to keep them. The backups are stored in
the bucket under the folder defined in **Folder on the destinations**.

### 1e. SFTP server

For a NAS, another server of yours, or SFTP storage rented from a hosting
provider. **Configuration → SFTP server connection** asks for the host, the
SSH port and the user name, then:

1. **Host keys.** The tool displays the fingerprints presented by the
   server. Once accepted they are recorded in
   `/etc/proxdump/sftp_known_hosts`, and a server that later presents
   other keys is refused.
2. **Sign-in method.**
   - *SSH key dedicated to this tool* (recommended): a key is generated in
     `/etc/proxdump/sftp_key` and its public half is displayed. Add that
     line to `~/.ssh/authorized_keys` of the account on the server (or
     through the provider's control panel), then press Enter.
   - *Password*: stored obscured in `rclone.conf`.
3. **Folder.** Where the backups go on the server: a path relative to the
   home folder of the account, or an absolute path. It is created if
   necessary.

After each upload the archive is compared with its source by checksum. A
server that offers no shell (and therefore no `md5sum`) only allows the
sizes to be compared; the log says which of the two was done.

### Keeping the access tokens alive

The connections made through a browser rely on a token that the provider
cancels when it stays unused for too long:

| Destination | The token lapses after |
|---|---|
| OneDrive | 90 days without use |
| Google Drive | 6 months without use |
| Dropbox, S3, SFTP | never (until the access is withdrawn) |

A destination that is backed up to regularly is never concerned. For one
that is used occasionally, open its entry in **Configuration** and enable
**Daily token refresh**: a daily cron task (12:17) queries the account for
the sole purpose of renewing the token. It transfers no data and records
its result in the log. The option only appears for OneDrive and Google
Drive. Neither provider lets the remaining lifetime of a token be queried.

### 2. Encryption

A single passphrase protects every destination.

**Configuration → Encryption** offers to generate a random passphrase
(recommended) or to enter your own.

> **Write this passphrase down off the server** (password manager, paper).
> It is required to restore if this server is lost. Without it, the backups
> are permanently unreadable — nobody, not even Microsoft, can decrypt them.

The same menu lets you display the passphrase again later, or change it.
Note: existing backups remain encrypted with the old passphrase.

#### File names

rclone's `crypt` encrypts the contents of every file (XSalsa20-Poly1305,
256-bit key). The names are left as they are, followed by `.encrypted`, so
the OneDrive folder stays easy to browse:
`100_web/vzdump-qemu-100-….vma.zst.encrypted`. Guest IDs, guest names,
backup dates, file sizes and upload dates are therefore visible to anyone
with access to the OneDrive account.

An installation made with an earlier version, which could encrypt the names,
is detected when the menus open: the tool offers to rename the existing
backups in place, without uploading them again.

### 3. Folders and options

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

## Disaster recovery (server lost)

You need: access to the destination (the account, or the S3 or SFTP
credentials) and the **passphrase**.

1. Install Proxmox VE on the new server, then proxdump (`./install.sh`).
2. **Configuration → … connection** for the destination that holds the
   backups: redo the authorization, or enter the same bucket or folder.
3. **Configuration → Folder on the destinations**: enter the old server's folder, e.g.
   `pve-backups/old-name` (the default uses the new node's name).
4. **Configuration → Encryption → Enter a passphrase**: enter the
   original passphrase.
5. **Manage → List the backups**: the backups should appear. If the list is
   empty although the folder contains files, the passphrase or the folder
   is wrong.
6. **Restore** each guest.

Without this tool, with any rclone, the same thing by hand:

```ini
# rclone.conf
[onedrive]
type = onedrive
# … created by "rclone config"

[onedrive-crypt]
type = crypt
remote = onedrive:pve-backups/<node>
password = <output of: rclone obscure 'your passphrase'>
filename_encryption = off
directory_name_encryption = false
suffix = .encrypted
```

For S3 the `remote` line is `s3:<bucket>/pve-backups/<node>`, and for SFTP
`sftp:<folder>/pve-backups/<node>`.

```bash
rclone lsf -R onedrive-crypt:
rclone copy onedrive-crypt:100_web/vzdump-qemu-100-….vma.zst /var/lib/vz/dump/
qmrestore /var/lib/vz/dump/vzdump-qemu-100-….vma.zst 100 --storage local-lvm
```

**Test a restore** (under a new ID) from time to time: a backup that has
never been restored is only a hope.

## Scheduling and command line

Menu **4 – Automatic scheduling** lists the schedules and lets you add or
remove them. Selecting a schedule also offers **Run this schedule now**,
which backs up its guests immediately, with the progress on screen, without
changing the schedule. Several schedules can coexist, for instance a daily one for a
critical guest and a weekly one for everything. Each schedule defines:

- the destinations, among those that are configured (the question is
  skipped when there is only one);
- the frequency: daily, or weekly on a given day;
- the start time (HH:MM);
- the guests: either **all guests on the node**, which includes those added
  later, or **a selection** of guests.

The schedules are stored in `/etc/cron.d/proxdump`, one line each. A
schedule that starts while another backup is still running waits for its
turn (up to 12 hours).

Subcommands you can use in your own scripts:

```
proxdump backup --all       # every guest on the node
proxdump backup 100 101     # specific guests
proxdump backup --to gdrive --all            # one destination only
proxdump backup --to onedrive,gdrive 100     # several destinations
proxdump list               # stored backups
proxdump prune              # apply retention
proxdump keepalive          # renew the tokens that can lapse (see above)
```

Destinations are named `onedrive`, `gdrive`, `dropbox`, `s3` and `sftp`.
Without `--to`, every
configured destination is used; `list` and `prune` accept `--to` as well.

`backup` returns the number of failures as its exit status (0 = everything
succeeded). A lock prevents two operations from running at the same time:
`backup` waits for the operation in progress, the other subcommands give up.

## Files and security

| File | Contents | Permissions |
|---|---|---|
| `/usr/local/bin/proxdump` | The tool | 755 |
| `/etc/proxdump/rclone.conf` | **Access tokens, S3 keys, SFTP password and passphrase** | 600, folder 700 |
| `/etc/proxdump/sftp_key` | **Private SSH key** used for the SFTP server | 600 |
| `/etc/proxdump/sftp_known_hosts` | Host keys of the SFTP server | 600 |
| `/etc/proxdump/config` | Settings (no secrets) | 600 |
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
- The interface is in English only for now.

## Development and testing

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

## License

MIT — see [LICENSE](LICENSE).
