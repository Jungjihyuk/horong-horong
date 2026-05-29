"""관심사 기준으로 source candidate artifact를 만든다."""

from __future__ import annotations

from collections.abc import Callable, Mapping, Sequence
from hashlib import sha1
from typing import Protocol, cast, get_args

from contracts.research_artifact import RelevanceJudgment, SourceCandidate, SourceType
from providers.protocols import StructuredProvider
from tracing.events import TraceEventName


_ALLOWED_SOURCE_TYPES = set(get_args(SourceType))


class TraceSink(Protocol):
    """relevance stage가 필요로 하는 trace 기록 계약."""

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


def select_source_candidates(
    items: Sequence[Mapping[str, object]],
    interest_keywords: list[str],
    provider: StructuredProvider,
    log: Callable[[str], None],
    *,
    threshold: float = 0.7,
    warnings: list[str] | None = None,
    trace: TraceSink | None = None,
) -> tuple[list[RelevanceJudgment], list[SourceCandidate]]:
    """item 목록을 relevance 판단과 source candidate artifact로 변환한다."""
    judgments: list[RelevanceJudgment] = []
    candidates: list[SourceCandidate] = []
    stage_warnings = warnings if warnings is not None else []

    for item in items:
        item_id = item_id_for(item)
        try:
            judgment = judge_item_relevance(
                item,
                item_id,
                interest_keywords,
                provider,
                threshold=threshold,
            )
        except Exception as error:
            warning = (
                f"relevance 판단 실패: {item_title_safe(item)} "
                f"({type(error).__name__}: {str(error)[:200]})"
            )
            stage_warnings.append(warning)
            log(f"  {warning}")
            if trace:
                _ = trace.write(
                    "stage_failed",
                    stage="relevance",
                    payload={
                        "item_id": item_id,
                        "title": item_title_safe(item),
                        "schema": "RelevanceJudgment",
                        "error_type": type(error).__name__,
                        "error_message": str(error)[:500],
                    },
                )
            continue

        judgments.append(judgment)

        if not judgment.is_relevant or judgment.score < threshold:
            log(f"  relevance 제외: {item_title(item)[:40]} ({judgment.score:.2f})")
            continue

        try:
            candidate = source_candidate_from_item(
                item,
                judgment,
                selection_rank=len(candidates) + 1,
            )
        except ValueError as error:
            warning = f"source candidate 생성 실패: {error}"
            stage_warnings.append(warning)
            log(f"  {warning}")
            if trace:
                _ = trace.write(
                    "stage_failed",
                    stage="source_candidate",
                    payload={
                        "item_id": item_id,
                        "title": item_title_safe(item),
                        "schema": "SourceCandidate",
                        "error_type": type(error).__name__,
                        "error_message": str(error)[:500],
                    },
                )
            continue

        candidates.append(candidate)
        log(f"  relevance 채택: {candidate.title[:40]} ({judgment.score:.2f})")

    return judgments, candidates


def judge_item_relevance(
    item: Mapping[str, object],
    item_id: str,
    interest_keywords: list[str],
    provider: StructuredProvider,
    *,
    threshold: float,
) -> RelevanceJudgment:
    """LLM structured output으로 item 하나의 relevance를 판단한다."""
    prompt = build_relevance_prompt(item, item_id, interest_keywords, threshold)
    judgment = provider.generate_json(prompt, RelevanceJudgment)
    return judgment.model_copy(
        update={
            "item_id": item_id,
            "threshold": threshold,
            "method": "llm",
        }
    )


def source_candidate_from_item(
    item: Mapping[str, object],
    judgment: RelevanceJudgment,
    *,
    selection_rank: int,
) -> SourceCandidate:
    """threshold를 통과한 relevance 판단을 source candidate로 변환한다."""
    return SourceCandidate(
        candidate_id=f"candidate-{selection_rank:03d}-{judgment.item_id}",
        item_id=judgment.item_id,
        source_type=source_type_for(item),
        configured_source_id=optional_text(item, "configuredSourceId"),
        title=item_title(item),
        url=required_text(item, "url"),
        relevance_score=judgment.score,
        threshold=judgment.threshold,
        matched_keywords=judgment.matched_keywords,
        selected_reason=judgment.reason,
        published_at=optional_text(item, "publishedAt"),
        selection_rank=selection_rank,
    )


def build_relevance_prompt(
    item: Mapping[str, object],
    item_id: str,
    interest_keywords: list[str],
    threshold: float,
) -> str:
    """RelevanceJudgment schema 출력을 요구하는 prompt를 만든다."""
    keywords = ", ".join(interest_keywords) if interest_keywords else "(전 영역)"
    content = text_for_relevance(item)
    return (
        "아래 소스 글이 사용자의 관심사와 관련 있는지 판단하세요.\n"
        "반드시 제공된 JSON schema에 맞춰 응답하세요.\n\n"
        f"item_id: {item_id}\n"
        f"threshold: {threshold:.2f}\n"
        f"관심사: {keywords}\n\n"
        f"제목: {item_title(item)}\n"
        f"소스: {optional_text(item, 'sourceType') or 'unknown'}\n"
        f"본문/요약 발췌:\n{content[:4000]}\n\n"
        "판단 기준:\n"
        "- 관심사와 직접 관련된 핵심 주제면 is_relevant=true, score는 threshold 이상.\n"
        "- 단순 단어 일치가 아니라 글의 실제 내용이 관심사와 연결되어야 함.\n"
        "- 관련성이 약하거나 일반 잡담이면 is_relevant=false.\n"
        "- matched_keywords에는 관련 있다고 본 사용자 관심사 키워드만 넣을 것.\n"
        "- reason은 판단 근거를 한국어 한 문장으로 쓸 것.\n"
    )


def item_id_for(item: Mapping[str, object]) -> str:
    """기존 item에 id가 없으면 URL/제목 기반 deterministic id를 만든다."""
    existing = optional_text(item, "itemId") or optional_text(item, "id")
    if existing:
        return existing

    seed = f"{required_text(item, 'url')}|{item_title(item)}"
    digest = sha1(seed.encode("utf-8")).hexdigest()[:12]
    return f"item-{digest}"


def text_for_relevance(item: Mapping[str, object]) -> str:
    """relevance 판단에 사용할 텍스트를 합친다."""
    parts = [
        item_title(item),
        optional_text(item, "summary") or "",
        optional_text(item, "contentText") or "",
    ]
    return "\n\n".join(part for part in parts if part.strip())


def item_title(item: Mapping[str, object]) -> str:
    """item 제목을 문자열로 읽는다."""
    return required_text(item, "title")


def item_title_safe(item: Mapping[str, object]) -> str:
    """warning/trace용 item 제목을 안전하게 읽는다."""
    return optional_text(item, "title") or "(제목 없음)"


def source_type_for(item: Mapping[str, object]) -> SourceType:
    """item의 sourceType을 SourceType 계약 값으로 읽는다."""
    value = required_text(item, "sourceType")
    if value not in _ALLOWED_SOURCE_TYPES:
        raise ValueError(f"지원하지 않는 sourceType: {value}")
    return cast(SourceType, value)


def required_text(item: Mapping[str, object], key: str) -> str:
    """필수 문자열 필드를 읽고 비어 있으면 오류를 낸다."""
    value = optional_text(item, key)
    if not value:
        raise ValueError(f"필수 item 필드가 비어 있음: {key}")
    return value


def optional_text(item: Mapping[str, object], key: str) -> str | None:
    """선택 문자열 필드를 읽는다."""
    value = item.get(key)
    if value is None:
        return None
    text = str(value).strip()
    return text or None
