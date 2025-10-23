# Docker Image Updater
This repo allows you to automate image updates for your docker compose setups. Designed for health checks and alerting so it can run as a cron job.

# Usage:
COMPOSE_FILE="compose.yml"                                  : Path for your docker compose file
BACKUP_DIR="/apps/backups"                                  : Directory to back up any persistant data
PROJECT_NAME="unifi_pihole_unbound"                         : Name for your specific compose setup - set to anything memorable for you
LOG_FILE="/apps/log/docker-auto-update.log"                 : Logging for your update process
BACKUP_LOCATION="$BACKUP_DIR/$PROJECT_NAME/$TIMESTAMP"      : Backup storage for your docker setup - typically sets to the project and time
PINNED_IMAGES_FILE="$BACKUP_LOCATION/pinned_images.txt"     : Pin some images where compatability is an issue


# pinned_images.txt format
mongo:6.0.5
pihole/pihole:2024.04
linuxserver/unifi-controller:8.1.127
