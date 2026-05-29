"""뉴스 item과 YouTube transcript를 LLM으로 요약한다."""

from __future__ import annotations

import json
import re


def summarize_transcripts(
    items: list[dict],
    interest_keywords: list[str],
    provider,
    log_fn,
) -> list[dict]:
    """긴 YouTube transcript를 먼저 요약해 이후 뉴스 요약 stage의 입력으로 사용한다."""
    keywords_str = ", ".join(interest_keywords)
    targets = [
        item for item in items
        if item.get("sourceType") == "youtube"
        and len(item.get("contentText", "")) >= 200
    ]
    batch_size = 3
    for batch_start in range(0, len(targets), batch_size):
        batch = targets[batch_start : batch_start + batch_size]
        try:
            summaries = summarize_transcript_batch(batch, keywords_str, provider)
            for offset, item in enumerate(batch):
                summary = summaries.get(offset + 1, "").strip()
                if summary:
                    item["llmSummary"] = summary
                    log_fn(f"  transcript 요약 완료: {item.get('title', '')[:40]}")
        except Exception as error:
            log_fn(
                f"  transcript 요약 배치 실패, 단건 fallback 적용: {batch_start // batch_size + 1} - {error}"
            )
            for item in batch:
                try:
                    result = summarize_transcript_single(
                        item, keywords_str, provider
                    ).strip()
                    if result:
                        item["llmSummary"] = result
                        log_fn(f"  transcript 요약 완료: {item.get('title', '')[:40]}")
                except Exception as single_error:
                    log_fn(f"  transcript 요약 실패: {single_error}")
    return items


def summarize_transcript_batch(
    batch: list[dict],
    keywords_str: str,
    provider,
) -> dict[int, str]:
    """YouTube transcript 여러 개를 한 번의 LLM 호출로 요약한다."""
    items_text = []
    for offset, item in enumerate(batch):
        local_idx = offset + 1
        items_text.append(
            f"[{local_idx}] 영상 제목: {item.get('title', '')}\n"
            f"자막:\n{item.get('contentText', '')[:3000]}"
        )
    prompt = (
        "다음 YouTube 영상 자막들을 아래 지침에 따라 각각 요약해주세요.\n\n"
        f"지침:\n"
        f"- 관심사({keywords_str})와 연관된 핵심 내용 위주로 요약\n"
        f"- 멤버십 가입 안내, 구독 요청 등 홍보 내용은 절대 포함하지 말 것\n"
        f"- 각 영상 summary는 3~5개의 완전한 문장으로 작성\n"
        f"- JSON 배열만 출력\n\n"
        f"영상 목록:\n{chr(10).join(items_text)}\n\n"
        '형식: [{"index":1,"summary":"요약문"}]'
    )
    raw = provider.run(prompt).strip()
    match = re.search(r"\[.*\]", raw, re.DOTALL)
    if not match:
        raise ValueError("응답에 JSON 배열 없음")
    parsed = json.loads(match.group())
    summaries: dict[int, str] = {}
    for entry in parsed:
        idx = int(entry.get("index", 0))
        summary = str(entry.get("summary", "")).strip()
        if idx and summary:
            summaries[idx] = summary
    return summaries


def summarize_transcript_single(item: dict, keywords_str: str, provider) -> str:
    """YouTube transcript 하나를 LLM으로 요약한다."""
    transcript = item.get("contentText", "")
    prompt = (
        f"다음은 유튜브 영상의 자막입니다. 아래 지침에 따라 요약해주세요.\n\n"
        f"지침:\n"
        f"- 관심사({keywords_str})와 연관된 핵심 내용 위주로 요약\n"
        f"- 각 줄은 반드시 30자 이상의 완전한 문장으로 작성\n"
        f"- 멤버십 가입 안내, 구독 요청 등 홍보 내용은 절대 포함하지 말 것\n"
        f"- 3~5줄로 요약, 요약문만 출력\n\n"
        f"영상 제목: {item.get('title', '')}\n\n"
        f"자막:\n{transcript[:6000]}"
    )
    return provider.run(prompt)


def summarize_items(
    items: list[dict],
    interest_keywords: list[str],
    provider,
    log_fn,
) -> list[dict]:
    """뉴스 item 본문을 headline과 bullet 구조로 요약한다."""
    if not items:
        return items

    batch_size = 5
    targets = items[:20]
    keywords_str = ", ".join(interest_keywords) if interest_keywords else "(전 영역)"

    for batch_start in range(0, len(targets), batch_size):
        batch = targets[batch_start : batch_start + batch_size]
        items_text = []
        for offset, item in enumerate(batch):
            local_idx = offset + 1
            transcript_or_content = (
                item.get("llmSummary")
                or item.get("contentText")
                or item.get("summary", "")
            )[:1500]
            items_text.append(
                f"[{local_idx}] 제목: {item.get('title', '')}\n"
                f"카테고리: {item.get('category', '기타')}\n"
                f"본문/자막 발췌:\n{transcript_or_content}"
            )
        prompt = (
            f"다음 뉴스 항목 {len(batch)} 개를 관심사({keywords_str}) 기준으로 분석해 주세요.\n"
            "각 항목에 대해 다음 JSON 형식으로 응답하세요:\n"
            "- index: 항목 번호 (위에 표기된 1, 2, …)\n"
            "- headline: 60~100자, 사건의 핵심을 한 문장으로. 구체 수치·기관명·인물명 포함.\n"
            "- bullets: 30~60자짜리 서브 포인트 *2~3개* 배열. 사실 위주.\n"
            "- reason: 관심사와의 연결 근거 한 줄 (30자 내외).\n"
            "주의: 멤버십 가입·구독 안내·광고성 내용 절대 포함 금지. 추측·메타 문장 금지.\n\n"
            f"뉴스 목록:\n{chr(10).join(items_text)}\n\n"
            'JSON 배열만 출력 (다른 텍스트 없이): [{"index":1,"headline":"...","bullets":["...","..."],"reason":"..."}]'
        )

        try:
            result_text = provider.run(prompt)
            json_match = re.search(r"\[.*\]", result_text, re.DOTALL)
            if not json_match:
                raise ValueError("응답에 JSON 배열 없음")
            summaries = json.loads(json_match.group(0))
            for summary in summaries:
                local_idx = int(summary.get("index", 0)) - 1
                if 0 <= local_idx < len(batch):
                    target = batch[local_idx]
                    headline = str(summary.get("headline", "")).strip()
                    bullets_raw = summary.get("bullets") or []
                    bullets = [
                        str(bullet).strip()
                        for bullet in bullets_raw
                        if str(bullet).strip()
                    ][:3]
                    reason = str(summary.get("reason", "")).strip()
                    if headline:
                        target["headline"] = headline
                        target["llmSummary"] = headline
                    if bullets:
                        target["bullets"] = bullets
                    if reason:
                        target["relevanceReason"] = reason
            log_fn(
                f"  요약 배치 {batch_start // batch_size + 1}: {len(batch)} 처리"
            )
        except Exception as error:
            log_fn(f"LLM 요약 배치 실패, fallback 적용: {error}")

    for item in items:
        if not item.get("headline"):
            raw = (item.get("summary") or item.get("contentText") or "").strip()
            if raw:
                item["headline"] = raw[:80] + ("…" if len(raw) > 80 else "")
            item.setdefault("bullets", [])

    return items
