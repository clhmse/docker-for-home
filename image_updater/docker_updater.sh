#!/bin/bash
# =====================================================
# Docker Compose Auto-Update + Self-Heal Script
# =====================================================

set -euo pipefail

COMPOSE_FILE="compose.yml"
BACKUP_DIR="/apps/backups"
PROJECT_NAME="unifi_pihole_unbound"
LOG_FILE="/apps/log/docker-auto-update.log"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
BACKUP_LOCATION="$BACKUP_DIR/$PROJECT_NAME/$TIMESTAMP"
PINNED_IMAGES_FILE="apps/pinned_images.txt"

CHECK_URLS=(
  # Pi-hole
  "http://localhost/admin"               # main web UI
  "http://localhost/admin/api.php"       # lightweight API endpoint

  # UniFi Controller
  "https://localhost:8443/manage"        # UniFi UI (HTTPS)
)

# Persistent data folders to back up
DATA_DIRS=($(grep '^[[:space:]]*-' "$COMPOSE_FILE" | grep ':' | sed 's/^[[:space:]]*-\s*//' | cut -d':' -f1 | grep '^/' | sort -u))

timestamp() { date +"%Y-%m-%d %H:%M:%S"; }

log() {
  echo "[$(timestamp)] $1" | tee -a "$LOG_FILE"
}

# 1. Create backup directory if missing
mkdir -p "$BACKUP_DIR/$PROJECT_NAME"
mkdir -p $BACKUP_LOCATION

# 2. Export current container list for rollback
log "Backing up current container images..."
docker-compose -f "$COMPOSE_FILE" ps --format '{{.Service}} {{.Image}}' > "$BACKUP_LOCATION/last_images.txt"


# 3. Backup persistent data (auto-detected)
log "Backing up persistent data from compose file..."
BACKUP_MAP="$BACKUP_LOCATION/data_paths.txt"
touch "$BACKUP_MAP"

for dir in "${DATA_DIRS[@]}"; do
  if [ -d "$dir" ]; then
    archive_name="$(echo "$dir" | sed 's#/#_#g').tar.gz"
    log "Archiving $dir → $archive_name"
    tar -czf "$BACKUP_LOCATION/$archive_name" -C / "$dir"
    echo "$archive_name:$dir" >> "$BACKUP_MAP"
  else
    log "Skipping non-directory path: $dir"
  fi
done


# 3. Pull latest images (respect pinned images)
log "Pulling latest images..."

PINNED_IMAGES_FILE="/apps/updates/pinned_images.txt"  # path to your pinned list

# Create the file if it doesn't exist to avoid errors
touch "$PINNED_IMAGES_FILE"

# Extract image names from compose file (docker-compose v2 syntax compatible)
IMAGES=$(docker-compose -f "$COMPOSE_FILE" config | awk '/image:/ {print $2}')

for image in $IMAGES; do
  if grep -q "^${image}$" "$PINNED_IMAGES_FILE"; then
    log "Skipping pinned image: $image"
  else
    log "Pulling image: $image"
    if ! docker pull "$image"; then
      log "Failed to pull $image — continuing to next."
    fi
  fi
done


# 4. Bring up updated containers
log "Deploying updated containers..."
if ! docker-compose -f "$COMPOSE_FILE" up -d --remove-orphans; then
  log "Deployment failed — rolling back..."
  docker-compose -f "$COMPOSE_FILE" down
  while read -r service image; do
    docker pull "$image" || true
  done < "$BACKUP_LOCATION/last_images.txt"
  docker-compose -f "$COMPOSE_FILE" up -d
  log "Rollback complete."
  exit 1
fi

# 5. Health check (optional but recommended)
sleep 20  # give services a few seconds to start

if curl -fs "$CHECK_URL" >/dev/null 2>&1; then
  log "Health check passed — update successful!"
else
  log "Health check failed — rolling back to previous images and data..."

  docker-compose -f "$COMPOSE_FILE" down

  # --- Restore persistent data ---
  BACKUP_MAP="$BACKUP_LOCATION/data_paths.txt"
  if [ -f "$BACKUP_MAP" ]; then
    log "Restoring persistent data from $BACKUP_MAP..."
    while IFS=: read -r archive dest; do
      archive_path="$BACKUP_LOCATION/$archive"
      if [ -f "$archive_path" ]; then
        log "Restoring $dest from $archive"
        mkdir -p "$dest"
        tar -xzf "$archive_path" -C /
      else
        log "Missing archive for $dest"
      fi
    done < "$BACKUP_MAP"
  else
    log "No data_paths.txt found — skipping data restore."
  fi

  # --- Restore previous container images ---
  if [ -f "$BACKUP_LOCATION/last_images.txt" ]; then
    while read -r service image; do
      docker pull "$image" || true
    done < "$BACKUP_LOCATION/last_images.txt"
  else
    log "No image list found — skipping image rollback."
  fi

  docker-compose -f "$COMPOSE_FILE" up -d
  log "Rollback completed after failed update."
fi

log "Update process complete."

