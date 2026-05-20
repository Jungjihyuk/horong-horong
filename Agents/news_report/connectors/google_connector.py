import urllib.request
import urllib.parse
import xml.etree.ElementTree as ET
from datetime import datetime

from ._text import clean_summary


class GoogleConnector:
    RSS_BASE = "https://news.google.com/rss/search?q={query}&hl=ko&gl=KR&ceid=KR:ko"

    def __init__(self, config: dict, max_items: int = 10):
        self.keywords = config.get("keywords", ["AI"])
        self.max_items = max_items

    def collect(self) -> list[dict]:
        # `max_items` = 이 소스가 최종 반환할 *총합* 상한. 키워드가 여러 개면 균등 분배해서 채운다.
        keyword_count = max(1, len(self.keywords))
        per_keyword_quota = max(1, self.max_items // keyword_count + (1 if self.max_items % keyword_count else 0))

        items: list[dict] = []
        seen_urls: set[str] = set()

        for keyword in self.keywords:
            if len(items) >= self.max_items:
                break
            url = self.RSS_BASE.format(query=urllib.parse.quote(keyword))
            try:
                with urllib.request.urlopen(url, timeout=10) as resp:
                    body = resp.read().decode("utf-8")
                root = ET.fromstring(body)
                channel = root.find("channel")
                if channel is None:
                    continue
                per_kw_added = 0
                for entry in channel.findall("item"):
                    if per_kw_added >= per_keyword_quota or len(items) >= self.max_items:
                        break
                    title = (entry.findtext("title") or "").strip()
                    link = (entry.findtext("link") or "").strip()
                    description = (entry.findtext("description") or "").strip()
                    pub_date = entry.findtext("pubDate") or ""

                    if not title or not link or link in seen_urls:
                        continue
                    seen_urls.add(link)

                    items.append(
                        {
                            "title": title,
                            "url": link,
                            "summary": clean_summary(description),
                            "publishedAt": pub_date,
                            "sourceType": "google_news",
                            "sourceName": f"Google News ({keyword})",
                            "author": "",
                        }
                    )
                    per_kw_added += 1
            except Exception as e:
                raise RuntimeError(f"Google News '{keyword}' 수집 실패: {e}") from e

        return items[: self.max_items]
