# Disaster recovery

[← proxdump](../README.md)

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
