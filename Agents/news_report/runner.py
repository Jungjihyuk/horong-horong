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
from datetime import datetime, timezone


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", required=True)
    parser.add_argument("--result", required=True)
    parser.add_argument("--log", required=True)
    args = parser.parse_args()

    os.makedirs(os.path.dirname(os.path.abspath(args.log)), exist_ok=True)
    log_file = open(args.log, "w", encoding="utf-8", buffering=1)

    def log(msg):
        ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
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

        step("classify")
        classified = _classify(deduped)
        log(f"Classified: {len(classified)}")

        llm_cls = provider_map.get(provider, ClaudeCliProvider)
        llm = llm_cls()

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
        ranked = _rank(filtered, interest_keywords)
        log(f"Ranked: {len(ranked)}")

        step("summarize")
        ranked = _summarize_transcripts(ranked, interest_keywords, llm, log)
        summarized = _summarize(ranked, interest_keywords, llm, log)

        step("render")
        today_str = datetime.now().strftime("%Y-%m-%d")
        report_rel = f"data/reports/{today_str}.md"
        meta_rel = f"data/meta/{today_str}.meta.json"
        report_full = os.path.join(output_dir, report_rel)
        meta_full = os.path.join(output_dir, meta_rel)
        os.makedirs(os.path.dirname(report_full), exist_ok=True)
        os.makedirs(os.path.dirname(meta_full), exist_ok=True)

        md = _render(summarized, today_str, interest_keywords, source_stats, warnings)
        with open(report_full, "w", encoding="utf-8") as f:
            f.write(md)
        log(f"Report written: {report_full}")

        meta = {
            "jobId": job_id,
            "reportDate": today_str,
            "reportPath": report_rel,
            "itemCount": len(summarized),
            "topItems": [
                {
                    "title": i.get("title", ""),
                    "url": i.get("url", ""),
                    "category": i.get("category", ""),
                    "importanceScore": i.get("importanceScore", 0),
                }
                for i in summarized[:5]
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


_CATEGORY_KEYWORDS = {
    "AI/반도체": [
        "AI",
        "인공지능",
        "GPU",
        "반도체",
        "LLM",
        "ChatGPT",
        "Claude",
        "Gemini",
        "OpenAI",
        "딥러닝",
        "머신러닝",
        "chip",
        "nvidia",
        "transformer",
        "에이전트",
        "생성형",
        "팔란티어",
        "실리콘밸리",
        "빅테크",
        "엔비디아",
    ],
    "미국증시/월가": [
        "나스닥",
        "S&P",
        "다우",
        "월가",
        "뉴욕증시",
        "월스트리트",
        "미증시",
        "주가",
        "증시",
        "랠리",
        "급등",
        "급락",
        "기술주",
        "빅테크",
        "애플",
        "테슬라",
        "메타",
        "구글",
        "알파벳",
        "마이크로소프트",
        "아마존",
    ],
    "매크로/정책": [
        "금리",
        "환율",
        "인플레이션",
        "Fed",
        "연준",
        "FOMC",
        "파월",
        "GDP",
        "채권",
        "관세",
        "무역",
        "경기침체",
        "달러",
        "부채한도",
        "트럼프",
        "바이든",
        "백악관",
        "의회",
        "정책",
    ],
    "개발/IT": [
        "개발",
        "Python",
        "Swift",
        "JavaScript",
        "API",
        "오픈소스",
        "GitHub",
        "Docker",
        "Kubernetes",
        "클라우드",
        "서버",
        "데이터베이스",
    ],
    "커리어/스타트업": [
        "취업",
        "이직",
        "연봉",
        "커리어",
        "스타트업",
        "채용",
        "직장",
        "면접",
        "VC",
        "펀딩",
        "유니콘",
        "IPO",
    ],
}


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


def _dedupe(items):
    seen = set()
    result = []
    for item in items:
        url = item.get("url", "")
        if url and url not in seen:
            seen.add(url)
            result.append(item)
    return result


def _classify(items):
    for item in items:
        text = (
            item.get("title", "")
            + " "
            + item.get("summary", "")
            + " "
            + item.get("contentText", "")[:1000]
        ).lower()
        category = "기타"
        best_cat = "기타"
        best_count = 0
        for cat, kws in _CATEGORY_KEYWORDS.items():
            count = sum(1 for kw in kws if kw.lower() in text)
            if count > best_count:
                best_count = count
                best_cat = cat
        item["category"] = best_cat if best_count > 0 else "기타"
    return items


def _rank(items, interest_keywords):
    category_bonus = {
        "AI/반도체": 20,
        "미국증시/월가": 18,
        "매크로/정책": 15,
        "개발/IT": 12,
        "커리어/스타트업": 8,
        "기타": 0,
    }
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
    for item in items:
        if item.get("sourceType") != "youtube":
            kept.append(item)
            continue
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
        try:
            raw = provider.run(prompt)
            m = re.search(r"\{.*?\}", raw, re.DOTALL)
            if not m:
                raise ValueError("응답에 JSON 블록 없음")
            parsed = json.loads(m.group())
            score = int(parsed.get("score", 0))
            reason = str(parsed.get("reason", ""))
        except Exception as e:
            log_fn(f"  관련성 판정 실패 (drop): {title[:40]} - {e}")
            dropped += 1
            continue

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
            score = 80

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


def _summarize_transcripts(items, interest_keywords, provider, log_fn):
    keywords_str = ", ".join(interest_keywords)
    for item in items:
        if item.get("sourceType") != "youtube":
            continue
        transcript = item.get("contentText", "")
        if len(transcript) < 200:
            continue
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
        try:
            result = provider.run(prompt).strip()
            if result:
                item["llmSummary"] = result
                log_fn(f"  transcript 요약 완료: {item.get('title', '')[:40]}")
        except Exception as e:
            log_fn(f"  transcript 요약 실패: {e}")
    return items


def _summarize(items, interest_keywords, provider, log_fn):
    if not items:
        return items

    def _item_content(item):
        if item.get("llmSummary"):
            return item["llmSummary"][:200]
        ct = item.get("contentText", "") or item.get("summary", "")
        return ct[:300]

    items_text = "\n".join(
        f"{i + 1}. [{item.get('category', '기타')}] {item.get('title', '')} - {_item_content(item)}"
        for i, item in enumerate(items[:10])
    )
    prompt = (
        f"다음 뉴스 항목들을 관심사({', '.join(interest_keywords)}) 기준으로 분석해주세요.\n"
        "각 항목에 대해 JSON 배열로 응답하세요.\n"
        '각 항목은: {"index": 번호, "summary": "핵심내용 요약(50자 이상, 구체적 수치·사건 포함)", "reason": "관심사 연결 근거(20자 이상)"} 형식입니다.\n'
        "주의: 멤버십 가입, 구독 안내 등 홍보성 내용은 요약에 절대 포함하지 마세요.\n\n"
        f"뉴스 목록:\n{items_text}\n\nJSON 배열만 출력하세요. 다른 텍스트 없이."
    )

    try:
        result_text = provider.run(prompt)
        json_match = re.search(r"\[.*?\]", result_text, re.DOTALL)
        if json_match:
            summaries = json.loads(json_match.group())
            for s in summaries:
                idx = s.get("index", 0) - 1
                if 0 <= idx < len(items):
                    items[idx]["llmSummary"] = s.get("summary", "")
                    items[idx]["relevanceReason"] = s.get("reason", "")
    except Exception as e:
        log_fn(f"LLM 요약 실패 (계속 진행): {e}")

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


def _render(items, date_str, interest_keywords, source_stats, warnings):
    lines = [
        f"# 뉴스 큐레이션 리포트 - {date_str}",
        f"생성일: {date_str}",
        f"관심사: {', '.join(interest_keywords)}",
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

    for cat, cat_items in sorted(categories.items()):
        lines.append(f"## {cat}")
        for i, item in enumerate(cat_items[:5], 1):
            title = item.get("title", "")
            url = item.get("url", "")
            score = item.get("importanceScore", 0)
            summary = item.get("llmSummary", item.get("summary", "")[:80])
            reason = item.get("relevanceReason", "")
            lines.append(f"### {i}. [{title}]({url})")
            # Build info line with metadata for YouTube videos
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
            if summary:
                lines.append(f"**{summary}**")
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
