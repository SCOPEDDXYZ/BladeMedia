#!/usr/bin/env bash
set -euo pipefail

print_banner() {
  printf '\n\033[1;36m'
  printf '=====================================\n'
  printf '   BladeMedia Organizer Installer    \n'
  printf '=====================================\n'
  printf '\033[0m'
}

main() {
  print_banner
  
  # Auto-detect BladeMedia root (finds docker-compose.yml)
  local blademedia_root
  if [[ -f docker-compose.yml ]]; then
    blademedia_root="$(pwd)"
  elif [[ -f /srv/blademedia/docker-compose.yml ]]; then
    blademedia_root="/srv/blademedia"
  else
    blademedia_root="$(find /srv /opt /home -name "docker-compose.yml" -path "*/blademedia*" | head -1 | xargs -I {} dirname {})"
  fi
  
  if [[ -z "$blademedia_root" ]]; then
    printf '\033[1;31mError: No BladeMedia docker-compose.yml found\033[0m\n' >&2
    printf 'Run from BladeMedia root or check /srv/blademedia/\n' >&2
    exit 1
  fi
  
  printf '\033[1;32m✅ Found BladeMedia at: %s\033[0m\n' "$blademedia_root"
  
  # Discord webhook prompt
  local webhook
  read -rp $'\033[1;33mEnter Discord webhook URL (or Enter to skip): \033[0m' webhook
  webhook="${webhook:-}"
  
  cd "$blademedia_root" || exit 1
  
  # Install Python dependencies
  printf '\n\033[1;34m📦 Installing Python dependencies...\033[0m\n'
  sudo apt update
  sudo apt install -y python3 python3-pip python3-requests || \
  sudo yum install -y python3 python3-pip || \
  sudo dnf install -y python3 python3-pip
  
  pip3 install --user requests || sudo pip3 install requests
  
  # Create complete media_organizer.py
  printf '\n\033[1;34m💾 Installing media_organizer.py...\033[0m\n'
  cat > media_organizer.py << 'EOF'
#!/usr/bin/env python3
"""
BladeMedia Organizer v2.1 - Unattended Service Edition
Organizes movies/TV + Discord webhook reporting.
"""

import os
import re
import shutil
import argparse
import requests
import json
from datetime import datetime
from pathlib import Path
from typing import List, Tuple, Optional
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class MediaOrganizer:
    def __init__(self, root_path: str, dry_run: bool = False, discord_webhook: str = None):
        self.root = Path(root_path)
        self.movies_root = self.root / "media" / "movies"
        self.tv_root = self.root / "media" / "tv"
        self.dry_run = dry_run
        self.discord_webhook = discord_webhook
        self.summary = {"movies_organized": 0, "movies_skipped": 0, "tv_organized": 0, "tv_skipped": 0, "errors": []}
        self.video_exts = {'.mkv', '.mp4', '.avi', '.m4v', '.mov', '.wmv', '.flv'}
        self.subtitle_exts = {'.srt', '.ass', '.ssa', '.sub', '.idx'}
    
    def send_discord(self, title: str, message: str, color: str = "success"):
        if not self.discord_webhook: return
        colors = {"success": 0x00ff00, "warning": 0xff9900, "error": 0xff0000}
        embed = {"title": f"🎬 {title}", "description": message, "color": colors.get(color, 0x00ff00),
                 "timestamp": datetime.utcnow().isoformat(), "footer": {"text": "BladeMedia Organizer v2.1"}}
        try:
            requests.post(self.discord_webhook, json={"embeds": [embed]}, timeout=10)
            logger.info("✅ Discord sent")
        except Exception as e:
            logger.error(f"Discord failed: {e}")
    
    def parse_movie_filename(self, filename: str) -> Optional[Tuple[str, int]]:
        patterns = [r'^(.+?)[. _-]+(?P<year>\d{4})[. _]', r'^(.+?)[. _]*\(?(?P<year>\d{4})\)?[. _]']
        filename = re.sub(r'[\[\]]', '', filename)
        for pattern in patterns:
            match = re.match(pattern, filename, re.IGNORECASE)
            if match:
                title = match.group(1).strip('.- ').replace('.', ' ').replace('_', ' ').strip()
                year = int(match.group('year'))
                if 1900 <= year <= 2026: return title, year
        return None
    
    def parse_tv_filename(self, filename: str) -> Optional[Tuple[str, int, int, str]]:
        patterns = [
            r'^(?P<show>.+?)[. _]+S(?P<season>\d+)[. _]*E(?P<episode>\d+)(?:[._-].*)?(?P<title>.*)?[. _]',
            r'^(?P<show>.+?)[. _]+(?P<season>\d+)x(?P<episode>\d+)(?:[._-].*)?(?P<title>.*)?[. _]'
        ]
        filename = re.sub(r'[\[\]]', '', filename)
        for pattern in patterns:
            match = re.match(pattern, filename, re.IGNORECASE)
            if match:
                show = match.group('show').strip('.- ').replace('.', ' ').replace('_', ' ').strip()
                season, episode = int(match.group('season')), int(match.group('episode'))
                title = match.group('title').strip('.- ') or f"Episode {episode}"
                return show, season, episode, title
        return None
    
    def get_video_files(self, path: Path) -> List[Path]:
        videos = []
        for ext in self.video_exts: videos.extend(path.rglob(f'*{ext}'))
        return sorted(videos)
    
    def find_associated_subs(self, video_path: Path) -> List[Path]:
        subs = []
        video_name = video_path.stem
        for ext in self.subtitle_exts:
            subs.extend(video_path.parent.glob(f'{video_name}*{ext}'))
        return sorted(subs)
    
    def organize_movie(self, video_path: Path) -> Optional[str]:
        parsed = self.parse_movie_filename(video_path.name)
        if not parsed: 
            self.summary["movies_skipped"] += 1
            return None
        
        title, year = parsed
        new_folder = self.movies_root / f"[{title}] [{year}]"
        if new_folder == video_path.parent: 
            self.summary["movies_skipped"] += 1
            return None
        
        video_dest = new_folder / video_path.name
        subs = self.find_associated_subs(video_path)
        
        logger.info(f"📽️ [{title}] [{year}] <- {video_path.name}")
        if not self.dry_run:
            new_folder.mkdir(parents=True, exist_ok=True)
            shutil.move(str(video_path), str(video_dest))
            for sub in subs:
                if sub.exists(): shutil.move(str(sub), str(new_folder / sub.name))
        self.summary["movies_organized"] += 1
        return f"[{title}] [{year}]"
    
    def organize_tv(self, video_path: Path) -> Optional[str]:
        parsed = self.parse_tv_filename(video_path.name)
        if not parsed: 
            self.summary["tv_skipped"] += 1
            return None
        
        show, season, episode, title = parsed
        show_year = 2025
        new_show_folder = self.tv_root / f"[{show}] [{show_year}]"
        new_season_folder = new_show_folder / f"Season {season} [{show_year}]"
        new_filename = f"EP{episode} - {title} [{show_year}]{video_path.suffix}"
        video_dest = new_season_folder / new_filename
        
        if new_season_folder == video_path.parent and video_path.name == new_filename:
            self.summary["tv_skipped"] += 1
            return None
        
        subs = self.find_associated_subs(video_path)
        logger.info(f"📺 [{show}] S{season:02d}E{episode:02d} <- {video_path.name}")
        if not self.dry_run:
            new_season_folder.mkdir(parents=True, exist_ok=True)
            shutil.move(str(video_path), str(video_dest))
            for sub in subs:
                if sub.exists():
                    shutil.move(str(sub), str(new_season_folder / f"{new_filename.rsplit('.',1)[0]}{sub.suffix}"))
        self.summary["tv_organized"] += 1
        return f"[{show}] S{season:02d}E{episode:02d}"
    
    def run_movies(self):
        logger.info(f"🎬 Scanning: {self.movies_root}")
        videos = self.get_video_files(self.movies_root)
        logger.info(f"Found {len(videos)} movies")
        for video in videos: self.organize_movie(video)
    
    def run_tv(self):
        logger.info(f"📺 Scanning: {self.tv_root}")
        videos = self.get_video_files(self.tv_root)
        logger.info(f"Found {len(videos)} TV files")
        for video in videos: self.organize_tv(video)
    
    def run(self):
        start_time = datetime.now()
        logger.info(f"🎥 Starting at {self.root}")
        self.run_movies()
        self.run_tv()
        
        total = self.summary["movies_organized"] + self.summary["tv_organized"]
        msg = (f"**Movies**: {self.summary['movies_organized']} org, {self.summary['movies_skipped']} skip\n"
               f"**TV**: {self.summary['tv_organized']} org, {self.summary['tv_skipped']} skip\n"
               f"**Runtime**: {(datetime.now()-start_time).total_seconds():.0f}s")
        
        if total > 0:
            self.send_discord("✅ Organized", msg)
            logger.info(f"✅ {total} files organized")
        else:
            self.send_discord("ℹ️ No changes", "Nothing to organize")
            logger.info("ℹ️ No changes")

def main():
    parser = argparse.ArgumentParser(description="BladeMedia Organizer")
    parser.add_argument("root_path", nargs='?', default='.')
    parser.add_argument("--movies-only", action="store_true")
    parser.add_argument("--tv-only", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--discord-webhook")
    args = parser.parse_args()
    
    organizer = MediaOrganizer(args.root_path, args.dry_run, args.discord_webhook)
    if args.tv_only: organizer.run_tv()
    elif args.movies_only: organizer.run_movies()
    else: organizer.run()

if __name__ == "__main__": main()
EOF

  chmod +x media_organizer.py
  
  # Install systemd service files
  printf '\n\033[1;34m⚙️  Installing systemd service...\033[0m\n'
  sudo tee /etc/systemd/system/blademedia-organizer.service > /dev/null << EOF
[Unit]
Description=BladeMedia Media Organizer
After=docker.service network-online.target
Wants=docker.service

[Service]
Type=oneshot
WorkingDirectory=${blademedia_root}
ExecStart=/usr/bin/python3 ${blademedia_root}/media_organizer.py .
$( [[ -n "${webhook}" ]] && echo "--discord-webhook='${webhook}'" || echo "" )
User=$(id -u)
Group=$(id -g)
StandardOutput=append:${blademedia_root}/organizer.log
StandardError=append:${blademedia_root}/organizer.log
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF

  sudo tee /etc/systemd/system/blademedia-organizer.timer > /dev/null << 'EOF'
[Unit]
Description=Run BladeMedia Organizer hourly
Requires=blademedia-organizer.service

[Timer]
OnCalendar=hourly
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
EOF

  # Activate service
  sudo systemctl daemon-reload
  sudo systemctl enable blademedia-organizer.timer
  sudo systemctl start blademedia-organizer.timer
  
  # Test run
  printf '\n\033[1;34m🧪 Testing...\033[0m\n'
  python3 media_organizer.py . --dry-run
  
  printf '\n\033[1;32m✅ Installation Complete!\033[0m\n\n'
  printf '📊 Service Status: \n'
  sudo systemctl status blademedia-organizer.timer --no-pager
  
  printf '\n📋 Logs: tail -f %s/organizer.log\n' "$blademedia_root"
  printf '🧪 Manual test: python3 media_organizer.py . --dry-run\n'
  printf '⏹️  Stop: sudo systemctl stop blademedia-organizer.timer\n'
}

main "$@"
