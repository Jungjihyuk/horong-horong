"""뉴스 리포트를 Markdown 문서로 렌더링한다."""

from __future__ import annotations

import re


def format_count(value) -> str:
    """큰 숫자를 한국어 짧은 단위로 표시한다."""
    try:
        count = int(value)
    except (ValueError, TypeError):
        return str(value)
    if count >= 10000:
        return f"{count / 10000:.1f}만"
    if count >= 1000:
        return f"{count / 1000:.1f}천"
    return str(count)


def format_duration(iso_duration: str) -> str:
    """ISO 8601 duration 문자열을 사람이 읽기 쉬운 한국어 표현으로 바꾼다."""
    match = re.match(r"PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?", iso_duration)
    if not match:
        return iso_duration
    hours, minutes, seconds = match.group(1), match.group(2), match.group(3)
    parts = []
    if hours:
        parts.append(f"{hours}시간")
    if minutes:
        parts.append(f"{minutes}분")
    if seconds and not hours:
        parts.append(f"{seconds}초")
    return " ".join(parts) or iso_duration


def render_markdown_report(
    items: list[dict],
    date_str: str,
    generated_at: str,
    interest_keywords: list[str],
    source_stats: dict,
    warnings: list[str],
    ontology,
    category_keywords: dict | None = None,
    category_trends: dict | None = None,
) -> str:
    """뉴스 리포트 데이터를 Markdown 문자열로 변환한다."""
    category_keywords = category_keywords or {}
    category_trends = category_trends or {}

    keywords_line = ", ".join(interest_keywords) if interest_keywords else "(등록된 관심사 없음)"
    lines = [
        f"# 뉴스 큐레이션 리포트 - {date_str}",
        f"생성일: {generated_at}",
        f"관심사: {keywords_line}",
        "",
        "## 수집 현황",
    ]

    for source, stats in source_stats.items():
        icon = "✅" if stats.get("failed", 0) == 0 else "⚠️"
        lines.append(f"- {icon} {source}: {stats.get('used', 0)}개 수집")

    for warning in warnings:
        lines.append(f"> ⚠️ {warning}")

    lines.append("")

    categories = {}
    for item in items:
        category = item.get("category", "기타")
        categories.setdefault(category, []).append(item)

    ordered_labels = [
        category.label for category in ontology.categories if category.label in categories
    ]
    for label in categories.keys():
        if label not in ordered_labels:
            ordered_labels.append(label)

    for category in ordered_labels:
        category_items = categories.get(category) or []
        lines.append(f"## {category}")

        keywords = category_keywords.get(category) or []
        trend = (category_trends.get(category) or "").strip()
        if keywords:
            lines.append(f"🔑 키워드: {', '.join(keywords)}")
        if trend:
            lines.append(f"📈 트렌드: {trend}")
        if keywords or trend:
            lines.append("")

        for index, item in enumerate(category_items[:5], 1):
            title = item.get("title", "")
            url = item.get("url", "")
            score = item.get("importanceScore", 0)
            headline = (item.get("headline") or item.get("llmSummary") or "").strip()
            bullets = item.get("bullets") or []
            reason = (item.get("relevanceReason") or "").strip()

            lines.append(f"### {index}. [{title}]({url})")
            info_parts = [f"중요도: {score}/100", category]
            relevance_score = item.get("relevanceScore")
            if relevance_score is not None:
                info_parts.append(f"관련성: {relevance_score}/100")
            view_count = item.get("viewCount")
            like_count = item.get("likeCount")
            duration = item.get("duration", "")
            if view_count:
                info_parts.append(f"조회수: {format_count(view_count)}")
            if like_count:
                info_parts.append(f"좋아요: {format_count(like_count)}")
            if duration:
                info_parts.append(f"길이: {format_duration(duration)}")
            lines.append(f"> {' | '.join(info_parts)}")

            if headline:
                lines.append(f"**{headline}**")
            for bullet in bullets:
                lines.append(f"- {bullet}")
            if reason:
                lines.append(f"_{reason}_")
            lines.append("")

    lines.extend(
        [
            "## 오늘의 액션 아이템",
            *[
                f"{index}. {item.get('title', '')} 읽기 및 정리"
                for index, item in enumerate(items[:3], 1)
            ],
        ]
    )

    return "\n".join(lines)
