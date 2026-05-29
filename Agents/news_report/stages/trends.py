"""카테고리별 키워드와 트렌드 요약을 생성한다."""

from __future__ import annotations

import json
import re


STOPWORDS = {
    "의", "을", "를", "이", "가", "은", "는", "에", "에서", "에게", "와", "과",
    "도", "만", "로", "으로", "부터", "까지", "한", "하다", "위해", "통해",
    "있는", "있다", "없는", "없다", "되는", "되다", "관한", "대한", "대해",
    "또한", "또는", "그리고", "하지만", "이번", "오늘", "최근", "관련",
    "기사", "뉴스", "이번주", "지난", "지난주", "올해", "내년", "작년",
    "the", "a", "an", "and", "or", "but", "to", "of", "in", "for", "on",
    "at", "by", "from", "with", "as", "is", "are", "was", "were", "be",
    "been", "being", "this", "that", "these", "those", "it", "its",
    "we", "you", "they", "i", "he", "she", "his", "her", "their", "our",
    "will", "would", "can", "could", "should", "may", "might", "do", "does",
    "did", "has", "have", "had", "not", "no", "if", "so", "than", "then",
    "into", "out", "up", "down", "off", "over", "more", "less", "new",
}

TOKEN_RE = re.compile(r"[A-Za-z]+|[가-힯]+|[0-9]+")


def extract_keyword_stats(items: list[dict], top_n: int = 5) -> list[str]:
    """카테고리 안 기사 제목을 토큰화해 빈도순 top N 키워드를 반환한다."""
    counts: dict[str, int] = {}
    for item in items:
        title = item.get("title", "") or ""
        for token in TOKEN_RE.findall(title):
            if len(token) <= 1:
                continue
            key = token.lower() if token.isascii() else token
            if key in STOPWORDS:
                continue
            counts[key] = counts.get(key, 0) + 1

    sorted_keywords = sorted(counts.items(), key=lambda item: (-item[1], item[0]))
    return [keyword for keyword, _ in sorted_keywords[:top_n]]


def summarize_category_trends(by_category: dict, provider, log_fn) -> dict[str, str]:
    """카테고리별 제목 목록을 LLM에 전달해 1~2문장 트렌드 요약을 만든다."""
    if not by_category:
        return {}

    blocks: list[str] = []
    for category, items in by_category.items():
        if not items:
            continue
        titles = [item.get("title", "").strip() for item in items[:8] if item.get("title")]
        if not titles:
            continue
        blocks.append(
            "카테고리: " + category + "\n" + "\n".join(f"- {title}" for title in titles)
        )
    if not blocks:
        return {}

    prompt = (
        "다음은 각 카테고리에 묶인 뉴스 *제목 목록* 입니다.\n"
        "각 카테고리에 대해 *1~2 문장* 으로 최근 트렌드를 요약해 주세요.\n"
        "- 구체적인 주체(기업·인물·기술명) 와 핵심 동향이 드러나야 합니다.\n"
        "- '~에 대한 뉴스가 있습니다' 처럼 메타적 표현 금지. 사실 위주.\n"
        "- 80~160자.\n\n"
        "다음 JSON 만 정확히 출력하세요 (다른 텍스트 없이):\n"
        '[{"category": "...", "summary": "..."}]\n\n'
        + "\n\n".join(blocks)
    )
    try:
        raw = provider.run(prompt)
    except Exception as error:
        log_fn(f"  trend summary LLM 호출 실패: {error}")
        return {}
    try:
        match = re.search(r"\[.*\]", raw, re.DOTALL)
        if not match:
            raise ValueError("응답에 JSON 배열 없음")
        parsed = json.loads(match.group(0))
        return {
            str(entry.get("category", "")).strip(): str(entry.get("summary", "")).strip()
            for entry in parsed
            if isinstance(entry, dict) and entry.get("category") and entry.get("summary")
        }
    except Exception as error:
        log_fn(f"  trend summary JSON 파싱 실패: {error}")
        return {}
