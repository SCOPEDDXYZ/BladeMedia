#!/usr/bin/env python3
"""
BladeMedia Organizer v2.1 - Unattended Service Edition
Organizes movies/TV + Discord webhook reporting.
Perfect for hourly cron/systemd automation.
"""

import os
import re
import shutil
import argparse
import requests
import json
from datetime import datetime
from pathlib import Path
from typing import List, Tuple, Optional, Dict, Any
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class MediaOrganizer:
    def __init__(self, root_path: str, dry_run: bool = False, discord_webhook: str = None):
        self.root = Path(root_path)
        self.movies_root = self.root / "media" / "movies"
        self.tv_root = self.root / "media" / "tv"
        self.dry_run = dry_run
        self.discord_webhook = discord_webhook
        self.summary = {
            "movies_organized": 0, "movies_skipped": 0,
            "tv_organized": 0, "tv_skipped": 0, "errors": []
        }
        self.video_exts = {'.mkv', '.mp4', '.avi', '.m4v', '.mov', '.wmv', '.flv'}
        self.subtitle_exts = {'.srt', '.ass', '.ssa', '.sub', '.idx'}
    
    def send_discord(self, title: str, message: str, color: str = "success"):
        """Send rich embed to Discord webhook."""
        if not self.discord_webhook:
            return
        
        colors = {"success": 0x00ff00, "warning": 0xff9900, "error": 0xff0000}
        embed = {
            "title": f"🎬 {title}",
            "description": message,
            "color": colors.get(color, 0x00ff00),
            "timestamp": datetime.utcnow().isoformat(),
            "footer": {"text": "BladeMedia Organizer v2.1"}
        }
        
        payload = {"embeds": [embed]}
        try:
            requests.post(self.discord_webhook, json=payload, timeout=10)
            logger.info("✅ Discord notification sent")
        except Exception as e:
            logger.error(f"Discord send failed: {e}")
    
    def parse_movie_filename(self, filename: str) -> Optional[Tuple[str, int]]:
        """Extract title and year from movie filename."""
        patterns = [
            r'^(.+?)[. _-]+(?P<year>\d{4})[. _]',  
            r'^(.+?)[. _]*\(?(?P<year>\d{4})\)?[. _]',  
        ]
        filename = re.sub(r'[\[\]]', '', filename)
        for pattern in patterns:
            match = re.match(pattern, filename, re.IGNORECASE)
            if match:
                title = match.group(1).strip('.- ').replace('.', ' ').replace('_', ' ').strip()
                year = int(match.group('year'))
                if 1900 <= year <= 2026:
                    return title, year
        return None
    
    def parse_tv_filename(self, filename: str) -> Optional[Tuple[str, int, int, str]]:
        """Extract show, season, episode, title from TV filename."""
        patterns = [
            r'^(?P<show>.+?)[. _]+S(?P<season>\d+)[. _]*E(?P<episode>\d+)(?:[._-].*)?(?P<title>.*)?[. _]',
            r'^(?P<show>.+?)[. _]+(?P<season>\d+)x(?P<episode>\d+)(?:[._-].*)?(?P<title>.*)?[. _]',
        ]
        
        filename = re.sub(r'[\[\]]', '', filename)
        for pattern in patterns:
            match = re.match(pattern, filename, re.IGNORECASE)
            if match:
                show = match.group('show').strip('.- ').replace('.', ' ').replace('_', ' ').strip()
                season = int(match.group('season'))
                episode = int(match.group('episode'))
                title = match.group('title').strip('.- ') if match.group('title') else f"Episode {episode}"
                return show, season, episode, title
        return None
    
    def get_video_files(self, path: Path) -> List[Path]:
        """Find all video files recursively."""
        videos = []
        for ext in self.video_exts:
            videos.extend(path.rglob(f'*{ext}'))
        return sorted(videos)
    
    def find_associated_subs(self, video_path: Path) -> List[Path]:
        """Find subtitle files matching the video filename."""
        subs = []
        video_name = video_path.stem
        for ext in self.subtitle_exts:
            pattern = f'{video_name}*{ext}'
            subs.extend(video_path.parent.glob(pattern))
        return sorted(subs)
    
    def organize_movie(self, video_path: Path) -> Optional[str]:
        """Organize movie into [Title] [Year] folder."""
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
        sub_dests = [new_folder / sub.name for sub in subs]
        
        logger.info(f"📽️  [{title}] [{year}] <- {video_path.name}")
        if not self.dry_run:
            new_folder.mkdir(parents=True, exist_ok=True)
            shutil.move(str(video_path), str(video_dest))
            for sub, sub_dest in zip(subs, sub_dests):
                if sub.exists():
                    shutil.move(str(sub), str(sub_dest))
        
        self.summary["movies_organized"] += 1
        return f"[{title}] [{year}]"
    
    def organize_tv(self, video_path: Path) -> Optional[str]:
        """Organize TV into [Show] [Year]/Season X [Year]/EPx - [Title] [Year]."""
        parsed = self.parse_tv_filename(video_path.name)
        if not parsed:
            self.summary["tv_skipped"] += 1
            return None
        
        show, season, episode, title = parsed
        show_year = 2025  # TODO: Parse from folder or metadata
        new_show_folder = self.tv_root / f"[{show}] [{show_year}]"
        new_season_folder = new_show_folder / f"Season {season} [{show_year}]"
        new_filename = f"EP{episode} - {title} [{show_year}]{video_path.suffix}"
        video_dest = new_season_folder / new_filename
        
        if (new_season_folder == video_path.parent and 
            video_path.name == new_filename):
            self.summary["tv_skipped"] += 1
            return None
        
        subs = self.find_associated_subs(video_path)
        sub_dests = [new_season_folder / f"{new_filename.rsplit('.', 1)[0]}{sub.suffix}" 
                    for sub in subs]
        
        logger.info(f"📺 [{show}] S{season:02d}E{episode:02d} <- {video_path.name}")
        if not self.dry_run:
            new_season_folder.mkdir(parents=True, exist_ok=True)
            shutil.move(str(video_path), str(video_dest))
            for sub, sub_dest in zip(subs, sub_dests):
                if sub.exists():
                    shutil.move(str(sub), str(sub_dest))
        
        self.summary["tv_organized"] += 1
        return f"[{show}] S{season:02d}E{episode:02d}"
    
    def run_movies(self):
        """Organize movies."""
        logger.info(f"🎬 Scanning movies: {self.movies_root}")
        videos = self.get_video_files(self.movies_root)
        logger.info(f"Found {len(videos)} movie files")
        
        for video in videos:
            self.organize_movie(video)
    
    def run_tv(self):
        """Organize TV shows."""
        logger.info(f"📺 Scanning TV: {self.tv_root}")
        videos = self.get_video_files(self.tv_root)
        logger.info(f"Found {len(videos)} TV files")
        
        for video in videos:
            self.organize_tv(video)
    
    def run(self):
        """Run full organization with Discord summary."""
        start_time = datetime.now()
        logger.info(f"🎥 BladeMedia Organizer starting at {self.root}")
        
        self.run_movies()
        self.run_tv()
        
        total_organized = self.summary["movies_organized"] + self.summary["tv_organized"]
        summary_msg = (f"**Movies**: {self.summary['movies_organized']} organized, "
                      f"{self.summary['movies_skipped']} skipped\n"
                      f"**TV**: {self.summary['tv_organized']} organized, "
                      f"{self.summary['tv_skipped']} skipped\n"
                      f"**Runtime**: {datetime.now() - start_time}")
        
        if total_organized > 0:
            self.send_discord("✅ Media Organized", summary_msg, "success")
            logger.info(f"✅ Organized {total_organized} files total")
        else:
            self.send_discord("ℹ️ No Changes", "No new media to organize", "warning")
            logger.info("ℹ️ No changes needed")

def main():
    parser = argparse.ArgumentParser(description="BladeMedia Media Organizer")
    parser.add_argument("root_path", help="BladeMedia root (e.g. /srv/blademedia)")
    parser.add_argument("--movies-only", action="store_true", help="Only organize movies")
    parser.add_argument("--tv-only", action="store_true", help="Only organize TV")
    parser.add_argument("--dry-run", action="store_true", help="Preview without moving")
    parser.add_argument("--discord-webhook", help="Discord webhook URL for notifications")
    args = parser.parse_args()
    
    organizer = MediaOrganizer(
        args.root_path, 
        args.dry_run, 
        args.discord_webhook
    )
    
    if args.tv_only:
        organizer.run_tv()
    elif args.movies_only:
        organizer.run_movies()
    else:
        organizer.run()

if __name__ == "__main__":
    main()
