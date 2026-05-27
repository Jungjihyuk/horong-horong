"""관심사 기준으로 YouTube item의 관련성을 평가한다."""

from __future__ import annotations

import json
import re


def filter_relevance(
    items: list[dict],
    interest_keywords: list[str],
    provider,
    log_fn,
    threshold: int = 80,
) -> tuple[list[dict], int]:
    """YouTube item은 LLM으로 관련성을 평가하고, 다른 source는 그대로 유지한다."""
    keywords_str = ", ".join(interest_keywords)
    kept = []
    dropped = 0
    youtube_items = []

    for item in items:
        if item.get("sourceType") != "youtube":
            kept.append(item)
        else:
            youtube_items.append(item)

    batch_size = 5
    for batch_start in range(0, len(youtube_items), batch_size):
        batch = youtube_items[batch_start : batch_start + batch_size]
        try:
            batch_scores = score_youtube_relevance_batch(batch, keywords_str, provider)
        except Exception as error:
            log_fn(
                f"  관련성 배치 판정 실패, 단건 fallback 적용: {batch_start // batch_size + 1} - {error}"
            )
            batch_scores = {}

        for offset, item in enumerate(batch):
            local_idx = offset + 1
            title = item.get("title", "")
            score_reason = batch_scores.get(local_idx)
            if score_reason is None:
                try:
                    score, reason = score_youtube_relevance_single(
                        item, keywords_str, provider
                    )
                except Exception as error:
                    log_fn(f"  관련성 판정 실패 (drop): {title[:40]} - {error}")
                    dropped += 1
                    continue
            else:
                score, reason = score_reason

            score = adjust_relevance_score_for_title_hit(
                item, interest_keywords, score, log_fn
            )
            item["relevanceScore"] = score
            if reason:
                item["relevanceReason"] = reason
            if score >= threshold:
                log_fn(f"  관련성 {score} (유지): {title[:40]}")
                kept.append(item)
            else:
                log_fn(f"  관련성 {score} (제외): {title[:40]}")
                dropped += 1

    log_fn(f"Relevance filter: kept {len(kept)}, dropped {dropped}")
    return kept, dropped


def score_youtube_relevance_batch(
    batch: list[dict],
    keywords_str: str,
    provider,
) -> dict[int, tuple[int, str]]:
    """YouTube item 여러 개를 한 번의 LLM 호출로 관련성 평가한다."""
    items_text = []
    for offset, item in enumerate(batch):
        local_idx = offset + 1
        title = item.get("title", "")
        content = (item.get("contentText", "") or item.get("summary", ""))[:1200]
        items_text.append(
            f"[{local_idx}] 영상 제목: {title}\n"
            f"영상 자막/설명 발췌:\n{content}"
        )

    prompt = (
        f"관심사: {keywords_str}\n\n"
        f"아래 YouTube 영상 {len(batch)}개의 관심사 연관도를 각각 0~100 점수로 평가하세요.\n"
        "판단 기준:\n"
        "- 제목에 관심사 키워드가 명시되어 있고 본문이 그 주제를 실제로 다룬다면 80 이상.\n"
        "- 관심사와 직접 맞닿는 핵심 소재를 다룬다면 90 이상.\n"
        "- 관심사와 접점이 희박한 일반 콘텐츠(예: 개인 매매 일지·잡담·무관 기술 뉴스)는 50 미만.\n\n"
        f"영상 목록:\n{chr(10).join(items_text)}\n\n"
        'JSON 배열만 정확히 출력하세요: [{"index":1,"score":85,"reason":"한 줄 근거"}]'
    )
    raw = provider.run(prompt)
    match = re.search(r"\[.*\]", raw, re.DOTALL)
    if not match:
        raise ValueError("응답에 JSON 배열 없음")
    parsed = json.loads(match.group())
    scores: dict[int, tuple[int, str]] = {}
    for entry in parsed:
        idx = int(entry.get("index", 0))
        score = max(0, min(100, int(entry.get("score", 0))))
        reason = str(entry.get("reason", ""))
        if idx:
            scores[idx] = (score, reason)
    return scores


def score_youtube_relevance_single(item: dict, keywords_str: str, provider) -> tuple[int, str]:
    """YouTube item 하나를 LLM으로 관련성 평가한다."""
    title = item.get("title", "")
    content = (item.get("contentText", "") or item.get("summary", ""))[:4000]
    prompt = (
        f"관심사: {keywords_str}\n\n"
        f"영상 제목: {title}\n\n"
        f"영상 자막/설명 (앞 4000자):\n{content}\n\n"
        "위 영상이 관심사와 얼마나 연관되는지 0~100 점수로 평가하세요.\n"
        "판단 기준:\n"
        "- 제목에 관심사 키워드가 명시되어 있고 본문이 그 주제를 실제로 다룬다면 80 이상.\n"
        "- 관심사와 직접 맞닿는 핵심 소재를 다룬다면 90 이상.\n"
        "- 관심사와 접점이 희박한 일반 콘텐츠(예: 개인 매매 일지·잡담·무관 기술 뉴스)는 50 미만.\n"
        "다음 JSON 만 정확히 출력하세요 (다른 텍스트 없이):\n"
        '{"score": <정수 0-100>, "reason": "<한 줄 근거>"}'
    )
    raw = provider.run(prompt)
    match = re.search(r"\{.*?\}", raw, re.DOTALL)
    if not match:
        raise ValueError("응답에 JSON 블록 없음")
    parsed = json.loads(match.group())
    score = max(0, min(100, int(parsed.get("score", 0))))
    reason = str(parsed.get("reason", ""))
    return score, reason


def adjust_relevance_score_for_title_hit(
    item: dict,
    interest_keywords: list[str],
    score: int,
    log_fn,
) -> int:
    """제목에 관심 키워드가 직접 있으면 최소 관련성 점수를 보정한다."""
    title = item.get("title", "")
    title_lower = title.lower()
    title_hit = next(
        (
            keyword
            for keyword in interest_keywords
            if keyword.strip() and keyword.strip().lower() in title_lower
        ),
        None,
    )
    if title_hit and score < 80:
        log_fn(
            f"  제목 키워드 '{title_hit}' 일치 → 점수 {score} → 80 보정: {title[:40]}"
        )
        return 80
    return score
