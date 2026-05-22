#!/usr/bin/env python3
"""
HorongHorong News Report Pipeline Runner
Usage: python3 runner.py --request <request.json> --result <result.json> --log <logfile> [--output-dir <dir>]
"""

import argparse
import json
import os
import re
import sys
import traceback
from datetime import datetime, timedelta, timezone


KST = timezone(timedelta(hours=9))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", required=True)
    parser.add_argument("--result", required=True)
    parser.add_argument("--log", required=True)
    args = parser.parse_args()

    os.makedirs(os.path.dirname(os.path.abspath(args.log)), exist_ok=True)
    log_file = open(args.log, "w", encoding="utf-8", buffering=1)

    def log(msg):
        ts = datetime.now(KST).strftime("%Y-%m-%d %H:%M:%S KST")
        line = f"[{ts}] {msg}"
        print(line, file=log_file, flush=True)

    def step(name):
        print(f"STEP:{name}", flush=True)
        log(f"STEP: {name}")

    started_at = datetime.now(timezone.utc).isoformat()
    request = {}

    try:
        with open(args.request, "r", encoding="utf-8") as f:
            request = json.load(f)

        job_id = request["jobId"]
        provider = request.get("provider", "claude")
        interest_keywords = request.get("interestKeywords", ["AI", "개발", "생산성", "자동화"])
        max_items = request.get("maxItemsPerSource", 10)
        sources = request.get("sources", [])
        output_dir = request.get("outputDir", ".")

        log(
            f"Job started: {job_id}, provider: {provider}, keywords: {interest_keywords}"
        )

        script_dir = os.path.dirname(os.path.abspath(__file__))
        sys.path.insert(0, script_dir)

        from connectors.youtube_connector import YouTubeConnector
        from connectors.google_connector import GoogleConnector
        from connectors.linkedin_connector import LinkedInConnector
        from connectors.yozm_connector import YozmConnector
        from providers.claude_cli import ClaudeCliProvider
        from providers.codex_cli import CodexCliProvider
        from providers.gemini_cli import GeminiCliProvider
        from providers.opencode_cli import OpencodeCliProvider
        from ontology import load_or_build as load_or_build_ontology
        from ontology import keyword_match as ontology_keyword_match

        connector_map = {
            "youtube": YouTubeConnector,
            "google_news": GoogleConnector,
            "linkedin": LinkedInConnector,
            "yozm_it": YozmConnector,
        }
        provider_map = {
            "claude": ClaudeCliProvider,
            "codex": CodexCliProvider,
            "gemini": GeminiCliProvider,
            "opencode": OpencodeCliProvider,
        }

        step("collect")
        all_items = []
        source_stats = {}
        warnings = []

        for source in sources:
            stype = source.get("type")
            if not source.get("enabled", True) or stype not in connector_map:
                continue
            connector = connector_map[stype](config=source, max_items=max_items)
            log(f"Collecting from {stype}...")
            try:
                items = connector.collect()
                source_stats[stype] = {
                    "fetched": len(items),
                    "used": len(items),
                    "failed": 0,
                }
                all_items.extend(items)
                log(f"  {stype}: {len(items)} items")
            except Exception as e:
                warn = f"{stype} 수집 실패: {e}"
                warnings.append(warn)
                source_stats[stype] = {"fetched": 0, "used": 0, "failed": 1}
                log(f"  {stype} ERROR: {e}")

        log(f"Total collected: {len(all_items)} items")

        step("normalize")
        normalized = _normalize(all_items)
        log(f"Normalized: {len(normalized)}")

        step("dedupe")
        deduped = _dedupe(normalized)
        log(f"Deduped: {len(deduped)}")

        # provider 는 ontology 클러스터링에도 필요하므로 classify 이전에 인스턴스화.
        llm_cls = provider_map.get(provider, ClaudeCliProvider)
        llm = llm_cls()

        step("ontology")
        ontology_path = os.path.join(output_dir, "data", "ontology", "news_ontology.json")
        # 구 경로(`data/cache/news_ontology.json`) 에 파일이 남아있고 새 경로엔 없으면 1회성 이동.
        legacy_ontology_path = os.path.join(output_dir, "data", "cache", "news_ontology.json")
        if os.path.isfile(legacy_ontology_path) and not os.path.isfile(ontology_path):
            try:
                os.makedirs(os.path.dirname(ontology_path), exist_ok=True)
                os.replace(legacy_ontology_path, ontology_path)
                log(f"  ontology 파일 이동: {legacy_ontology_path} → {ontology_path}")
            except Exception as e:
                log(f"  ontology 파일 이동 실패: {e}")
        ontology, ontology_status = load_or_build_ontology(
            interest_keywords, llm, ontology_path, log_fn=log
        )
        log(
            f"Ontology {ontology_status}: {len(ontology.categories)} categories "
            f"({', '.join(ontology.labels())})"
        )

        step("classify")
        classified = _classify(deduped, ontology)
        log(f"Classified: {len(classified)}")

        step("relevance_filter")
        filtered, dropped_count = _filter_relevance(
            classified, interest_keywords, llm, log
        )
        yt_stats = source_stats.get("youtube")
        if yt_stats is not None:
            yt_stats["used"] = sum(
                1 for it in filtered if it.get("sourceType") == "youtube"
            )
            yt_stats["filteredOut"] = dropped_count
        log(f"Relevance-filtered: {len(filtered)}")

        step("rank")
        ranked = _rank(filtered, interest_keywords, ontology)
        log(f"Ranked: {len(ranked)}")

        step("summarize")
        ranked = _summarize_transcripts(ranked, interest_keywords, llm, log)
        summarized = _summarize(ranked, interest_keywords, llm, log)

        # 카테고리별 그룹화 — 트렌드 요약 + render 양쪽에서 사용.
        by_category: dict = {}
        for item in summarized:
            cat = item.get("category", "기타")
            by_category.setdefault(cat, []).append(item)

        step("trend_summary")
        category_keywords = {
            cat: _extract_keyword_stats(items, top_n=5)
            for cat, items in by_category.items()
        }
        category_trends = _summarize_category_trends(by_category, llm, log)
        log(f"Trend summary: {len(category_trends)} category 요약 생성")

        step("render")
        now = datetime.now()
        today_str = now.strftime("%Y-%m-%d")
        # 파일명은 분 단위까지 포함 → 같은 날 여러 번 돌려도 덮어쓰지 않음.
        file_stamp = now.strftime("%Y-%m-%d-%H%M")
        generated_at_human = now.strftime("%Y-%m-%d %H:%M")
        report_rel = f"data/reports/{file_stamp}.md"
        meta_rel = f"data/meta/{file_stamp}.meta.json"
        report_full = os.path.join(output_dir, report_rel)
        meta_full = os.path.join(output_dir, meta_rel)
        os.makedirs(os.path.dirname(report_full), exist_ok=True)
        os.makedirs(os.path.dirname(meta_full), exist_ok=True)

        md = _render(
            summarized,
            today_str,
            generated_at_human,
            interest_keywords,
            source_stats,
            warnings,
            ontology,
            category_keywords,
            category_trends,
        )
        with open(report_full, "w", encoding="utf-8") as f:
            f.write(md)
        log(f"Report written: {report_full}")

        meta = {
            "jobId": job_id,
            "reportDate": today_str,
            "generatedAt": now.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "reportPath": report_rel,
            "itemCount": len(summarized),
            "interestKeywords": interest_keywords,
            "ontologySnapshot": [
                {"label": c.label, "keywords": list(c.keywords)}
                for c in ontology.categories
            ],
            "categoryCounts": {cat: len(items) for cat, items in by_category.items()},
            "categoryKeywords": category_keywords,
            "categoryTrendSummary": category_trends,
            "topItems": [
                {
                    "title": i.get("title", ""),
                    "url": i.get("url", ""),
                    "category": i.get("category", ""),
                    "sourceType": i.get("sourceType", ""),
                    "importanceScore": i.get("importanceScore", 0),
                    "publishedAt": i.get("publishedAt", ""),
                    "headline": i.get("headline") or i.get("llmSummary", ""),
                }
                for i in summarized[:20]
            ],
            "sourceStats": source_stats,
            "warnings": warnings,
        }
        with open(meta_full, "w", encoding="utf-8") as f:
            json.dump(meta, f, ensure_ascii=False, indent=2)

        step("index")
        has_failures = any(v.get("failed", 0) > 0 for v in source_stats.values())
        status = "partial_success" if has_failures else "success"

        result = {
            "jobId": job_id,
            "status": status,
            "startedAt": started_at,
            "endedAt": datetime.now(timezone.utc).isoformat(),
            "reportPath": report_rel,
            "metaPath": meta_rel,
            "sourceStats": source_stats,
            "topItems": [
                {
                    "title": i.get("title", ""),
                    "url": i.get("url", ""),
                    "importanceScore": i.get("importanceScore", 0),
                    "category": i.get("category", "기타"),
                }
                for i in summarized[:5]
            ],
            "warnings": warnings,
            "errorCode": None,
            "errorMessage": None,
        }
        with open(args.result, "w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False, indent=2)

        log(f"Job completed: {status}")
        log_file.close()
        sys.exit(0)

    except Exception as e:
        tb = traceback.format_exc()
        log(f"EXCEPTION: {tb}")

        error_result = {
            "jobId": request.get("jobId", "unknown"),
            "status": "failed",
            "startedAt": started_at,
            "endedAt": datetime.now(timezone.utc).isoformat(),
            "reportPath": None,
            "metaPath": None,
            "sourceStats": {},
            "topItems": [],
            "warnings": [],
            "errorCode": "E_RUNNER_EXCEPTION",
            "errorMessage": str(e),
        }
        try:
            with open(args.result, "w", encoding="utf-8") as f:
                json.dump(error_result, f, ensure_ascii=False, indent=2)
        except Exception:
            pass

        log_file.close()
        sys.exit(1)


def _normalize(items):
    result = []
    for item in items:
        norm = {
            "title": item.get("title", "").strip(),
            "url": item.get("url", ""),
            "publishedAt": item.get("publishedAt", ""),
            "summary": item.get("summary", ""),
            "contentText": item.get("contentText", item.get("summary", "")),
            "sourceType": item.get("sourceType", ""),
            "sourceName": item.get("sourceName", ""),
            "author": item.get("author", ""),
        }
        if norm["title"] and norm["url"]:
            result.append(norm)
    return result


# 카테고리 키워드 통계 추출용 불용어 (한글·영문). 일반적이면서 정보량 적은 단어들.
_STOPWORDS = {
    # 한국어 조사·접속사·일반 단어
    "의", "을", "를", "이", "가", "은", "는", "에", "에서", "에게", "와", "과",
    "도", "만", "로", "으로", "부터", "까지", "한", "하다", "위해", "통해",
    "있는", "있다", "없는", "없다", "되는", "되다", "관한", "대한", "대해",
    "또한", "또는", "그리고", "하지만", "이번", "오늘", "최근", "관련",
    "기사", "뉴스", "이번주", "지난", "지난주", "올해", "내년", "작년",
    # 영문 stopwords
    "the", "a", "an", "and", "or", "but", "to", "of", "in", "for", "on",
    "at", "by", "from", "with", "as", "is", "are", "was", "were", "be",
    "been", "being", "this", "that", "these", "those", "it", "its",
    "we", "you", "they", "i", "he", "she", "his", "her", "their", "our",
    "will", "would", "can", "could", "should", "may", "might", "do", "does",
    "did", "has", "have", "had", "not", "no", "if", "so", "than", "then",
    "into", "out", "up", "down", "off", "over", "more", "less", "new",
}

_TOKEN_RE = re.compile(r"[A-Za-z]+|[가-힯]+|[0-9]+")


def _extract_keyword_stats(items, top_n: int = 5) -> list[str]:
    """카테고리 안 기사 *제목* 토큰화 → 불용어 제거 → 빈도순 top N 키워드."""
    counts: dict[str, int] = {}
    for item in items:
        title = item.get("title", "") or ""
        for tok in _TOKEN_RE.findall(title):
            if len(tok) <= 1:
                continue
            key = tok.lower() if tok.isascii() else tok
            if key in _STOPWORDS:
                continue
            counts[key] = counts.get(key, 0) + 1
    # 빈도 같으면 사전순 (안정적 결과).
    sorted_kws = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))
    return [k for k, _ in sorted_kws[:top_n]]


def _summarize_category_trends(by_category, provider, log_fn) -> dict[str, str]:
    """모든 카테고리를 한 번의 LLM 호출에 담아 카테고리당 1~2줄 트렌드 요약 생성.

    실패 시 빈 dict 반환 — render 측이 줄을 생략한다.
    """
    if not by_category:
        return {}
    # 각 카테고리당 최대 8개 제목만 LLM 에 노출 (프롬프트 비대화 방지).
    blocks: list[str] = []
    for cat, items in by_category.items():
        if not items:
            continue
        titles = [it.get("title", "").strip() for it in items[:8] if it.get("title")]
        if not titles:
            continue
        blocks.append(
            "카테고리: " + cat + "\n" + "\n".join(f"- {t}" for t in titles)
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
    except Exception as e:
        log_fn(f"  trend summary LLM 호출 실패: {e}")
        return {}
    try:
        m = re.search(r"\[.*\]", raw, re.DOTALL)
        if not m:
            raise ValueError("응답에 JSON 배열 없음")
        parsed = json.loads(m.group(0))
        return {
            str(e.get("category", "")).strip(): str(e.get("summary", "")).strip()
            for e in parsed
            if isinstance(e, dict) and e.get("category") and e.get("summary")
        }
    except Exception as e:
        log_fn(f"  trend summary JSON 파싱 실패: {e}")
        return {}


def _dedupe(items):
    seen = set()
    result = []
    for item in items:
        url = item.get("url", "")
        if url and url not in seen:
            seen.add(url)
            result.append(item)
    return result


def _classify(items, ontology):
    # 함수 내부 lazy import — runner 가 main() 안에서 sys.path 를 만진 뒤에야 ontology 가 import 가능.
    from ontology import keyword_match
    for item in items:
        text = (
            item.get("title", "")
            + " "
            + item.get("summary", "")
            + " "
            + (item.get("contentText", "") or "")[:1000]
        )
        item["category"] = keyword_match(text, ontology)
    return items


def _rank(items, interest_keywords, ontology):
    # ontology 의 모든 카테고리에 균일한 보너스를 준다 (사용자 도메인을 모르기 때문).
    # "기타" 만 0 으로 두어 미분류 아이템의 우선순위를 낮춘다.
    category_bonus = {cat.label: 12 for cat in ontology.categories}
    category_bonus["기타"] = 0
    source_weight = {"youtube": 15, "google_news": 10, "yozm_it": 12, "linkedin": 8}

    for item in items:
        text = (
            item.get("title", "")
            + " "
            + item.get("summary", "")
            + " "
            + (item.get("contentText", "") or "")[:2000]
        ).lower()
        relevance = sum(1 for kw in interest_keywords if kw.lower() in text)
        cat = item.get("category", "기타")
        src = item.get("sourceType", "")
        item["importanceScore"] = min(
            100,
            relevance * 10
            + category_bonus.get(cat, 0)
            + source_weight.get(src, 10)
            + 40,
        )

    return sorted(items, key=lambda x: x.get("importanceScore", 0), reverse=True)


def _filter_relevance(items, interest_keywords, provider, log_fn, threshold=80):
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
            batch_scores = _score_youtube_relevance_batch(
                batch, keywords_str, provider
            )
        except Exception as e:
            log_fn(
                f"  관련성 배치 판정 실패, 단건 fallback 적용: {batch_start // batch_size + 1} - {e}"
            )
            batch_scores = {}

        for offset, item in enumerate(batch):
            local_idx = offset + 1
            title = item.get("title", "")
            score_reason = batch_scores.get(local_idx)
            if score_reason is None:
                try:
                    score, reason = _score_youtube_relevance_single(
                        item, keywords_str, provider
                    )
                except Exception as e:
                    log_fn(f"  관련성 판정 실패 (drop): {title[:40]} - {e}")
                    dropped += 1
                    continue
            else:
                score, reason = score_reason

            score = _adjust_relevance_score_for_title_hit(
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


def _score_youtube_relevance_batch(batch, keywords_str, provider) -> dict[int, tuple[int, str]]:
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
    m = re.search(r"\[.*\]", raw, re.DOTALL)
    if not m:
        raise ValueError("응답에 JSON 배열 없음")
    parsed = json.loads(m.group())
    scores: dict[int, tuple[int, str]] = {}
    for entry in parsed:
        idx = int(entry.get("index", 0))
        score = max(0, min(100, int(entry.get("score", 0))))
        reason = str(entry.get("reason", ""))
        if idx:
            scores[idx] = (score, reason)
    return scores


def _score_youtube_relevance_single(item, keywords_str, provider) -> tuple[int, str]:
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
    m = re.search(r"\{.*?\}", raw, re.DOTALL)
    if not m:
        raise ValueError("응답에 JSON 블록 없음")
    parsed = json.loads(m.group())
    score = max(0, min(100, int(parsed.get("score", 0))))
    reason = str(parsed.get("reason", ""))
    return score, reason


def _adjust_relevance_score_for_title_hit(item, interest_keywords, score, log_fn) -> int:
    title = item.get("title", "")
    title_lower = title.lower()
    title_hit = next(
        (kw for kw in interest_keywords
         if kw.strip() and kw.strip().lower() in title_lower),
        None,
    )
    if title_hit and score < 80:
        log_fn(
            f"  제목 키워드 '{title_hit}' 일치 → 점수 {score} → 80 보정: {title[:40]}"
        )
        return 80
    return score


def _summarize_transcripts(items, interest_keywords, provider, log_fn):
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
            summaries = _summarize_transcript_batch(batch, keywords_str, provider)
            for offset, item in enumerate(batch):
                summary = summaries.get(offset + 1, "").strip()
                if summary:
                    item["llmSummary"] = summary
                    log_fn(f"  transcript 요약 완료: {item.get('title', '')[:40]}")
        except Exception as e:
            log_fn(
                f"  transcript 요약 배치 실패, 단건 fallback 적용: {batch_start // batch_size + 1} - {e}"
            )
            for item in batch:
                try:
                    result = _summarize_transcript_single(
                        item, keywords_str, provider
                    ).strip()
                    if result:
                        item["llmSummary"] = result
                        log_fn(f"  transcript 요약 완료: {item.get('title', '')[:40]}")
                except Exception as single_error:
                    log_fn(f"  transcript 요약 실패: {single_error}")
    return items


def _summarize_transcript_batch(batch, keywords_str, provider) -> dict[int, str]:
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
    m = re.search(r"\[.*\]", raw, re.DOTALL)
    if not m:
        raise ValueError("응답에 JSON 배열 없음")
    parsed = json.loads(m.group())
    summaries: dict[int, str] = {}
    for entry in parsed:
        idx = int(entry.get("index", 0))
        summary = str(entry.get("summary", "")).strip()
        if idx and summary:
            summaries[idx] = summary
    return summaries


def _summarize_transcript_single(item, keywords_str, provider) -> str:
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


def _summarize(items, interest_keywords, provider, log_fn):
    """기사 본문 요약 — *headline (1줄)* + *bullets (2~3개)* 구조로 LLM 호출.

    - 배치 크기 5 (응답 잘림 방지)
    - 각 기사당 contentText 를 1500자까지 컨텍스트로 제공
    - LLM 응답 파싱 실패 시 RSS summary 첫 80자 + "…" 를 headline 으로 폴백
    """
    if not items:
        return items

    batch_size = 5
    targets = items[:20]  # 최대 20개까지만 LLM 요약 (그 이상은 비용 부담)
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
            for s in summaries:
                local_idx = int(s.get("index", 0)) - 1
                if 0 <= local_idx < len(batch):
                    target = batch[local_idx]
                    headline = str(s.get("headline", "")).strip()
                    bullets_raw = s.get("bullets") or []
                    bullets = [str(b).strip() for b in bullets_raw if str(b).strip()][:3]
                    reason = str(s.get("reason", "")).strip()
                    if headline:
                        target["headline"] = headline
                        target["llmSummary"] = headline  # 하위호환 (기존 필드)
                    if bullets:
                        target["bullets"] = bullets
                    if reason:
                        target["relevanceReason"] = reason
            log_fn(
                f"  요약 배치 {batch_start // batch_size + 1}: {len(batch)} 처리"
            )
        except Exception as e:
            log_fn(f"LLM 요약 배치 실패, fallback 적용: {e}")

    # Fallback — headline 없는 항목은 원본 summary 첫 80자로 채움.
    for item in items:
        if not item.get("headline"):
            raw = (item.get("summary") or item.get("contentText") or "").strip()
            if raw:
                item["headline"] = raw[:80] + ("…" if len(raw) > 80 else "")
            item.setdefault("bullets", [])

    return items


def _format_count(n) -> str:
    try:
        n = int(n)
    except (ValueError, TypeError):
        return str(n)
    if n >= 10000:
        return f"{n / 10000:.1f}만"
    if n >= 1000:
        return f"{n / 1000:.1f}천"
    return str(n)


def _format_duration(iso_duration: str) -> str:
    m = re.match(r"PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?", iso_duration)
    if not m:
        return iso_duration
    h, mi, s = m.group(1), m.group(2), m.group(3)
    parts = []
    if h:
        parts.append(f"{h}시간")
    if mi:
        parts.append(f"{mi}분")
    if s and not h:
        parts.append(f"{s}초")
    return " ".join(parts) or iso_duration


def _render(
    items,
    date_str,
    generated_at,
    interest_keywords,
    source_stats,
    warnings,
    ontology,
    category_keywords=None,
    category_trends=None,
):
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

    for w in warnings:
        lines.append(f"> ⚠️ {w}")

    lines.append("")

    categories = {}
    for item in items:
        cat = item.get("category", "기타")
        categories.setdefault(cat, []).append(item)

    # ontology 의 카테고리 순서대로 출력 → 그 외에 등장한 카테고리(예: "기타")는 마지막에.
    ordered_labels = [c.label for c in ontology.categories if c.label in categories]
    for label in categories.keys():
        if label not in ordered_labels:
            ordered_labels.append(label)

    for cat in ordered_labels:
        cat_items = categories.get(cat) or []
        lines.append(f"## {cat}")

        # 카테고리 트렌드 헤더 (통계 키워드 + LLM 한 줄 요약).
        kws = category_keywords.get(cat) or []
        trend = (category_trends.get(cat) or "").strip()
        if kws:
            lines.append(f"🔑 키워드: {', '.join(kws)}")
        if trend:
            lines.append(f"📈 트렌드: {trend}")
        if kws or trend:
            lines.append("")

        for i, item in enumerate(cat_items[:5], 1):
            title = item.get("title", "")
            url = item.get("url", "")
            score = item.get("importanceScore", 0)
            headline = (item.get("headline") or item.get("llmSummary") or "").strip()
            bullets = item.get("bullets") or []
            reason = (item.get("relevanceReason") or "").strip()

            lines.append(f"### {i}. [{title}]({url})")
            info_parts = [f"중요도: {score}/100", cat]
            rel_score = item.get("relevanceScore")
            if rel_score is not None:
                info_parts.append(f"관련성: {rel_score}/100")
            view_count = item.get("viewCount")
            like_count = item.get("likeCount")
            duration = item.get("duration", "")
            if view_count:
                info_parts.append(f"조회수: {_format_count(view_count)}")
            if like_count:
                info_parts.append(f"좋아요: {_format_count(like_count)}")
            if duration:
                info_parts.append(f"길이: {_format_duration(duration)}")
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
                f"{i}. {item.get('title', '')} 읽기 및 정리"
                for i, item in enumerate(items[:3], 1)
            ],
        ]
    )

    return "\n".join(lines)


if __name__ == "__main__":
    main()
