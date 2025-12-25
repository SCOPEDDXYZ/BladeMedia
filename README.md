# Simple Media Server Stack
A simple & easy way to setup an automated media server system. 

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
Overall, this uses Docker Compose. I have provided two different ways to run this though. 

1. Plain old "docker-compose.yml" file. 
You can run the services easily by just downloading the docker-compose.yml file using wget & filling out all the necessary information for everything to run.

2. Automated installation script.
In this repository, you can find a bash script. Use wget to get that onto your system, and run the installer. Upon running it, you'll be asked a few questions, aslong as you fill them out correctly, it'll breeze through the entire installation. From making the directories, to creating the compose file & starting the stack. Very straightforward, very simple.

## Updating
Updating the stack is simple. All you need to do is this:
- SSH or access the machine directly.
- Enter root user mode.
- Navigate to the directory in which your installation script created the docker-compose.yml file, then run this comamand: ```docker compose down```
- Once you've taken the stack down run this command: ```docker compose pull```
- After that you can run: ```docker compose up -d```
- And you're good to go! 
