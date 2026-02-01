# critical-sync

a small management script that creates backups of critical data using a marker..

It scans through one or more source directories for the `!critical` marker file, and for every folder that contains the marker, it mirrors the folder recursively onto either local or remote backup targets. Mirroring is done with `rsync` so changes, including deletions, are propogated to all backup targets.

## How to use

Create a file named exactly `!critical` inside the folder to be backed up:

```bash
touch /path/to/critical/dir/!critical
```

For each critical folder, the script preserves the path inside the backup target:

```bash
/source_folder/path/to/critical_folder
```

becomes

```bash
backup_folder/path/to/critical_folder
```

## Features

- Mutiple source folders
- Multiple local targets
- Multiple remote targets
- Interactive config wizard `--init`
- Lockfile preventing overlapping runs
- Optional checksum mode
- Exclude lists
- `--dry-run` which doesnt do any backup, but shows you what would happen

## Configuration

Config is stored at:

```bash
~/.config/critical-sync/critical-sync.conf
```

And config can be generated using the interactive wizard:

```bash
critical-sync --init
```

Which will prompt you for:
- all source folders
- all local backup targets (warns if backup is on the same filesystem as source)
- all remote backup targets (user@host, with destination directory on the target)
- to install the script to your PATH
- to create a systemd timer

## SSH setup for remote backups

Remote backups require key-based SSH auth, because the script runs in non-interactive “batch mode” and will not prompt for passwords.

1) Generate a key on the NAS (as your normal user)

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ''
```

2) Install the public key on the remote target

```bash
ssh-copy-id user@remote-host
```

3) Verify

```bash
ssh -o BatchMode=yes user@remote-host 'echo ok'
```

If the verification prints `ok`, then remote backups should work. 
