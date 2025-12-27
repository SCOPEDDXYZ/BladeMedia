# MediaBlade
A simple & easy way to set up an automated Jellyfin-based media server.

*Created by Blade (@SCOPEDDDXYZ) with the help of AI.*


## Installation


## Method 1: Pure Docker Compose (No Organizer Script)
This docker-compose based setup script utilizes the following services:
- MediaManager (This is an all-in-one replacement for Radarr, Sonarr & Jellyseerr.)
- Jellyfin (My media server manager of choice. Open source, free & built by an awesome team.)
- Jackett (This will be your indexer. Similar to Prowlarr, but better in my opinion.)
- RDTClient (This is a Real-Debrid Torrent client that can be self-hosted & automated.)
- Flaresolverr (Auto-completes Cloudflare captcha's on captcha-protected indexers.)
- Bazarr (Searches & auto-downloads subtitles for all of the media in your library.)
- Tdarr (Automatically uses your GPU to transcode all of the media in your library. Can be used in a node-based system)
- Wizarr (Allows easy inviting to your Jellyfin instance. Also allows you to invite to Discord & introduce your requesting system.)

## Installation
Overall, this uses Docker Compose. I’ve provided two different ways to run this.

1. Plain old `docker-compose.yml` file.
You can run the services by grabbing `docker-compose.yml`, creating the folders (`media/`, `downloads/`, `tdarr_cache/`) next to it, then running `docker compose up -d`.

2. Automated installation script.
If you want to generate folders + `.env` automatically, use the AIO installer instead (Method 2).

## Updating
Updating the stack is simple. All you need to do is this:
- SSH or access the machine directly.
- Enter root user mode.
- Navigate to the directory in which your installation script created the docker-compose.yml file, then run this comamand: ```docker compose down```
- Once you've taken the stack down run this command: ```docker compose pull```
- After that you can run: ```docker compose up -d```
- And you're good to go! 

## Security defaults (important)
This repo is now set up with **safer defaults**:
- **Ports bind to localhost by default** (`BIND_IP=127.0.0.1`). This prevents exposing admin UIs to your LAN/Internet accidentally.
- **Containers run as a non-root UID/GID by default** (`MEDIABLADE_UID` / `MEDIABLADE_GID`).
- **Least-privilege container settings** are enabled (`no-new-privileges`, drop Linux capabilities, log rotation).

If you want LAN access without a reverse proxy, set `BIND_IP=0.0.0.0` in your `.env` (or bind to your LAN IP), and make sure you have a firewall in place.

## Configuration via `.env`
Copy the example and edit it:
- `cp .env.example .env`

Key settings:
- **`BIND_IP`**: `127.0.0.1` (safe default) vs `0.0.0.0` (expose)
- **`TZ`**: your timezone
- **`MEDIABLADE_UID` / `MEDIABLADE_GID`**: should match ownership of `./media` and `./downloads`

## Reverse proxy option (Traefik)
The compose includes an **optional Traefik v3** reverse proxy (with Let's Encrypt).

1. Set these in `.env`:
   - `LETSENCRYPT_EMAIL`
   - `TRAEFIK_ENABLE=true`
   - `JELLYFIN_HOST`, `MEDIAMANAGER_HOST`, `WIZARR_HOST`
2. Start Traefik:
   - `docker compose --profile proxy up -d`

If you already run a reverse proxy, you can ignore the Traefik service and just keep `BIND_IP=127.0.0.1`.

## Tdarr GPU options
- **NVIDIA**: install NVIDIA Container Toolkit on the host, then set `TDARR_NVIDIA_GPUS=all` (or `1`) in `.env`.
- **Intel/AMD VAAPI**: uncomment the `/dev/dri:/dev/dri` mapping in `docker-compose.yml` and set `RENDER_GID` in `.env` to your host's render group id.

## Method 2: MediaBlade All-in-One Script
This script is slightly different. It still installs the same Docker Compose file, prompting you for nearly the same info, but at the same time, it also installs MediaBlade-Organizer.

MediaBlade-Organizer is a fix for when media organization breaks. It not only organizes files into a cleanly-organized setup, but also renames everything to an easily readable setup that Jellyfin will easily read.

### What this setup does.
This setup installs both a Python script & a Docker Compose file. The Docker Compose script will run your media stack. The Python script will run your organizing. The Python script runs hourly & as long as you setup a Discord Webhook link, it'll notify you how many things were moved, skipped & when it last ran. 

1. Install the script.
  Install the script onto your machine. Use wget, or however works best for you.
2. Make the script executable.
  Run `chmod +x MediaBlade-AIO-Installer`
3. Run the script.
  Run `./MediaBlade-AIO-Installer`
4. Setup the services via WebUI
  From here, you're basically done. 

### AIO Installer options
When you run the AIO installer, it will prompt you for:
- **Security mode**: run containers as root *or* as a specific UID/GID
- **Networking**: bind ports to localhost, LAN, or all interfaces
- **Reverse proxy**: enable/disable Traefik + optional auto-start + hostnames + Let's Encrypt email
- **Tdarr GPU**: none / NVIDIA / VAAPI (writes an override compose file when needed)
