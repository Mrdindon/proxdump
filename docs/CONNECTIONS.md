# Connecting the destinations

[← proxdump](../README.md)

Run `proxdump` as root and open **Configuration**: each destination has its own entry. Connect at least one; an archive can be uploaded to several of them in the same run.

## OneDrive connection

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

### Before you start

- A computer with a web browser (Windows, macOS or Linux) on which you can
  install rclone.
- The Microsoft account that will hold the backups (personal, or work/school).
- A terminal on the Proxmox server that accepts pasted text: an SSH session
  is the most convenient. The Proxmox web console also works, but pasting a
  long text into it is less reliable.

### Step 1 — Install rclone on your computer

| System | Command |
|---|---|
| Windows | `winget install Rclone.Rclone`, or download the zip from <https://rclone.org/downloads/> and run `rclone.exe` from its folder |
| macOS | `brew install rclone` |
| Linux | `sudo -v ; curl https://rclone.org/install.sh \| sudo bash` |

Prefer the same version as on the server; the authorization screen of
proxdump displays it (`rclone version` shows yours). Nothing has to be
configured in rclone on your computer.

### Step 2 — Start the guided configuration on the server

Run `proxdump`, then **Configuration → OneDrive connection → Guided
configuration**. The tool displays the instructions below and waits at the
`Token >` prompt. Leave it there.

### Step 3 — Authorize on your computer

In a terminal on your computer (PowerShell on Windows), run:

```
rclone authorize "onedrive"
```

Your browser opens on the Microsoft sign-in page; if it does not, open the
`http://127.0.0.1:53682/auth…` address that rclone displays. Sign in with
the account that will hold the backups and accept the permissions requested
by rclone (read and write your files, and keep that access). The browser
then shows **Success!** and can be closed.

### Step 4 — Copy the token to the server

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

### Step 5 — Select the drive

The tool then relays rclone's questions:

1. the account type: choose `onedrive` for a personal or a work/school
   OneDrive;
2. the drive: Microsoft's technical drives are filtered out, and the question
   is skipped when a single drive remains;
3. a final confirmation showing the drive that was found.

### Step 6 — Connection test

The tool ends with a test that displays the total and free space of the
account. It can be run again at any time with **Configuration → Test the
connections**.

The token is saved in `/etc/proxdump/rclone.conf`, readable by root only,
and rclone renews it automatically. The authorization only has to be redone
if access is withdrawn or if the token goes unused for more than 90 days.

Special cases (SharePoint library, your own Azure application…): choose
**Manual rclone configuration** instead and create a remote named `onedrive`.

### Replacing or removing the connection

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

## Google Drive connection

**Configuration → Google Drive connection → Guided configuration** follows
the same principle as OneDrive: the authorization is granted in a browser on
another computer and the token is pasted on the server. One preliminary step
is specific to Google: creating an OAuth client.

### Create your OAuth client (once)

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

### Connect

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

## Dropbox connection

**Configuration → Dropbox connection → Guided configuration** works exactly
like OneDrive, without the drive selection: run on your computer the command
displayed (`rclone authorize "dropbox"`), sign in to Dropbox in the browser,
then paste the token on the server. To withdraw the authorization on
Dropbox's side: <https://www.dropbox.com/account/connected_apps>.

## S3-compatible storage

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

## SFTP server

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

## Keeping the access tokens alive

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
