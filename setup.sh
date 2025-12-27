#!/usr/bin/env bash
set -euo pipefail

echo "=== MediaBlade stack setup ==="
read -rp "Enter root path for MediaBlade (e.g. /srv/mediablade): " ROOT

if [ -z "$ROOT" ]; then
  echo "Root path cannot be empty."
  exit 1
fi

echo "Using MediaBlade root: $ROOT"

echo "Creating directory tree..."
mkdir -p \
  "$ROOT/media/movies" \
  "$ROOT/media/tv" \
  "$ROOT/downloads/incomplete" \
  "$ROOT/downloads/complete" \
  "$ROOT/downloads/jackett" \
  "$ROOT/tdarr_cache" \
  "$ROOT/traefik/letsencrypt"

echo "Directories created under $ROOT:"
find "$ROOT" -maxdepth 3 -type d

COMPOSE_FILE="$ROOT/docker-compose.yml"
ENV_FILE="$ROOT/.env"

if [ ! -f "$ENV_FILE" ]; then
  TZ_VALUE="Etc/UTC"
  if [ -f /etc/timezone ]; then
    TZ_VALUE="$(tr -d '\n' < /etc/timezone || echo 'Etc/UTC')"
  fi

  cat > "$ENV_FILE" <<EOF
# MediaBlade generated defaults (edit as needed)
BIND_IP=127.0.0.1
TZ=${TZ_VALUE}
MEDIABLADE_UID=$(id -u)
MEDIABLADE_GID=$(id -g)

# Optional: Traefik reverse proxy
TRAEFIK_ENABLE=false
LETSENCRYPT_EMAIL=you@example.com
JELLYFIN_HOST=jellyfin.example.com
MEDIAMANAGER_HOST=mediamanager.example.com
WIZARR_HOST=wizarr.example.com

# Optional: Tdarr NVIDIA GPU
TDARR_NVIDIA_GPUS=0
EOF

  echo "Wrote $ENV_FILE (recommended: keep BIND_IP=127.0.0.1 unless you add a proxy)."
fi

echo "Writing docker-compose.yml to $COMPOSE_FILE ..."

cat > "$COMPOSE_FILE" <<EOF
name: mediablade

x-logging: &default-logging
  driver: json-file
  options:
    max-size: \${LOG_MAX_SIZE:-10m}
    max-file: "\${LOG_MAX_FILE:-3}"

x-security: &default-security
  init: true
  security_opt:
    - no-new-privileges:true
  cap_drop:
    - ALL
  restart: unless-stopped
  logging: *default-logging

networks:
  media:
    driver: bridge
  proxy:
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
  traefik:
    image: traefik:v3.3
    profiles: ["proxy"]
    container_name: mediablade-traefik
    networks: [proxy]
    ports:
      - "\${TRAEFIK_BIND_IP:-0.0.0.0}:80:80"
      - "\${TRAEFIK_BIND_IP:-0.0.0.0}:443:443"
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--providers.docker.network=\${TRAEFIK_DOCKER_NETWORK:-mediablade_proxy}"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.\${TRAEFIK_CERTRESOLVER:-le}.acme.email=\${LETSENCRYPT_EMAIL}"
      - "--certificatesresolvers.\${TRAEFIK_CERTRESOLVER:-le}.acme.storage=/letsencrypt/acme.json"
      - "--certificatesresolvers.\${TRAEFIK_CERTRESOLVER:-le}.acme.tlschallenge=true"
      - "--api.dashboard=\${TRAEFIK_DASHBOARD:-false}"
      - "--log.level=\${TRAEFIK_LOG_LEVEL:-INFO}"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ${ROOT}/traefik/letsencrypt:/letsencrypt
    <<: *default-security

  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: mediablade-jellyfin
    networks: [media, proxy]
    user: "\${MEDIABLADE_UID:-1000}:\${MEDIABLADE_GID:-1000}"
    environment:
      - TZ=\${TZ:-Etc/UTC}
    volumes:
      - jellyfin_config:/config
      - jellyfin_cache:/cache
      - ${ROOT}/media:/media
    ports:
      - "\${BIND_IP:-127.0.0.1}:8096:8096"
    labels:
      - "traefik.enable=\${TRAEFIK_ENABLE:-false}"
      - "traefik.docker.network=\${TRAEFIK_DOCKER_NETWORK:-mediablade_proxy}"
      - "traefik.http.routers.jellyfin.rule=Host(\`\${JELLYFIN_HOST:-jellyfin.local}\`)"
      - "traefik.http.routers.jellyfin.entrypoints=\${TRAEFIK_ENTRYPOINTS:-websecure}"
      - "traefik.http.routers.jellyfin.tls=\${TRAEFIK_TLS:-true}"
      - "traefik.http.routers.jellyfin.tls.certresolver=\${TRAEFIK_CERTRESOLVER:-le}"
      - "traefik.http.services.jellyfin.loadbalancer.server.port=8096"
    <<: *default-security

  jackett:
    image: lscr.io/linuxserver/jackett:latest
    container_name: mediablade-jackett
    networks: [media]
    environment:
      - PUID=\${MEDIABLADE_UID:-1000}
      - PGID=\${MEDIABLADE_GID:-1000}
      - TZ=\${TZ:-Etc/UTC}
    volumes:
      - jackett_config:/config
      - ${ROOT}/downloads/jackett:/downloads
    ports:
      - "\${BIND_IP:-127.0.0.1}:9117:9117"
    <<: *default-security

  rdtclient:
    image: rogerfar/rdtclient:latest
    container_name: mediablade-rdtclient
    networks: [media]
    environment:
      - PUID=\${MEDIABLADE_UID:-1000}
      - PGID=\${MEDIABLADE_GID:-1000}
      - TZ=\${TZ:-Etc/UTC}
    volumes:
      - rdtclient_config:/data/db
      - ${ROOT}/downloads:/data/downloads
    ports:
      - "\${BIND_IP:-127.0.0.1}:6500:6500"
    <<: *default-security

  flaresolverr:
    image: ghcr.io/flaresolverr/flaresolverr:latest
    container_name: mediablade-flaresolverr
    networks: [media]
    environment:
      - LOG_LEVEL=info
      - LOG_HTML=false
      - CAPTCHA_SOLVER=none
      - TZ=\${TZ:-Etc/UTC}
    ports:
      - "\${BIND_IP:-127.0.0.1}:8191:8191"
    <<: *default-security

  bazarr:
    image: lscr.io/linuxserver/bazarr:latest
    container_name: mediablade-bazarr
    networks: [media]
    environment:
      - PUID=\${MEDIABLADE_UID:-1000}
      - PGID=\${MEDIABLADE_GID:-1000}
      - TZ=\${TZ:-Etc/UTC}
    volumes:
      - bazarr_config:/config
      - ${ROOT}/media:/media
    ports:
      - "\${BIND_IP:-127.0.0.1}:6767:6767"
    <<: *default-security

  tdarr:
    image: ghcr.io/haveagitgat/tdarr:latest
    container_name: mediablade-tdarr
    networks: [media]
    environment:
      - PUID=\${MEDIABLADE_UID:-1000}
      - PGID=\${MEDIABLADE_GID:-1000}
      - TZ=\${TZ:-Etc/UTC}
      - serverIP=0.0.0.0
      - serverPort=8266
      - webUIPort=8265
      - NVIDIA_DRIVER_CAPABILITIES=\${NVIDIA_DRIVER_CAPABILITIES:-compute,video,utility}
      - NVIDIA_VISIBLE_DEVICES=\${NVIDIA_VISIBLE_DEVICES:-}
    volumes:
      - tdarr_config:/app/configs
      - tdarr_logs:/app/logs
      - tdarr_server_config:/app/server
      - ${ROOT}/media:/media
      - ${ROOT}/tdarr_cache:/temp
    device_requests:
      - driver: nvidia
        count: \${TDARR_NVIDIA_GPUS:-0}
        capabilities: [gpu]
    ports:
      - "\${BIND_IP:-127.0.0.1}:8265:8265"
      - "\${BIND_IP:-127.0.0.1}:8266:8266"
    <<: *default-security

  mediamanager:
    image: ghcr.io/maxdorninger/mediamanager/mediamanager:latest
    container_name: mediablade-mediamanager
    networks: [media, proxy]
    environment:
      - TZ=\${TZ:-Etc/UTC}
    volumes:
      - mediamanager_config:/app/data
      - ${ROOT}/media:/media
    ports:
      - "\${BIND_IP:-127.0.0.1}:8787:8787"
    labels:
      - "traefik.enable=\${TRAEFIK_ENABLE:-false}"
      - "traefik.docker.network=\${TRAEFIK_DOCKER_NETWORK:-mediablade_proxy}"
      - "traefik.http.routers.mediamanager.rule=Host(\`\${MEDIAMANAGER_HOST:-mediamanager.local}\`)"
      - "traefik.http.routers.mediamanager.entrypoints=\${TRAEFIK_ENTRYPOINTS:-websecure}"
      - "traefik.http.routers.mediamanager.tls=\${TRAEFIK_TLS:-true}"
      - "traefik.http.routers.mediamanager.tls.certresolver=\${TRAEFIK_CERTRESOLVER:-le}"
      - "traefik.http.services.mediamanager.loadbalancer.server.port=8787"
    <<: *default-security

  wizarr:
    image: ghcr.io/wizarrrr/wizarr:latest
    container_name: mediablade-wizarr
    networks: [media, proxy]
    environment:
      - TZ=\${TZ:-Etc/UTC}
    volumes:
      - wizarr_config:/data
    ports:
      - "\${BIND_IP:-127.0.0.1}:5690:5690"
    labels:
      - "traefik.enable=\${TRAEFIK_ENABLE:-false}"
      - "traefik.docker.network=\${TRAEFIK_DOCKER_NETWORK:-mediablade_proxy}"
      - "traefik.http.routers.wizarr.rule=Host(\`\${WIZARR_HOST:-wizarr.local}\`)"
      - "traefik.http.routers.wizarr.entrypoints=\${TRAEFIK_ENTRYPOINTS:-websecure}"
      - "traefik.http.routers.wizarr.tls=\${TRAEFIK_TLS:-true}"
      - "traefik.http.routers.wizarr.tls.certresolver=\${TRAEFIK_CERTRESOLVER:-le}"
      - "traefik.http.services.wizarr.loadbalancer.server.port=5690"
    <<: *default-security
EOF

echo "docker-compose.yml created."
echo
echo "Next steps:"
echo "  cd \"$ROOT\""
echo "  # edit $ENV_FILE if needed"
echo "  docker compose up -d"
echo
echo "Optional reverse proxy:"
echo "  docker compose --profile proxy up -d"
