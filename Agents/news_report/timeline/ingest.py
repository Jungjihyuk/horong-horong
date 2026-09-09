"""리포트 마크다운 → 카테고리별 시점 사건 목록.

여기에는 LLM 이 없다. 순수하게 결정적인 파싱·정제·중복 제거만 한다. 그래서 실행할
때마다 117편을 전량 다시 읽어도 밀리초면 끝나고, 교차-날짜 중복 제거가 항상 같은
결과를 낸다. 비싼 것은 월 종합(LLM)뿐이므로 메모이제이션은 거기에만 둔다.

정규식과 정제 규칙(별칭 클러스터·조사·불용어)은 MY_BRAIN vault 의
`.my-wiki/scripts/build_report_timeline.py` 에서 이식했다. 실제 리포트 6개월치로
다듬어진 값이라 임의로 손대면 카테고리 매칭과 주제어 품질이 조용히 나빠진다.
"""

from __future__ import annotations

import glob
import hashlib
import os
import re
import unicodedata
import urllib.parse
from collections import Counter, defaultdict

from contracts.timeline_artifact import TimelineEvent

# 리포트 본문이 아니라 실행 메타를 담은 섹션. 사건으로 세면 안 된다.
SKIP_HEADINGS = ("수집 현황", "오늘의 액션 아이템", "액션 아이템")

# 별칭 클러스터 — 질의 토큰이 여기 속하면 같은 클러스터의 헤딩도 함께 매칭한다.
# 리포트마다 헤딩 명칭이 조금씩 달라서(«AI 기업/모델» vs «AI모델») 느슨하게 묶어야 한다.
ALIAS_CLUSTERS = [
    {"금리", "거시", "거시경제", "매크로", "정책", "금융", "증시", "월가",
     "미국증시", "코스피", "환율", "채권", "경제", "외환", "종목"},
    {"ai", "반도체", "hbm", "기술", "칩", "파운드리"},
    {"aimodel", "ai모델", "모델", "llm", "에이전트", "rag", "지식"},
    {"ai도구", "ai코딩", "코딩", "codex", "claude", "도구", "개발", "it"},
    {"기업", "개별기업", "삼성전자", "sk하이닉스", "루미르", "에이피알", "스타트업", "커리어"},
]

# 각 클러스터의 대표 이름. 제안 목록과 타임라인 제목에 쓴다.
# 순서가 ALIAS_CLUSTERS 와 1:1 로 맞아야 한다.
CLUSTER_LABELS = [
    "금리/거시경제",
    "AI/반도체",
    "AI모델/에이전트",
    "AI도구/개발",
    "기업/커리어",
]
assert len(CLUSTER_LABELS) == len(ALIAS_CLUSTERS)

# 주제어 신호를 왜곡하는 조사·상투어·출처명.
NOISE = {"가능성이", "부담이", "있다는", "이후", "있다", "관련", "대한", "위한", "통해",
         "우려", "전망", "이라는", "라는", "대해", "된다", "됐다", "한다", "했다", "하는",
         "가운데", "속에", "이번", "지난", "오늘", "관측", "분석", "기대", "상황", "내용",
         "미국", "한국", "국내", "글로벌", "시장", "전체", "관심", "제기", "가장",
         "뉴시스", "개장전요것만", "개장전요것", "요것만", "빈난새", "백브리핑", "월가백브리핑",
         "김종학", "포커스", "단독", "속보", "종합", "전일", "이날", "일보", "뉴스", "기자", "방송"}

# 어절 끝 조사 제거용. 긴 것부터 지워야 «으로써» 가 «으로» 로 잘리지 않는다.
JOSA = ("으로써", "으로", "에서", "까지", "부터", "라는", "이라는", "에게", "에는",
        "을", "를", "이", "가", "은", "는", "의", "에", "도", "와", "과", "로", "만")


def norm(text: str) -> str:
    """비교용 정규화. 공백과 가운뎃점을 지워 «AI/반도체» 와 «AI 반도체» 를 같게 본다."""
    return unicodedata.normalize("NFC", text).replace(" ", "").replace("·", "").lower()


def query_terms(query: str) -> set[str]:
    """카테고리 질의를 매칭 토큰 집합으로. 별칭 클러스터까지 펼친다."""
    raw = [token for token in re.split(r"[\/,\s]+", query) if token]
    terms = {norm(token) for token in raw}
    for term in list(terms):
        for cluster in ALIAS_CLUSTERS:
            if term in cluster:
                terms |= cluster
    return terms


def heading_matches(heading: str, terms: set[str]) -> bool:
    normalized = norm(heading)
    if any(skip in heading for skip in SKIP_HEADINGS):
        return False
    return any(term and (term in normalized or normalized in term) for term in terms)


def clean_title(title: str) -> str:
    """편집 프리픽스와 언론사 꼬리를 걷어낸다."""
    text = title.strip()
    # 〔김종학의 뉴욕…〕, [속보], 【단독】 같은 머리 표지
    text = re.sub(r"^\s*[\[〔【(][^\]〕】)]{0,40}[\]〕】)]\s*", "", text)
    # "제목 - 머니투데이 - 머니투데이" 꼬리
    text = re.sub(r"(\s*-\s*[^-|]{1,20}){1,2}\s*$", "", text)
    if "|" in text:
        text = text.split("|")[0].strip()
    return text.strip() or "(제목 없음)"


def canonical_url(url: str) -> str:
    """동일 기사 판별용 URL. fragment 만 지우고 경로·query 는 남긴다 —
    Google News RSS 는 query 에 기사 식별자가 들어 있어 지우면 전부 같은 기사가 된다."""
    url = (url or "").strip()
    if not url:
        return ""
    try:
        parts = urllib.parse.urlsplit(url)
        return urllib.parse.urlunsplit(
            (parts.scheme.lower(), parts.netloc.lower(), parts.path, parts.query, "")
        )
    except ValueError:
        return url.split("#", 1)[0]


def normalized_title_key(title: str) -> str:
    """URL 이 없는 항목의 보조 중복 키."""
    cleaned = unicodedata.normalize("NFC", clean_title(title)).casefold()
    return re.sub(r"[\W_]+", "", cleaned)


def article_key(title: str, url: str) -> str:
    canonical = canonical_url(url)
    return f"url:{canonical}" if canonical else f"title:{normalized_title_key(title)}"


def first_sentence(trend: str, maxlen: int = 110) -> str:
    parts = re.split(r"(?<=[.。!?])\s+", trend)
    out = parts[0] if parts else trend
    if len(out) < 40 and len(parts) > 1:
        out = (out + " " + parts[1]).strip()
    return out[:maxlen].rstrip()


def strip_josa(word: str) -> str:
    changed = True
    while changed:
        changed = False
        for josa in JOSA:
            if word.endswith(josa) and len(word) - len(josa) >= 2:
                word = word[: -len(josa)]
                changed = True
                break
    return word


def clean_token(word: str) -> str | None:
    """주제어 후보 1개를 정제한다. 버릴 것이면 None."""
    word = strip_josa(word.strip())
    if len(word) < 2 or word in NOISE:
        return None
    if re.fullmatch(r"[0-9][0-9.,%]*", word):  # "22", "4.5%"
        return None
    if word.isascii() and word.islower():  # 영어 문장 조각. AI·HBM 등 대문자는 남긴다
        return None
    return word


def parse_report(path: str) -> list[dict]:
    """리포트 파일 1개 → 섹션 목록.

    형식: `## <카테고리>` / `🔑 키워드: …` / `📈 트렌드: …` / `### N. [제목](url)` +
    바로 다음 줄의 `> 중요도: NN/100 …`.
    """
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().split("\n")

    sections: list[dict] = []
    current: dict | None = None
    for index, line in enumerate(lines):
        heading = re.match(r"^##\s+(.+?)\s*$", line)
        if heading and not line.startswith("###"):
            current = {"heading": heading.group(1).strip(), "trend": "",
                       "items": [], "keywords": []}
            sections.append(current)
            continue
        if current is None:
            continue

        keywords = re.match(r"^🔑\s*키워드:\s*(.+)$", line)
        if keywords:
            current["keywords"] += [
                word.strip() for word in re.split(r"[,·]", keywords.group(1)) if word.strip()
            ]
        trend = re.match(r"^📈\s*트렌드:\s*(.+)$", line)
        if trend and not current["trend"]:
            current["trend"] = trend.group(1).strip()

        item = re.match(r"^###\s*\d+\.\s*\[(.+?)\]\((https?://[^)]+)\)", line)
        if item:
            importance = 0
            # 중요도는 제목 바로 아래 인용 줄에 있다. 2줄까지만 본다.
            for offset in range(index + 1, min(index + 3, len(lines))):
                found = re.search(r"중요도:\s*(\d+)", lines[offset])
                if found:
                    importance = int(found.group(1))
                    break
            current["items"].append((item.group(1).strip(), item.group(2).strip(), importance))
    return sections


def report_date_of(path: str) -> str | None:
    """파일명 앞머리의 날짜. 사건의 시점은 기사 발행일이 아니라 리포트 날짜다."""
    found = re.match(r"(\d{4}-\d{2}-\d{2})", os.path.basename(path))
    return found.group(1) if found else None


def event_id_for(category_id: str, date: str) -> str:
    return f"{category_id}-{date}-" + hashlib.sha256(
        f"{category_id}|{date}".encode("utf-8")
    ).hexdigest()[:8]


def parse_reports(
    reports_dir: str,
    *,
    since: str | None = None,
    until: str | None = None,
) -> list[tuple[str, list[dict]]]:
    """(리포트 날짜, 섹션 목록) 을 날짜 오름차순으로.

    파싱 결과를 여러 카테고리가 나눠 쓸 수 있게 분리했다 — 주제 «제안» 은 후보마다
    전체 리포트를 훑어야 하는데, 그때마다 117편을 다시 읽으면 낭비다.
    """
    parsed: list[tuple[str, list[dict]]] = []
    for path in sorted(glob.glob(os.path.join(reports_dir, "*.md"))):
        date = report_date_of(path)
        if not date:
            continue
        if (since and date < since) or (until and date > until):
            continue
        parsed.append((date, parse_report(path)))
    return parsed


def collect_events(
    reports_dir: str,
    category_id: str,
    terms: set[str],
    *,
    since: str | None = None,
    until: str | None = None,
    parsed: list[tuple[str, list[dict]]] | None = None,
) -> list[TimelineEvent]:
    """리포트 폴더 전체를 훑어 이 카테고리의 시점 사건 목록을 만든다.

    사건 1건 = 리포트 날짜 1개다. 그날 이 카테고리에 실린 기사 중 처음 등장한 것들을
    모아 대표 제목 1개와 불릿 몇 개로 만든다. 같은 기사가 여러 날 반복해 실리므로
    **처음 나온 날에만** 붙인다 — 그래서 날짜 오름차순으로 훑어야 한다.
    """
    per_date: dict[str, dict] = defaultdict(
        lambda: {"trends": [], "items": [], "headings": set(), "keywords": []}
    )
    if parsed is None:
        parsed = parse_reports(reports_dir, since=since, until=until)
    for date, sections in parsed:
        for section in sections:
            if not heading_matches(section["heading"], terms):
                continue
            bucket = per_date[date]
            bucket["headings"].add(section["heading"])
            if section["trend"]:
                bucket["trends"].append((len(section["items"]), section["trend"]))
            bucket["items"].extend(section["items"])
            bucket["keywords"].extend(section["keywords"])

    events: list[TimelineEvent] = []
    seen_articles: set[str] = set()
    for date in sorted(per_date):
        bucket = per_date[date]
        # 항목이 가장 많은 섹션의 트렌드를 그날의 대표로 삼는다.
        trend = sorted(bucket["trends"], key=lambda pair: -pair[0])[0][1] if bucket["trends"] else ""

        candidates = sorted(
            ((clean_title(title), url, importance) for title, url, importance in bucket["items"]),
            key=lambda item: (-item[2], norm(item[0]), item[0], canonical_url(item[1])),
        )
        daily: list[tuple[str, str, int, str]] = []
        daily_keys: set[str] = set()
        for title, url, importance in candidates:
            key = article_key(title, url)
            if key in daily_keys:
                continue
            daily_keys.add(key)
            daily.append((title, url, importance, key))

        fresh = [item for item in daily if item[3] not in seen_articles]
        seen_articles.update(item[3] for item in daily)
        # 트렌드 문장이 대표 제목을 맡으면 불릿에 2개, 아니면 첫 제목이 대표라 3개까지 쓴다.
        display_limit = 2 if trend else 3
        shown = fresh[:display_limit]
        if not shown:
            continue

        titles = [title for title, _, _, _ in shown]
        importance = max((item[2] for item in fresh), default=0)

        cleaned_keywords = [
            word for word in dict.fromkeys(clean_token(k) for k in bucket["keywords"]) if word
        ]
        # 그날 여러 제목에 겹쳐 나온 토큰(빈도 2 이상)도 그날의 주제어로 본다.
        frequency: Counter[str] = Counter()
        for title in titles:
            for word in set(re.findall(r"[가-힣A-Za-z][가-힣A-Za-z0-9]{1,}", title)):
                token = clean_token(word)
                if token:
                    frequency[token] += 1
        tags = sorted(
            set(cleaned_keywords) | {word for word, count in frequency.items() if count >= 2}
        )

        headline = first_sentence(trend) if trend else titles[0]
        bullets = titles if trend else titles[1:]
        events.append(
            TimelineEvent(
                event_id=event_id_for(category_id, date),
                date=date,
                title=headline,
                url=shown[0][1],
                importance=importance,
                bullets=bullets,
                tags=tags,
            )
        )
    return events
