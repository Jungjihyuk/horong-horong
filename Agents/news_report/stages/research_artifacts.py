"""research artifact 묶음을 생성하는 stage 함수들."""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from datetime import datetime, timezone
from hashlib import sha1
import re
from typing import Protocol, cast

from contracts.research_artifact import (
    CategoryAssignment,
    CategoryDefinition,
    CategoryTaxonomy,
    ExtractedArticle,
    InsightBundle,
    KeywordInsight,
    KeywordMatch,
    Method,
    ReportContent,
    SourceCandidate,
    SourceInsight,
    SourceItem,
    TrendInsight,
)
from ontology import keyword_match
from ontology.models import NewsOntology
from providers.protocols import StructuredProvider
from tracing.events import TraceEventName
from stages.relevance_artifacts import (
    item_id_for,
    item_title,
    optional_text,
    required_text,
    source_type_for,
    text_for_relevance,
)


_TOKEN_RE: re.Pattern[str] = re.compile(r"[A-Za-z]+|[가-힯]+|[0-9]+")
_KEYWORD_STOPWORDS = {
    "의", "을", "를", "이", "가", "은", "는", "에", "에서", "와", "과",
    "도", "로", "으로", "대한", "관련", "최근", "뉴스", "the", "a", "an",
    "and", "or", "to", "of", "in", "for", "on", "with", "is", "are",
}


class TraceSink(Protocol):
    """research artifact stage가 필요로 하는 trace 기록 계약."""

    def write(
        self,
        event: TraceEventName,
        *,
        stage: str | None = None,
        duration_ms: int | None = None,
        payload: Mapping[str, object] | None = None,
        **payload_fields: object,
    ) -> object:
        """trace 이벤트를 기록한다."""
        ...


def build_source_items(items: Sequence[Mapping[str, object]]) -> list[SourceItem]:
    """정규화된 dict item을 SourceItem artifact로 변환한다."""
    source_items: list[SourceItem] = []
    for item in items:
        try:
            source_items.append(
                SourceItem(
                    source_type=source_type_for(item),
                    configured_source_id=optional_text(item, "configuredSourceId"),
                    item_id=item_id_for(item),
                    title=item_title(item),
                    url=required_text(item, "url"),
                    published_at=optional_text(item, "publishedAt"),
                    author=optional_text(item, "author"),
                    raw_summary=optional_text(item, "summary"),
                )
            )
        except ValueError:
            continue
    return source_items


def build_extracted_articles(
    items: Sequence[Mapping[str, object]],
    *,
    extracted_at: str,
) -> list[ExtractedArticle]:
    """정규화된 dict item에서 relevance/insight 입력 article artifact를 만든다."""
    articles: list[ExtractedArticle] = []
    for item in items:
        try:
            articles.append(
                ExtractedArticle(
                    item_id=item_id_for(item),
                    title=item_title(item),
                    url=required_text(item, "url"),
                    content_text=text_for_relevance(item),
                    extracted_at=extracted_at,
                )
            )
        except ValueError:
            continue
    return articles


def build_keyword_matches(
    articles: list[ExtractedArticle],
    interest_keywords: list[str],
) -> list[KeywordMatch]:
    """관심사 키워드가 article 텍스트에 직접 포함되는지 찾는다."""
    matches: list[KeywordMatch] = []
    for article in articles:
        text = f"{article.title}\n{article.content_text}".lower()
        for keyword in interest_keywords:
            normalized = keyword.strip()
            if not normalized:
                continue
            if normalized.lower() in text:
                matches.append(
                    KeywordMatch(
                        item_id=article.item_id,
                        interest_keyword=normalized,
                        matched_text=normalized,
                        match_type="exact",
                    )
                )
    return matches


def build_category_taxonomy(ontology: NewsOntology) -> CategoryTaxonomy:
    """현재 ontology snapshot을 CategoryTaxonomy artifact로 변환한다."""
    categories = [
        CategoryDefinition(
            category_id=category_id_for(category.label),
            name=category.label,
            description=category.description or f"{category.label} 관련 소식",
            keywords=list(category.keywords),
        )
        for category in ontology.categories
    ]
    return CategoryTaxonomy(
        taxonomy_id=f"taxonomy-{ontology.interestKeywordsHash or 'current'}",
        version=str(ontology.version),
        generated_from_keywords=list(ontology.interestKeywords),
        method=cast(Method, "rule"),
        categories=categories,
    )


def assign_categories(
    candidates: list[SourceCandidate],
    articles_by_item_id: Mapping[str, ExtractedArticle],
    ontology: NewsOntology,
    taxonomy: CategoryTaxonomy,
) -> list[CategoryAssignment]:
    """SourceCandidate를 ontology 카테고리에 배정한다."""
    assignments: list[CategoryAssignment] = []
    category_id_by_name = {
        category.name: category.category_id
        for category in taxonomy.categories
    }
    for candidate in candidates:
        article = articles_by_item_id.get(candidate.item_id)
        text = article.content_text if article else candidate.title
        category_name = keyword_match(text, ontology)
        category_id = category_id_by_name.get(
            category_name,
            category_id_for(category_name),
        )
        assignments.append(
            CategoryAssignment(
                candidate_id=candidate.candidate_id,
                category_id=category_id,
                category_name=category_name,
                confidence=0.8 if category_name != "기타" else 0.4,
                reason=f"ontology 키워드 기준으로 '{category_name}' 카테고리에 배정했다.",
                method="rule",
                taxonomy_id=taxonomy.taxonomy_id,
                taxonomy_version=taxonomy.version,
            )
        )
    return assignments


def build_source_insights(
    candidates: list[SourceCandidate],
    articles_by_item_id: Mapping[str, ExtractedArticle],
    assignments_by_candidate_id: Mapping[str, CategoryAssignment],
    provider: StructuredProvider,
    *,
    warnings: list[str] | None = None,
    trace: TraceSink | None = None,
) -> list[SourceInsight]:
    """각 SourceCandidate에서 리포트에 쓸 SourceInsight를 생성한다."""
    insights: list[SourceInsight] = []
    stage_warnings = warnings if warnings is not None else []
    for index, candidate in enumerate(candidates, 1):
        article = articles_by_item_id.get(candidate.item_id)
        prompt = build_source_insight_prompt(candidate, article)
        try:
            generated = provider.generate_json(prompt, SourceInsight)
        except Exception as error:
            warning = (
                f"source insight 생성 실패: {candidate.title} "
                f"({type(error).__name__}: {str(error)[:200]})"
            )
            stage_warnings.append(warning)
            if trace:
                _ = trace.write(
                    "stage_failed",
                    stage="source_insight",
                    payload={
                        "candidate_id": candidate.candidate_id,
                        "item_id": candidate.item_id,
                        "title": candidate.title,
                        "schema": "SourceInsight",
                        "error_type": type(error).__name__,
                        "error_message": str(error)[:500],
                    },
                )
            continue

        assignment = assignments_by_candidate_id.get(candidate.candidate_id)
        insights.append(
            generated.model_copy(
                update={
                    "source_insight_id": f"source-insight-{index:03d}",
                    "candidate_id": candidate.candidate_id,
                    "category_id": assignment.category_id if assignment else None,
                }
            )
        )
    return insights


def build_insight_bundles(
    source_insights: list[SourceInsight],
    assignments_by_candidate_id: Mapping[str, CategoryAssignment],
) -> list[InsightBundle]:
    """SourceInsight를 카테고리 기준 InsightBundle로 묶는다."""
    grouped: dict[str, list[SourceInsight]] = {}
    title_by_category_id: dict[str, str] = {}
    for insight in source_insights:
        assignment = assignments_by_candidate_id.get(insight.candidate_id)
        category_id = assignment.category_id if assignment else "category-uncategorized"
        title_by_category_id[category_id] = assignment.category_name if assignment else "기타"
        grouped.setdefault(category_id, []).append(insight)

    bundles: list[InsightBundle] = []
    for index, (category_id, insights) in enumerate(grouped.items(), 1):
        summaries = [insight.summary for insight in insights if insight.summary]
        takeaways = [
            point
            for insight in insights
            for point in insight.key_points
            if point.strip()
        ][:5]
        bundles.append(
            InsightBundle(
                bundle_id=f"bundle-{index:03d}-{category_id}",
                bundle_type="category",
                title=title_by_category_id[category_id],
                source_insight_ids=[
                    insight.source_insight_id for insight in insights
                ],
                summary=" ".join(summaries[:2]) or f"{title_by_category_id[category_id]} 묶음",
                key_takeaways=takeaways,
                category_id=category_id,
            )
        )
    return bundles


def build_keyword_insights(
    bundles: list[InsightBundle],
    source_insights_by_id: Mapping[str, SourceInsight],
) -> list[KeywordInsight]:
    """InsightBundle별 대표 키워드 artifact를 만든다."""
    insights: list[KeywordInsight] = []
    report_keyword_pool: list[str] = []
    for index, bundle in enumerate(bundles, 1):
        summaries = [
            source_insights_by_id[insight_id].summary
            for insight_id in bundle.source_insight_ids
            if insight_id in source_insights_by_id
        ]
        keywords = extract_keywords_from_texts(summaries, top_n=5)
        report_keyword_pool.extend(keywords)
        insights.append(
            KeywordInsight(
                keyword_insight_id=f"keyword-bundle-{index:03d}",
                scope="bundle",
                scope_id=bundle.bundle_id,
                keywords=keywords,
            )
        )

    unique_report_keywords = list(dict.fromkeys(report_keyword_pool))[:8]
    if unique_report_keywords:
        insights.append(
            KeywordInsight(
                keyword_insight_id="keyword-report-001",
                scope="report",
                scope_id="report",
                keywords=unique_report_keywords,
            )
        )
    return insights


def build_trend_insights(
    bundles: list[InsightBundle],
    source_insights_by_id: Mapping[str, SourceInsight],
    provider: StructuredProvider,
    *,
    warnings: list[str] | None = None,
    trace: TraceSink | None = None,
) -> list[TrendInsight]:
    """InsightBundle별 TrendInsight를 생성한다."""
    trends: list[TrendInsight] = []
    stage_warnings = warnings if warnings is not None else []
    for index, bundle in enumerate(bundles, 1):
        prompt = build_trend_prompt(bundle, source_insights_by_id)
        try:
            generated = provider.generate_json(prompt, TrendInsight)
        except Exception as error:
            warning = (
                f"trend insight 생성 실패: {bundle.title} "
                f"({type(error).__name__}: {str(error)[:200]})"
            )
            stage_warnings.append(warning)
            if trace:
                _ = trace.write(
                    "stage_failed",
                    stage="trend_insight",
                    payload={
                        "bundle_id": bundle.bundle_id,
                        "title": bundle.title,
                        "schema": "TrendInsight",
                        "error_type": type(error).__name__,
                        "error_message": str(error)[:500],
                    },
                )
            continue

        trends.append(
            generated.model_copy(
                update={
                    "trend_id": f"trend-{index:03d}",
                    "scope": "bundle",
                    "scope_id": bundle.bundle_id,
                    "source_insight_ids": list(bundle.source_insight_ids),
                }
            )
        )
    return trends


def build_report_content(
    *,
    report_id: str,
    title: str,
    generated_at: str,
    interest_keywords: list[str],
    bundles: list[InsightBundle],
    keyword_insights: list[KeywordInsight],
    trend_insights: list[TrendInsight],
) -> ReportContent:
    """최종 리포트 렌더링에 사용할 ReportContent artifact를 만든다."""
    return ReportContent(
        report_id=report_id,
        title=title,
        generated_at=generated_at,
        interest_keywords=interest_keywords,
        bundle_ids=[bundle.bundle_id for bundle in bundles],
        keyword_insight_ids=[
            insight.keyword_insight_id for insight in keyword_insights
        ],
        trend_insight_ids=[trend.trend_id for trend in trend_insights],
    )


def build_source_insight_prompt(
    candidate: SourceCandidate,
    article: ExtractedArticle | None,
) -> str:
    """SourceInsight schema 출력을 요구하는 prompt를 만든다."""
    content = article.content_text if article else candidate.title
    return (
        "아래 소스 글 1개를 리포트에 사용할 분석 자료로 정리하세요.\n"
        "반드시 제공된 JSON schema에 맞춰 응답하세요.\n\n"
        f"candidate_id: {candidate.candidate_id}\n"
        f"title: {candidate.title}\n"
        f"url: {candidate.url}\n"
        f"relevance_score: {candidate.relevance_score:.2f}\n"
        f"selected_reason: {candidate.selected_reason}\n\n"
        f"본문/요약:\n{content[:5000]}\n\n"
        "작성 기준:\n"
        "- summary는 1~2문장.\n"
        "- key_points는 사실 기반 bullet 2~4개.\n"
        "- importance_score는 0.0~1.0.\n"
        "- why_it_matters는 사용자가 왜 봐야 하는지 한 문장.\n"
    )


def build_trend_prompt(
    bundle: InsightBundle,
    source_insights_by_id: Mapping[str, SourceInsight],
) -> str:
    """TrendInsight schema 출력을 요구하는 prompt를 만든다."""
    blocks: list[str] = []
    for insight_id in bundle.source_insight_ids:
        insight = source_insights_by_id.get(insight_id)
        if not insight:
            continue
        key_points = ", ".join(insight.key_points)
        blocks.append(f"- summary: {insight.summary}\n  key_points: {key_points}")
    source_block = "\n".join(blocks)
    return "\n".join(
        [
            "아래 묶음에 포함된 소스 분석 결과를 바탕으로 관찰되는 트렌드를 정리하세요.",
            "반드시 제공된 JSON schema에 맞춰 응답하세요.",
            "",
            f"bundle_id: {bundle.bundle_id}",
            f"bundle_title: {bundle.title}",
            f"bundle_summary: {bundle.summary}",
            "",
            source_block,
            "",
            "작성 기준:",
            "- title은 트렌드를 드러내는 짧은 제목.",
            "- summary는 1~2문장.",
            "- trend_type은 emerging/repeated/declining/ongoing 중 하나.",
            "- confidence는 0.0~1.0.",
        ]
    )


def extract_keywords_from_texts(texts: Sequence[str], top_n: int) -> list[str]:
    """텍스트 묶음에서 단순 빈도 기반 대표 키워드를 추출한다."""
    counts: dict[str, int] = {}
    for text in texts:
        tokens = cast(list[str], _TOKEN_RE.findall(text))
        for token in tokens:
            if len(token) <= 1:
                continue
            key = token.lower() if token.isascii() else token
            if key in _KEYWORD_STOPWORDS:
                continue
            counts[key] = counts.get(key, 0) + 1
    return [
        keyword
        for keyword, _ in sorted(counts.items(), key=lambda item: (-item[1], item[0]))[
            :top_n
        ]
    ]


def category_id_for(label: str) -> str:
    """카테고리 label에서 안정적인 category_id를 만든다."""
    digest = sha1(label.encode("utf-8")).hexdigest()[:8]
    return f"category-{digest}"


def utc_now_iso() -> str:
    """UTC ISO timestamp를 만든다."""
    return datetime.now(timezone.utc).isoformat()
