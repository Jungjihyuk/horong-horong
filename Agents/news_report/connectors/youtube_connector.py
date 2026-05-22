from __future__ import annotations

import os
import re
import subprocess
import tempfile
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone
from typing import Optional

from ._text import clean_summary


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
        sources: list[tuple[str, str, str]] = [
            ("channel", channel_id, channel_id)
            for channel_id in self.channel_ids
        ]
        sources.extend(
            ("playlist", pl.get("playlistId", ""), pl.get("name", pl.get("playlistId", "")))
            for pl in self.playlists
            if pl.get("playlistId", "")
        )
        if not sources:
            raise RuntimeError(
                "YouTube channelIds 또는 playlists가 설정되지 않았습니다."
            )

        failures: list[str] = []
        attempted = 0
        base_quota, remainder = divmod(self.max_items, len(sources))
        buckets: list[list[dict]] = [[] for _ in sources]
        exhausted: set[int] = set()

        for idx, source in enumerate(sources):
            quota = base_quota + (1 if idx < remainder else 0)
            if quota <= 0:
                exhausted.add(idx)
                continue
            attempted += 1
            try:
                buckets[idx] = self._collect_source(source, cutoff, quota)
                if len(buckets[idx]) < quota:
                    exhausted.add(idx)
            except Exception as e:
                failures.append(_format_source_failure(source, e))
                exhausted.add(idx)

        remaining = self.max_items - sum(len(bucket) for bucket in buckets)
        while remaining > 0:
            made_progress = False
            for idx, source in enumerate(sources):
                if remaining <= 0:
                    break
                if idx in exhausted:
                    continue
                exclude_urls = {item.get("url", "") for item in buckets[idx]}
                try:
                    extras = self._collect_source(source, cutoff, 1, exclude_urls)
                except Exception:
                    exhausted.add(idx)
                    continue
                if not extras:
                    exhausted.add(idx)
                    continue
                buckets[idx].extend(extras)
                remaining -= len(extras)
                made_progress = True
            if not made_progress:
                break

        if attempted > 0 and failures and len(failures) == attempted:
            raise RuntimeError(" / ".join(failures))

        items = [item for bucket in buckets for item in bucket]
        items.sort(key=lambda x: x.get("publishedAt", ""), reverse=True)
        return items[: self.max_items]

    def _collect_source(
        self,
        source: tuple[str, str, str],
        cutoff: datetime,
        item_limit: int,
        exclude_urls: Optional[set[str]] = None,
    ) -> list[dict]:
        kind, identifier, display_name = source
        if kind == "channel":
            resolved_channel_id = _resolve_channel_id(identifier)
            try:
                return self._fetch_feed(
                    self.CHANNEL_FEED.format(id=resolved_channel_id),
                    source_name=None,
                    cutoff=cutoff,
                    one_per_source=False,
                    item_limit=item_limit,
                    exclude_urls=exclude_urls,
                )
            except Exception:
                return self._fetch_page_videos(
                    _channel_videos_url(identifier, resolved_channel_id),
                    source_name=identifier,
                    cutoff=cutoff,
                    one_per_source=False,
                    item_limit=item_limit,
                    exclude_urls=exclude_urls,
                )
        try:
            return self._fetch_feed(
                self.PLAYLIST_FEED.format(id=identifier),
                source_name=display_name,
                cutoff=cutoff,
                one_per_source=False,
                item_limit=item_limit,
                exclude_urls=exclude_urls,
            )
        except Exception:
            return self._fetch_page_videos(
                f"https://www.youtube.com/playlist?list={identifier}",
                source_name=display_name,
                cutoff=cutoff,
                one_per_source=False,
                item_limit=item_limit,
                exclude_urls=exclude_urls,
            )

    def _fetch_feed(
        self,
        url: str,
        source_name: Optional[str],
        cutoff: datetime,
        one_per_source: bool,
        item_limit: Optional[int] = None,
        exclude_urls: Optional[set[str]] = None,
    ) -> list[dict]:
        limit = 1 if one_per_source else (item_limit or self.max_items)
        if limit <= 0:
            return []
        excluded = exclude_urls or set()
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
            if link in excluded:
                return None
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
                "summary": clean_summary(description or transcript),
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
                if len(result) >= limit:
                    break
            if not result:
                for entry in all_entries:
                    item = _parse_entry(entry)
                    if item:
                        result.append(item)
                    if len(result) >= limit:
                        break
            return result

    def _fetch_page_videos(
        self,
        url: str,
        source_name: Optional[str],
        cutoff: datetime,
        one_per_source: bool,
        item_limit: Optional[int] = None,
        exclude_urls: Optional[set[str]] = None,
    ) -> list[dict]:
        limit = 1 if one_per_source else (item_limit or self.max_items)
        if limit <= 0:
            return []
        excluded = exclude_urls or set()
        try:
            body = _fetch_youtube_page(url)
            payload = _extract_yt_initial_data(body)
        except Exception as e:
            raise RuntimeError(f"YouTube 페이지 수집 실패 ({url}): {e}") from e

        display_name = source_name or url
        videos = _extract_video_lockups(payload)
        if not videos:
            raise RuntimeError(f"YouTube 페이지에서 영상 목록을 찾지 못했습니다 ({url})")

        result = []
        for video in videos:
            video_id = video.get("videoId", "")
            if f"https://www.youtube.com/watch?v={video_id}" in excluded:
                continue
            published_dt = _published_time_to_datetime(video.get("publishedTimeText", ""))
            if published_dt and published_dt < cutoff:
                continue
            item = _video_lockup_to_item(video, display_name)
            if item:
                result.append(item)
            if one_per_source and result:
                break
            if len(result) >= limit:
                break

        if not result:
            for video in videos:
                video_id = video.get("videoId", "")
                if f"https://www.youtube.com/watch?v={video_id}" in excluded:
                    continue
                item = _video_lockup_to_item(video, display_name)
                if item:
                    result.append(item)
                if len(result) >= limit:
                    break
        return result


def _format_source_failure(source: tuple[str, str, str], error: Exception) -> str:
    kind, identifier, display_name = source
    if kind == "channel":
        return f"channel {identifier}: {error}"
    return f"playlist '{display_name}': {error}"


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


def _resolve_channel_id(identifier: str) -> str:
    raw = (identifier or "").strip()
    if not raw or raw.startswith("UC"):
        return raw
    if raw.startswith("@"):
        return _resolve_channel_handle(raw)
    return raw


def _resolve_channel_handle(handle: str) -> str:
    try:
        with urllib.request.urlopen(f"https://www.youtube.com/{handle}", timeout=10) as resp:
            body = resp.read().decode("utf-8", errors="ignore")
    except Exception as e:
        raise RuntimeError(f"YouTube 핸들 해석 실패 ({handle}): {e}") from e

    patterns = [
        r'"channelId":"(UC[A-Za-z0-9_-]{22})"',
        r'"browseId":"(UC[A-Za-z0-9_-]{22})"',
        r'"externalId":"(UC[A-Za-z0-9_-]{22})"',
        r'itemprop="channelId"\s+content="(UC[A-Za-z0-9_-]{22})"',
        r"/channel/(UC[A-Za-z0-9_-]{22})",
    ]
    for pattern in patterns:
        match = re.search(pattern, body)
        if match:
            return match.group(1)
    raise RuntimeError(f"YouTube 핸들에서 channelId를 찾지 못했습니다: {handle}")


def _channel_videos_url(raw_identifier: str, resolved_channel_id: str) -> str:
    raw = (raw_identifier or "").strip()
    if raw.startswith("@"):
        return f"https://www.youtube.com/{raw}/videos"
    if resolved_channel_id:
        return f"https://www.youtube.com/channel/{resolved_channel_id}/videos"
    return raw


def _fetch_youtube_page(url: str) -> str:
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": (
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/124.0 Safari/537.36"
            ),
            "Accept-Language": "ko,en;q=0.8",
        },
    )
    with urllib.request.urlopen(request, timeout=10) as resp:
        return resp.read().decode("utf-8", errors="ignore")


def _extract_yt_initial_data(body: str) -> dict:
    marker = "ytInitialData"
    marker_index = body.find(marker)
    if marker_index < 0:
        raise ValueError("ytInitialData 없음")
    start = body.find("{", marker_index)
    if start < 0:
        raise ValueError("ytInitialData JSON 시작점을 찾지 못함")

    depth = 0
    in_string = False
    escaped = False
    for idx, ch in enumerate(body[start:], start):
        if in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == "\"":
                in_string = False
            continue
        if ch == "\"":
            in_string = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                import json as _json

                return _json.loads(body[start : idx + 1])
    raise ValueError("ytInitialData JSON 종료점을 찾지 못함")


def _extract_video_lockups(payload: object) -> list[dict]:
    videos: list[dict] = []
    seen: set[str] = set()

    def _walk(node: object) -> None:
        if isinstance(node, dict):
            if "videoRenderer" in node:
                item = _video_renderer_to_lockup(node["videoRenderer"])
                if item and item["videoId"] not in seen:
                    seen.add(item["videoId"])
                    videos.append(item)
            if "playlistVideoRenderer" in node:
                item = _playlist_video_renderer_to_lockup(node["playlistVideoRenderer"])
                if item and item["videoId"] not in seen:
                    seen.add(item["videoId"])
                    videos.append(item)
            if "lockupViewModel" in node:
                item = _lockup_view_model_to_lockup(node["lockupViewModel"])
                if item and item["videoId"] not in seen:
                    seen.add(item["videoId"])
                    videos.append(item)
            for value in node.values():
                _walk(value)
        elif isinstance(node, list):
            for value in node:
                _walk(value)

    _walk(payload)
    return videos


def _video_renderer_to_lockup(renderer: dict) -> dict:
    video_id = renderer.get("videoId", "")
    title = _text_from_runs(renderer.get("title", {}))
    published = _text_from_runs(renderer.get("publishedTimeText", {}))
    duration = _text_from_runs(renderer.get("lengthText", {}))
    if not video_id or not title or _is_membership_video(title):
        return {}
    return {
        "videoId": video_id,
        "title": title,
        "publishedTimeText": published,
        "duration": duration,
    }


def _playlist_video_renderer_to_lockup(renderer: dict) -> dict:
    video_id = renderer.get("videoId", "")
    title = _text_from_runs(renderer.get("title", {}))
    duration = _text_from_runs(renderer.get("lengthText", {}))
    published = ""
    video_info = renderer.get("videoInfo", {}).get("runs", [])
    if isinstance(video_info, list):
        for run in video_info:
            if not isinstance(run, dict):
                continue
            text = str(run.get("text", ""))
            if "전" in text:
                published = text
                break
    if not video_id or not title or _is_membership_video(title):
        return {}
    return {
        "videoId": video_id,
        "title": title,
        "publishedTimeText": published,
        "duration": duration,
    }


def _lockup_view_model_to_lockup(view_model: dict) -> dict:
    if view_model.get("contentType") != "LOCKUP_CONTENT_TYPE_VIDEO":
        return {}
    video_id = view_model.get("contentId", "")
    metadata = (
        view_model.get("metadata", {})
        .get("lockupMetadataViewModel", {})
    )
    title = metadata.get("title", {}).get("content", "")
    rows = (
        metadata.get("metadata", {})
        .get("contentMetadataViewModel", {})
        .get("metadataRows", [])
    )
    parts = []
    for row in rows:
        for part in row.get("metadataParts", []):
            text = part.get("text", {}).get("content", "")
            if text:
                parts.append(text)
    published = next((p for p in parts if "전" in p), "")
    duration = (
        view_model.get("rendererContext", {})
        .get("accessibilityContext", {})
        .get("label", "")
    )
    if not video_id or not title or _is_membership_video(title):
        return {}
    return {
        "videoId": video_id,
        "title": title,
        "publishedTimeText": published,
        "duration": duration,
    }


def _text_from_runs(value: object) -> str:
    if not isinstance(value, dict):
        return ""
    if "simpleText" in value:
        return str(value.get("simpleText", ""))
    runs = value.get("runs", [])
    if isinstance(runs, list):
        return "".join(str(run.get("text", "")) for run in runs if isinstance(run, dict))
    return ""


def _video_lockup_to_item(video: dict, display_name: str) -> dict:
    video_id = video.get("videoId", "")
    title = video.get("title", "").strip()
    if not video_id or not title:
        return {}

    link = f"https://www.youtube.com/watch?v={video_id}"
    transcript = _clean_membership_text(_get_transcript(video_id, link))
    published_at = ""
    published_dt = _published_time_to_datetime(video.get("publishedTimeText", ""))
    if published_dt:
        published_at = published_dt.isoformat()

    item = {
        "title": title,
        "url": link,
        "summary": clean_summary(transcript),
        "contentText": transcript,
        "publishedAt": published_at,
        "sourceType": "youtube",
        "sourceName": f"YouTube / {display_name}",
        "author": display_name,
    }
    video_meta = _get_video_meta(video_id)
    if video_meta:
        item["viewCount"] = video_meta.get("viewCount", 0)
        item["likeCount"] = video_meta.get("likeCount", 0)
        item["duration"] = video_meta.get("duration", video.get("duration", ""))
    elif video.get("duration"):
        item["duration"] = video.get("duration", "")
    return item


def _published_time_to_datetime(text: str) -> Optional[datetime]:
    text = (text or "").strip()
    match = re.search(r"(\d+)\s*(분|시간|일|주|개월|년)\s*전", text)
    if not match:
        return None
    amount = int(match.group(1))
    unit = match.group(2)
    now = datetime.now(timezone.utc)
    if unit == "분":
        return now - timedelta(minutes=amount)
    if unit == "시간":
        return now - timedelta(hours=amount)
    if unit == "일":
        return now - timedelta(days=amount)
    if unit == "주":
        return now - timedelta(weeks=amount)
    if unit == "개월":
        return now - timedelta(days=amount * 30)
    if unit == "년":
        return now - timedelta(days=amount * 365)
    return None


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
