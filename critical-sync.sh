#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# CONFIG

# Folders to scan for "!critical" marker files.
SOURCES=(
  "/mnt/storage"
  "/mnt/media"
)

# Where your backup disks are mounted
BACKUP_DISK_MOUNT="/home/\!critical"          # second backup disk mountpoint
BOOT_DISK_DEST="/var/\!critical"             # lives on the NAS boot disk

# Remote PC target 
PC_SSH="t@tpc"                       # user@host
PC_DEST='~/\!critical'                    # remote folder

# Exclude patterns you never want to copy
EXCLUDES=(
  ".Trash*"
  "@eaDir"
  ".DS_Store"
)

# How aggressive to be:
#   0 = rsync default (size+mtime)
#   1 = checksum comparison (slower but more certain)
USE_CHECKSUM=1


# INTERNALS
BACKUP2_DEST="${BACKUP_DISK_MOUNT}/!critical"
BOOT_DEST="${BOOT_DISK_DEST}/!critical"
LOCKFILE="/var/lock/critical-sync.lock"
LOGFILE="/var/log/critical-sync.log"

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1" >&2; exit 2; }; }

need_cmd find
need_cmd rsync
need_cmd flock
need_cmd ssh

# Lock so two runs don't overlap
mkdir -p "$(dirname "$LOCKFILE")"
exec 9>"$LOCKFILE"
flock -n 9 || exit 0

# Basic sanity: ensure backup disk is mounted
if ! mountpoint -q "$BACKUP_DISK_MOUNT"; then
  echo "ERROR: $BACKUP_DISK_MOUNT is not mounted" >&2
  exit 3
fi

# Ensure local target roots exist
mkdir -p "$BACKUP2_DEST" "$BOOT_DEST"

# Build rsync options
RSYNC_OPTS=(
  -aHAX --numeric-ids
  --delete --delete-delay
  --partial --delay-updates
  --mkpath
)

(( USE_CHECKSUM == 1 )) && RSYNC_OPTS+=( --checksum )
(( DRY_RUN == 1 )) && RSYNC_OPTS+=( --dry-run )

# Add excludes
for pat in "${EXCLUDES[@]}"; do
  RSYNC_OPTS+=( "--exclude=$pat" )
done

# Logging helper
log() {
  local msg="[$(date -Is)] $*"
  echo "$msg" | tee -a "$LOGFILE"
}

# Collect unique directories containing "!critical"
declare -A CRIT_DIRS=()   # dir -> source_root
for root in "${SOURCES[@]}"; do
  root="${root%/}"
  if [[ ! -d "$root" ]]; then
    log "WARN: source root missing: $root"
    continue
  fi

  # -xdev prevents crossing into other mounted filesystems under the root
  while IFS= read -r -d '' marker; do
    dir="$(dirname "$marker")"
    CRIT_DIRS["$dir"]="$root"
  done < <(find "$root" -xdev -type f -name '!critical' -print0)
done

if (( ${#CRIT_DIRS[@]} == 0 )); then
  log "No !critical markers found. Nothing to do."
  exit 0
fi

# Ensure remote destination exists (dont fail the whole run if PC is offline)
REMOTE_OK=1
if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$PC_SSH" "mkdir -p $PC_DEST" >/dev/null 2>&1; then
  REMOTE_OK=0
  log "WARN: remote PC unreachable; will skip remote sync this run."
fi

sync_one() {
  local src_dir="$1"
  local src_root="$2"

  local root_tag rel
  root_tag="$(basename "$src_root")"

  if [[ "$src_dir" == "$src_root" ]]; then
    rel="__ROOT__"
  else
    rel="${src_dir#"$src_root"/}"
  fi

  local dst_backup2="${BACKUP2_DEST}/${root_tag}/${rel}"
  local dst_boot="${BOOT_DEST}/${root_tag}/${rel}"
  local dst_pc="${PC_DEST}/${root_tag}/${rel}"

  log "SYNC: $src_dir"
  log "  -> backup2: $dst_backup2"
  if ! rsync "${RSYNC_OPTS[@]}" -- "$src_dir/" "$dst_backup2/"; then
    log "ERROR: rsync to backup2 failed for $src_dir"
  fi

  log "  -> boot:    $dst_boot"
  if ! rsync "${RSYNC_OPTS[@]}" -- "$src_dir/" "$dst_boot/"; then
    log "ERROR: rsync to boot disk failed for $src_dir"
  fi

  if (( REMOTE_OK == 1 )); then
    log "  -> pc:      $PC_SSH:$dst_pc"
    if ! rsync -e "ssh -o BatchMode=yes" "${RSYNC_OPTS[@]}" -- "$src_dir/" "$PC_SSH:$dst_pc/"; then
      log "ERROR: rsync to remote PC failed for $src_dir"
    fi
  fi
}

log "Run started (dry_run=$DRY_RUN checksum=$USE_CHECKSUM). Found ${#CRIT_DIRS[@]} critical folder(s)."

for dir in "${!CRIT_DIRS[@]}"; do
  sync_one "$dir" "${CRIT_DIRS[$dir]}"
done

log "Run finished."
