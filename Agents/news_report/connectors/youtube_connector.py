from __future__ import annotations

import os
import re
import subprocess
import tempfile
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone
from typing import Optional


class YouTubeConnector:
    CHANNEL_FEED = "https://www.youtube.com/feeds/videos.xml?channel_id={id}"
    PLAYLIST_FEED = "https://www.youtube.com/feeds/videos.xml?playlist_id={id}"

    def __init__(self, config: dict, max_items: int = 10, date_range_hours: int = 24):
        channel_ids: list[str] = config.get("channelIds") or []
        if not channel_ids and config.get("channelId"):
            channel_ids = [config["channelId"]]
        self.channel_ids = channel_ids
        self.playlists: list[dict] = config.get("playlists") or []
        self.max_items = max_items
        self.date_range_hours = date_range_hours

    def collect(self) -> list[dict]:
        if not self.channel_ids and not self.playlists:
            raise RuntimeError(
                "YouTube channelIds 또는 playlists가 설정되지 않았습니다."
            )

        cutoff = datetime.now(timezone.utc) - timedelta(hours=self.date_range_hours)
        items: list[dict] = []

        for channel_id in self.channel_ids:
            try:
                items.extend(
                    self._fetch_feed(
                        self.CHANNEL_FEED.format(id=channel_id),
                        source_name=None,
                        cutoff=cutoff,
                        one_per_source=False,
                    )
                )
            except Exception as e:
                print(f"[youtube] channel {channel_id} 수집 실패: {e}", flush=True)

        for pl in self.playlists:
            pid = pl.get("playlistId", "")
            name = pl.get("name", pid)
            if not pid:
                continue
            try:
                items.extend(
                    self._fetch_feed(
                        self.PLAYLIST_FEED.format(id=pid),
                        source_name=name,
                        cutoff=cutoff,
                        one_per_source=True,
                    )
                )
            except Exception as e:
                print(f"[youtube] playlist '{name}' 수집 실패: {e}", flush=True)

        items.sort(key=lambda x: x.get("publishedAt", ""), reverse=True)
        return items

    def _fetch_feed(
        self,
        url: str,
        source_name: Optional[str],
        cutoff: datetime,
        one_per_source: bool,
    ) -> list[dict]:
        try:
            with urllib.request.urlopen(url, timeout=10) as resp:
                body = resp.read().decode("utf-8")
        except Exception as e:
            raise RuntimeError(f"YouTube 피드 수집 실패 ({url}): {e}") from e

        ns = {
            "atom": "http://www.w3.org/2005/Atom",
            "media": "http://search.yahoo.com/mrss/",
            "yt": "http://www.youtube.com/xml/schemas/2015",
        }

        root = ET.fromstring(body)
        feed_title = root.findtext("atom:title", namespaces=ns) or url
        display_name = source_name or feed_title
        all_entries = root.findall("atom:entry", ns)

        def _parse_entry(entry: ET.Element) -> Optional[dict]:
            title = entry.findtext("atom:title", namespaces=ns) or ""
            link_el = entry.find("atom:link", ns)
            link = link_el.get("href", "") if link_el is not None else ""
            published_str = entry.findtext("atom:published", namespaces=ns) or ""
            if not title or not link:
                return None
            if _is_membership_video(title):
                return None

            video_id_el = entry.find("yt:videoId", ns)
            video_id = (
                video_id_el.text if video_id_el is not None else _extract_video_id(link)
            )

            media_group = entry.find("media:group", ns)
            description = ""
            if media_group is not None:
                desc_el = media_group.find("media:description", ns)
                if desc_el is not None and desc_el.text:
                    description = _clean_membership_text(desc_el.text[:500])

            transcript = _get_transcript(video_id, link) if video_id else ""
            transcript = _clean_membership_text(transcript)
            content_text = transcript or description

            # Fetch video metadata via smithery youtube-mcp
            video_meta = _get_video_meta(video_id) if video_id else {}

            item = {
                "title": title.strip(),
                "url": link.strip(),
                "summary": (description[:300] if description else transcript[:300])
                or "",
                "contentText": content_text,
                "publishedAt": published_str,
                "sourceType": "youtube",
                "sourceName": f"YouTube / {display_name}",
                "author": display_name,
            }
            if video_meta:
                item["viewCount"] = video_meta.get("viewCount", 0)
                item["likeCount"] = video_meta.get("likeCount", 0)
                item["duration"] = video_meta.get("duration", "")
            return item

        if one_per_source:

            def _is_recent(entry: ET.Element) -> bool:
                dt = _parse_iso(entry.findtext("atom:published", namespaces=ns) or "")
                return dt is not None and dt >= cutoff

            recent_entries = [e for e in all_entries if _is_recent(e)]
            target_entries = recent_entries[:1] if recent_entries else all_entries[:1]
            result = []
            for entry in target_entries:
                item = _parse_entry(entry)
                if item:
                    result.append(item)
            return result
        else:
            result = []
            for entry in all_entries:
                published_str = entry.findtext("atom:published", namespaces=ns) or ""
                published_dt = _parse_iso(published_str)
                if published_dt and published_dt < cutoff:
                    continue
                item = _parse_entry(entry)
                if item:
                    result.append(item)
            return result


_MEMBERSHIP_TITLE_MARKERS = [
    "멤버십 전용",
    "멤버십전용",
    "회원 전용",
    "회원전용",
    "[멤버십]",
    "(멤버십)",
    "🍔멤버십",
    "🔒",
]

_MEMBERSHIP_PROMO_PATTERNS = [
    "멤버십 오픈",
    "멤버십 가입",
    "멤버십 혜택",
    "멤버십 회원",
    "멤버십으로",
    "한경글로벌마켓 멤버십",
    "멤버십 구독",
    "멤버십 안내",
    "멤버십 신청",
]

_VTT_META_PREFIXES = ["Kind:", "Language:"]


def _is_membership_video(title: str) -> bool:
    lower = title.lower()
    return any(m.lower() in lower for m in _MEMBERSHIP_TITLE_MARKERS)


def _clean_membership_text(text: str) -> str:
    pattern = "|".join(re.escape(p) for p in _MEMBERSHIP_PROMO_PATTERNS)
    cleaned = re.sub(r"[^。.!?\n]*(?:" + pattern + r")[^。.!?\n]*[。.!?\n]?", " ", text)
    return re.sub(r" {2,}", " ", cleaned).strip()


def _parse_iso(s: str) -> Optional[datetime]:
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError:
        return None


def _extract_video_id(url: str) -> str:
    m = re.search(r"[?&]v=([A-Za-z0-9_-]{11})", url)
    return m.group(1) if m else ""


def _get_transcript(video_id: str, url: str) -> str:
    transcript = _transcript_via_smithery(video_id)
    if transcript:
        return transcript
    transcript = _transcript_via_api(video_id)
    if transcript:
        return transcript
    return _transcript_via_ytdlp(url)


def _transcript_via_smithery(video_id: str) -> str:
    if not video_id:
        return ""
    try:
        import json as _json

        result = subprocess.run(
            [
                "smithery",
                "tool",
                "call",
                "youtube-mcp",
                "transcripts_getTranscript",
                _json.dumps({"videoId": video_id, "language": "ko"}),
            ],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode != 0:
            return ""
        output = result.stdout.strip()
        if not output:
            return ""
        try:
            data = _json.loads(output)
            if isinstance(data, dict):
                text = data.get("transcript") or data.get("text") or ""
                if isinstance(text, list):
                    return " ".join(
                        seg.get("text", "") if isinstance(seg, dict) else str(seg)
                        for seg in text
                    )[:8000]
                return str(text)[:8000]
            return str(data)[:8000]
        except _json.JSONDecodeError:
            return output[:8000]
    except (FileNotFoundError, subprocess.TimeoutExpired, Exception):
        return ""


def _transcript_via_api(video_id: str) -> str:
    try:
        from youtube_transcript_api import YouTubeTranscriptApi  # type: ignore

        segments = YouTubeTranscriptApi.get_transcript(video_id, languages=["ko", "en"])
        return " ".join(seg["text"] for seg in segments)[:8000]
    except Exception:
        return ""


def _transcript_via_ytdlp(url: str) -> str:
    try:
        result = subprocess.run(["yt-dlp", "--version"], capture_output=True, timeout=5)
        if result.returncode != 0:
            return ""
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return ""

    with tempfile.TemporaryDirectory() as tmpdir:
        try:
            subprocess.run(
                [
                    "yt-dlp",
                    "--write-auto-sub",
                    "--sub-langs",
                    "ko,en",
                    "--skip-download",
                    "--sub-format",
                    "vtt",
                    "-o",
                    os.path.join(tmpdir, "%(id)s.%(ext)s"),
                    url,
                ],
                capture_output=True,
                timeout=30,
            )
        except subprocess.TimeoutExpired:
            return ""

        for fname in os.listdir(tmpdir):
            if fname.endswith(".vtt"):
                with open(
                    os.path.join(tmpdir, fname), encoding="utf-8", errors="ignore"
                ) as f:
                    return _parse_vtt(f.read())

    return ""


def _get_video_meta(video_id: str) -> dict:
    if not video_id:
        return {}
    try:
        import json as _json

        result = subprocess.run(
            [
                "smithery",
                "tool",
                "call",
                "youtube-mcp",
                "videos_getVideo",
                _json.dumps({"videoId": video_id, "parts": ["statistics", "contentDetails"]}),
            ],
            capture_output=True,
            text=True,
            timeout=15,
        )
        if result.returncode != 0:
            return {}
        output = result.stdout.strip()
        if not output:
            return {}
        data = _json.loads(output)
        meta = {}
        stats = data.get("statistics", {})
        if stats:
            meta["viewCount"] = int(stats.get("viewCount", 0))
            meta["likeCount"] = int(stats.get("likeCount", 0))
        details = data.get("contentDetails", {})
        if details:
            meta["duration"] = details.get("duration", "")
        return meta
    except Exception:
        return {}


def _parse_vtt(vtt: str) -> str:
    texts: list[str] = []
    for line in vtt.splitlines():
        line = line.strip()
        if not line or line.startswith("WEBVTT") or "-->" in line or line.isdigit():
            continue
        if any(line.startswith(p) for p in _VTT_META_PREFIXES):
            continue
        clean = re.sub(r"<[^>]+>", "", line).strip()
        if clean:
            texts.append(clean)

    deduped: list[str] = []
    for t in texts:
        if not deduped or deduped[-1] != t:
            deduped.append(t)
    return " ".join(deduped)[:8000]
