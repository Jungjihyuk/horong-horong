import feedparser


class YozmConnector:
    RSS_URLS = [
        "https://yozm.wishket.com/magazine/list/all/?format=rss",  # 전체
        "https://yozm.wishket.com/magazine/ai/feed/",  # AI 탭
    ]

    def __init__(self, config: dict, max_items: int = 10):
        self.keywords = config.get("keywords", [])
        self.max_items = max_items

    def _fetch_feed(self, url: str) -> list[dict]:
        feed = feedparser.parse(url)
        if feed.bozo and not feed.entries:
            raise RuntimeError(f"요즘IT RSS 파싱 실패 ({url}): {feed.bozo_exception}")

        items = []
        for entry in feed.entries:
            title = (entry.get("title") or "").strip()
            link = (entry.get("link") or "").strip()
            summary = (entry.get("summary") or "").strip()[:300]
            pub_date = entry.get("published") or ""
            author = (entry.get("author") or "").strip()

            if not title or not link:
                continue

            items.append(
                {
                    "title": title,
                    "url": link,
                    "summary": summary,
                    "publishedAt": pub_date,
                    "sourceType": "yozm_it",
                    "sourceName": "요즘IT",
                    "author": author,
                }
            )

        return items

    def collect(self) -> list[dict]:
        seen_urls: set[str] = set()
        all_items: list[dict] = []

        for rss_url in self.RSS_URLS:
            try:
                feed_items = self._fetch_feed(rss_url)
            except RuntimeError:
                continue

            for item in feed_items:
                url = item["url"]
                if url in seen_urls:
                    continue
                seen_urls.add(url)

                if self.keywords:
                    combined = (item["title"] + " " + item["summary"]).lower()
                    if not any(kw.lower() in combined for kw in self.keywords):
                        continue

                all_items.append(item)

        return all_items[: self.max_items]
