"""카테고리별 월간 타임라인 상태 데이터 계약.

리포트는 하루에 한두 편씩 계속 쌓이는데, 그때마다 전체를 LLM 입력으로 다시 넣으면
비용이 리포트 수에 비례해 늘어난다. 그래서 «월» 을 메모이제이션 단위로 삼는다 —
마감된 달은 다시 종합하지 않고, 상위 개요는 원본 사건이 아니라 월 요약들만 본다.

리포트 마크다운 파싱 자체는 LLM 이 없어 117편에 밀리초면 끝난다. 그래서 수집은 매번
전량 다시 하고(그 편이 교차-날짜 중복 제거가 항상 일관된다), 메모이제이션은 비싼
LLM 합성에만 둔다 — `input_hash` 가 그 경계다.

`status: sealed|open` 같은 필드를 두지 않는 이유: 이번 달은 다음 달이 되면 지난 달이라
쓰기 없이 자정만 지나도 틀리는 값이다. 저장하는 것은 `synthesized_at` 과 `input_hash`
뿐이고, 봉인 여부는 읽는 시점에 현재 월과 비교해 계산한다(`timeline/state.py`).
"""

from pydantic import BaseModel, Field

TIMELINE_SCHEMA_VERSION = 1

# 월 종합 프롬프트가 바뀌면 올린다. 올리면 봉인된 달도 다시 종합된다.
TIMELINE_PROMPT_VERSION = 2


class TimelineEvent(BaseModel):
    """타임라인의 한 시점에서 일어난 사건 1건.

    시점의 단위는 «리포트 날짜» 다. 기사 발행 시각(`published_at`)이 아닌 이유는
    커넥터마다 채우는 형식이 다르고(RFC-822 / ISO-8601) linkedin 은 아예 안 채우기
    때문이다. 리포트 날짜는 파일명에 항상 있고 모호하지 않다.
    """

    event_id: str  # 날짜+기사키에서 만든 안정 식별자. 재생성해도 같은 사건이면 같다
    date: str  # YYYY-MM-DD. 이 사건이 실린 리포트의 날짜
    title: str  # 편집 프리픽스·언론사 꼬리를 걷어낸 제목
    url: str = ""  # 원문 URL. 없을 수 있다
    importance: int = 0  # 리포트가 매긴 중요도 0~100
    bullets: list[str] = Field(default_factory=list)  # 카드에 표시할 요약 불릿
    tags: list[str] = Field(default_factory=list)  # 그 시점의 주제어(칩으로 표시)
    rank: int | None = None  # 세부 사건의 우선순위. 축 사건은 None
    why_it_matters: str = ""  # 축 사건만 LLM 이 채운다. 「왜 이게 축인가」


class TimelineMonth(BaseModel):
    """월 버킷 하나. 재계산 여부를 스스로 판단할 근거를 들고 있다."""

    month_key: str  # YYYY-MM
    input_hash: str  # 이 달 사건들의 내용 해시. 바뀌면 다시 종합한다
    synthesized_at: str = ""  # 비어 있으면 아직 종합 전이다
    provider: str = ""  # 이 달을 종합한 provider. 품질 비교의 근거로 남긴다
    prompt_version: int = 0
    summary: str = ""  # LLM 이 만든 그 달의 종합 정리
    key_terms: list[str] = Field(default_factory=list)  # 그 달의 핵심어
    is_turning_point: bool = False
    axis_events: list[TimelineEvent] = Field(default_factory=list)  # 최대 3개
    detail_events: list[TimelineEvent] = Field(default_factory=list)  # 우선순위순

class TimelineOverview(BaseModel):
    """타임라인 전체 머리말. 원본 사건이 아니라 월 요약들만 보고 만든다."""

    input_hash: str = ""  # 월 요약들의 해시. 달이 늘어도 입력 크기는 월 수만큼만 는다
    summary: str = ""
    emphasis_keywords: list[str] = Field(default_factory=list)
    turning_point_count: int = 0


class TimelineState(BaseModel):
    """`data/timeline/<category_id>.json` 의 전체 모양. 모든 렌더링의 단일 진실 공급원."""

    schema_version: int = TIMELINE_SCHEMA_VERSION
    category_id: str
    category_label: str
    date_from: str = ""
    date_to: str = ""
    generated_at: str = ""
    months: list[TimelineMonth] = Field(default_factory=list)
    overview: TimelineOverview = Field(default_factory=TimelineOverview)
    warnings: list[str] = Field(default_factory=list)
    """이번 실행에서 종합에 실패한 달 등. 실패해도 빌드는 끝까지 간다."""


# ---------- LLM 응답 계약 (provider.generate_json 의 schema_model) ----------


class AxisSelection(BaseModel):
    """축 사건으로 고른 것 하나와 그 근거."""

    event_id: str  # 후보 목록에 제시된 event_id 중 하나여야 한다
    why_it_matters: str  # 한 문장. 왜 이 달의 축인가


class MonthSynthesis(BaseModel):
    """월 종합 LLM 응답."""

    summary: str  # 그 달에 무슨 일이 있었는지 2~3문장
    key_terms: list[str]  # 그 달의 핵심어 2~4개
    is_turning_point: bool  # 이 달이 흐름의 전환점인가
    axis: list[AxisSelection]  # 축 사건 최대 3개


class OverviewSynthesis(BaseModel):
    """타임라인 개요 LLM 응답."""

    summary: str  # 전체 기간을 관통하는 흐름 2~3문장
    emphasis_keywords: list[str]  # 머리말에 강조할 키워드 3~6개
