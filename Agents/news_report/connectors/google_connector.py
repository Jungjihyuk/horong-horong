import urllib.request
import urllib.parse
import xml.etree.ElementTree as ET
from datetime import datetime


class GoogleConnector:
    RSS_BASE = "https://news.google.com/rss/search?q={query}&hl=ko&gl=KR&ceid=KR:ko"

    def __init__(self, config: dict, max_items: int = 10):
        self.keywords = config.get("keywords", ["AI"])
        self.max_items = max_items

    def collect(self) -> list[dict]:
        items = []
        seen_urls = set()

        for keyword in self.keywords:
            url = self.RSS_BASE.format(query=urllib.parse.quote(keyword))
            try:
                with urllib.request.urlopen(url, timeout=10) as resp:
                    body = resp.read().decode("utf-8")
                root = ET.fromstring(body)
                channel = root.find("channel")
                if channel is None:
                    continue
                for entry in channel.findall("item")[: self.max_items]:
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
                            "summary": description[:300],
                            "publishedAt": pub_date,
                            "sourceType": "google_news",
                            "sourceName": f"Google News ({keyword})",
                            "author": "",
                        }
                    )
            except Exception as e:
                raise RuntimeError(f"Google News '{keyword}' 수집 실패: {e}") from e

        return items[: self.max_items * len(self.keywords)]
