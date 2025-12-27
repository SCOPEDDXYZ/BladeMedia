#!/usr/bin/env bash
set -e

echo "=== MediaBlade stack setup ==="
read -rp "Enter root path for MediaBlade (e.g. /srv/mediablade): " ROOT

if [ -z "$ROOT" ]; then
  echo "Root path cannot be empty."
  exit 1
fi

echo "Using MediaBlade root: $ROOT"

# Create directory structure
echo "Creating directory tree..."
mkdir -p \
  "$ROOT/media/movies" \
  "$ROOT/media/tv" \
  "$ROOT/downloads/incomplete" \
  "$ROOT/downloads/complete" \
  "$ROOT/downloads/jackett" \
  "$ROOT/tdarr_cache"

echo "Directories created under $ROOT:"
find "$ROOT" -maxdepth 3 -type d

COMPOSE_FILE="$ROOT/docker-compose.yml"

echo "Writing docker-compose.yml to $COMPOSE_FILE ..."

cat > "$COMPOSE_FILE" <<EOF
name: mediablade

networks:
  media:
    driver: bridge

volumes:
  jellyfin_cache:
  jellyfin_config:
  jackett_config:
  rdtclient_config:
  bazarr_config:
  tdarr_config:
  tdarr_logs:
  tdarr_server_config:
  mediamanager_config:
  wizarr_config:

services:

  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: mediablade-jellyfin
    networks:
      - media
    user: "\${MEDIABLADE_UID:-0}:\${MEDIABLADE_GID:-0}"
    environment:
      - TZ=\${TZ:-Etc/UTC}
    volumes:
      - jellyfin_config:/config
      - jellyfin_cache:/cache
      - ${ROOT}/media:/media
    ports:
      - "\${BIND_IP:-0.0.0.0}:8096:8096"
    restart: unless-stopped

  jackett:
    image: lscr.io/linuxserver/jackett:latest
    container_name: mediablade-jackett
    networks:
      - media
    environment:
      - PUID=\${MEDIABLADE_UID:-0}
      - PGID=\${MEDIABLADE_GID:-0}
      - TZ=\${TZ:-Etc/UTC}
    volumes:
      - jackett_config:/config
      - ${ROOT}/downloads/jackett:/downloads
    ports:
      - "\${BIND_IP:-0.0.0.0}:9117:9117"
    restart: unless-stopped

  rdtclient:
    image: rogerfar/rdtclient:latest
    container_name: mediablade-rdtclient
    networks:
      - media
    environment:
      - PUID=\${MEDIABLADE_UID:-0}
      - PGID=\${MEDIABLADE_GID:-0}
      - TZ=\${TZ:-Etc/UTC}
    volumes:
      - rdtclient_config:/data/db
      - ${ROOT}/downloads:/data/downloads
    ports:
      - "\${BIND_IP:-0.0.0.0}:6500:6500"
    restart: unless-stopped

  flaresolverr:
    image: ghcr.io/flaresolverr/flaresolverr:latest
    container_name: mediablade-flaresolverr
    networks:
      - media
    environment:
      - LOG_LEVEL=info
      - LOG_HTML=false
      - CAPTCHA_SOLVER=none
      - TZ=\${TZ:-Etc/UTC}
    ports:
      - "\${BIND_IP:-0.0.0.0}:8191:8191"
    restart: unless-stopped

  bazarr:
    image: lscr.io/linuxserver/bazarr:latest
    container_name: mediablade-bazarr
    networks:
      - media
    environment:
      - PUID=\${MEDIABLADE_UID:-0}
      - PGID=\${MEDIABLADE_GID:-0}
      - TZ=\${TZ:-Etc/UTC}
    volumes:
      - bazarr_config:/config
      - ${ROOT}/media:/media
    ports:
      - "\${BIND_IP:-0.0.0.0}:6767:6767"
    restart: unless-stopped

  tdarr:
    image: ghcr.io/haveagitgat/tdarr:latest
    container_name: mediablade-tdarr
    networks:
      - media
    environment:
      - PUID=\${MEDIABLADE_UID:-0}
      - PGID=\${MEDIABLADE_GID:-0}
      - TZ=\${TZ:-Etc/UTC}
      - serverIP=0.0.0.0
      - serverPort=8266
      - webUIPort=8265
    volumes:
      - tdarr_config:/app/configs
      - tdarr_logs:/app/logs
      - tdarr_server_config:/app/server
      - ${ROOT}/media:/media
      - ${ROOT}/tdarr_cache:/temp
    ports:
      - "\${BIND_IP:-0.0.0.0}:8265:8265"
      - "\${BIND_IP:-0.0.0.0}:8266:8266"
    restart: unless-stopped

  mediamanager:
    image: ghcr.io/maxdorninger/mediamanager/mediamanager:latest
    container_name: mediablade-mediamanager
    networks:
      - media
    environment:
      - TZ=\${TZ:-Etc/UTC}
      # Add any DB or auth-related environment variables you want here.
    volumes:
      - mediamanager_config:/app/data
      - ${ROOT}/media:/media
    ports:
      - "\${BIND_IP:-0.0.0.0}:8787:8787"
    restart: unless-stopped

  wizarr:
    image: ghcr.io/wizarrrr/wizarr:latest
    container_name: mediablade-wizarr
    networks:
      - media
    environment:
      - TZ=\${TZ:-Etc/UTC}
      # Example (override in compose if you want):
      # - APP_URL=https://your-domain
      # - INVITE_ONLY=true
      # - JELLYFIN_URL=http://jellyfin:8096
    volumes:
      - wizarr_config:/data
    ports:
      - "\${BIND_IP:-0.0.0.0}:5690:5690"
    restart: unless-stopped
EOF

echo "docker-compose.yml created."

echo
echo "Next steps:"
echo "  cd \"$ROOT\""
echo "  docker compose up -d"
echo
echo "Then configure:"
echo "  - Jellyfin libraries at /media/movies and /media/tv"
echo "  - MediaManager to scan /media"
echo "  - Wizarr to point at http://jellyfin:8096"
