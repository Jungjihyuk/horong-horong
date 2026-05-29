"""Deep research pipeline이 공유하는 중간 산출물 데이터 계약."""

from typing import Literal

from pydantic import BaseModel, Field

SourceType = Literal["youtube", "google_news", "linkedin", "yozm_it"]
Method = Literal["llm", "embedding", "rule", "hybrid"]
MatchType = Literal["exact", "partial"]
BundleType = Literal["category", "topic", "all", "manual"]
InsightScope = Literal["source", "bundle", "report"]
TrendType = Literal["emerging", "repeated", "declining", "ongoing"]


class SourceItem(BaseModel):
    """connector가 지정 소스에서 가져온 원본 항목 1개."""

    source_type: SourceType  # 어떤 connector/source에서 수집된 항목인지
    configured_source_id: str | None = None  # 사용자가 설정한 대표 소스와 연결할 식별자
    item_id: str  # pipeline 내부에서 이 항목을 추적할 고유 식별자
    title: str  # connector가 수집한 원본 제목
    url: str  # 원본 항목 URL
    published_at: str | None = None  # 원본 발행 시각. 소스가 제공하지 않으면 None
    author: str | None = None  # 작성자 또는 채널명
    raw_summary: str | None = None  # 본문 추출 전 connector가 제공한 설명/요약


class ExtractedArticle(BaseModel):
    """SourceItem에서 본문 추출을 마친 글 1개."""

    item_id: str  # SourceItem.item_id와 연결되는 식별자
    title: str  # 본문 추출 후 사용할 제목
    url: str  # 원문 URL
    content_text: str  # relevance/요약/키워드 추출에 사용할 본문 텍스트
    extracted_at: str  # 본문 추출 시각
    language: str | None = None  # 감지된 언어. 모르면 None


class KeywordMatch(BaseModel):
    """사용자 관심사 키워드가 본문에서 직접 발견된 결과."""

    item_id: str  # 어떤 article에서 매칭됐는지
    interest_keyword: str  # 사용자가 등록한 관심사 키워드
    matched_text: str  # 원문에서 실제로 발견된 표현
    match_type: MatchType  # 완전 일치인지 부분 일치인지


class RelevanceJudgment(BaseModel):
    """사용자 관심사와 글 사이의 최종 연관성 판단 결과."""

    item_id: str = Field(min_length=1)
    is_relevant: bool  # 최종 채택 여부
    score: float = Field(ge=0.0, le=1.0)  # 점수
    threshold: float = Field(ge=0.0, le=1.0)  # 판단에 사용한 기준선
    matched_keywords: list[str] = Field(default_factory=list)  # 관련 있다고 본 관심사 키워드
    reason: str = Field(min_length=10)  # 관련 있다고 판단한 이유
    method: Method = "llm"  # 판단 방식. rule/hybrid 등 여러 방식이 될 수 있음


class SourceCandidate(BaseModel):
    """연관성 기준을 통과해 리포트 분석 대상으로 채택된 소스 글."""

    candidate_id: str  # 후보 자체를 구분하기 위한 식별자
    item_id: str  # SourceItem/ExtractedArticle/RelevanceJudgment와 연결되는 원본 항목 식별자
    source_type: SourceType  # 후보가 어느 source connector에서 왔는지
    configured_source_id: str | None = None  # 사용자가 설정한 대표 소스와 연결할 식별자
    title: str  # 후보 목록과 리포트에서 보여줄 제목
    url: str  # 최종 리포트에서 출처 링크로 사용할 URL
    relevance_score: float = Field(ge=0.0, le=1.0)  # 후보 채택에 사용된 연관성 점수
    threshold: float = Field(ge=0.0, le=1.0)  # 이 후보가 통과한 연관성 기준선
    matched_keywords: list[str] = Field(default_factory=list)  # 채택 근거가 된 관심사 키워드
    selected_reason: str  # 이 글을 분석 대상으로 채택한 이유
    published_at: str | None = None  # 원본 발행 시각. 최신성/트렌드 판단에 사용
    selection_rank: int | None = None  # 정렬 후 몇 번째 후보인지


class CategoryDefinition(BaseModel):
    """이번 run에서 사용할 카테고리 1개에 대한 정의."""

    category_id: str = Field(min_length=1)  # 카테고리를 안정적으로 참조하기 위한 식별자
    name: str = Field(min_length=1)  # 리포트에 표시할 카테고리 이름
    description: str = Field(min_length=1)  # 어떤 글을 이 카테고리에 넣을지 설명하는 기준
    keywords: list[str] = Field(default_factory=list)  # 카테고리와 연결된 대표 키워드


class CategoryTaxonomy(BaseModel):
    """사용자 관심사 키워드로부터 만든 이번 run의 카테고리 체계."""

    taxonomy_id: str = Field(min_length=1)  # 이번 카테고리 체계를 식별하는 ID
    version: str = Field(min_length=1)  # taxonomy 생성 규칙이나 프롬프트 버전
    generated_from_keywords: list[str] = Field(default_factory=list)  # taxonomy를 만든 사용자 관심사
    method: Method = "llm"  # taxonomy 생성 방식. 나중에 embedding/graph 등으로 교체 가능
    categories: list[CategoryDefinition] = Field(default_factory=list)  # 이번 run에서 사용할 카테고리 목록


class CategoryAssignment(BaseModel):
    """채택된 소스 후보가 어떤 카테고리에 배치됐는지에 대한 결과."""

    candidate_id: str = Field(min_length=1)  # SourceCandidate와 연결되는 후보 식별자
    category_id: str = Field(min_length=1)  # CategoryDefinition.category_id
    category_name: str = Field(min_length=1)  # 리포트 렌더링에서 바로 사용할 카테고리 이름
    confidence: float = Field(ge=0.0, le=1.0)  # 이 카테고리 배정에 대한 확신도
    reason: str = Field(min_length=1)  # 이 카테고리에 배정한 이유
    method: Method = "llm"  # 분류 방식. ontology/embedding/graph 확장을 위해 기록
    taxonomy_id: str = Field(min_length=1)  # 어떤 taxonomy 기준으로 분류했는지
    taxonomy_version: str = Field(min_length=1)  # taxonomy 버전 추적용


class SourceInsight(BaseModel):
    """채택된 소스 1개에서 리포트에 쓸 분석 결과."""

    source_insight_id: str = Field(min_length=1)  # 소스 분석 결과를 구분하는 식별자
    candidate_id: str = Field(min_length=1)  # SourceCandidate와 연결되는 후보 식별자
    category_id: str | None = None  # 카테고리 배정 결과와 연결할 때 사용
    summary: str = Field(min_length=1)  # 소스 글 1개에 대한 요약
    key_points: list[str] = Field(default_factory=list)  # 리포트 bullet로 쓸 핵심 포인트
    importance_score: float = Field(ge=0.0, le=1.0)  # 이 소스가 얼마나 중요한지
    why_it_matters: str = Field(min_length=1)  # 사용자가 이 소스를 봐야 하는 이유


class KeywordInsight(BaseModel):
    """특정 범위에서 추출한 키워드 분석 결과."""

    keyword_insight_id: str = Field(min_length=1)  # 키워드 분석 결과 식별자
    scope: InsightScope  # source/bundle/report 중 어떤 범위의 키워드인지
    scope_id: str = Field(min_length=1)  # scope에 해당하는 artifact 식별자
    keywords: list[str] = Field(default_factory=list)  # 추출된 키워드 목록


class TrendInsight(BaseModel):
    """여러 소스 또는 묶음에서 관찰한 트렌드 신호."""

    trend_id: str = Field(min_length=1)  # 트렌드 분석 결과 식별자
    scope: InsightScope  # bundle/report 등 어떤 범위에서 본 트렌드인지
    scope_id: str = Field(min_length=1)  # scope에 해당하는 artifact 식별자
    title: str = Field(min_length=1)  # 트렌드 제목
    summary: str = Field(min_length=1)  # 트렌드 설명
    trend_type: TrendType  # 부상/반복/감소/지속 중 어떤 신호인지
    source_insight_ids: list[str] = Field(default_factory=list)  # 트렌드 근거가 된 SourceInsight 목록
    confidence: float = Field(ge=0.0, le=1.0)  # 트렌드 판단 확신도


class InsightBundle(BaseModel):
    """여러 SourceInsight를 하나의 기준으로 묶은 분석 묶음."""

    bundle_id: str = Field(min_length=1)  # 묶음 자체를 구분하는 식별자
    bundle_type: BundleType  # SourceInsight를 어떤 기준으로 묶었는지
    title: str = Field(min_length=1)  # 리포트에서 사용할 수 있는 묶음 제목
    source_insight_ids: list[str] = Field(default_factory=list)  # 이 묶음에 포함된 SourceInsight 목록
    summary: str = Field(min_length=1)  # 묶음 전체를 설명하는 요약
    key_takeaways: list[str] = Field(default_factory=list)  # 묶음에서 뽑은 핵심 시사점
    category_id: str | None = None  # category 기반 묶음일 때만 사용


class ReportContent(BaseModel):
    """리포트 템플릿에 넣을 최종 데이터."""

    report_id: str = Field(min_length=1)  # report content 식별자
    title: str = Field(min_length=1)  # 리포트 제목
    generated_at: str = Field(min_length=1)  # 리포트 데이터 생성 시각
    interest_keywords: list[str] = Field(default_factory=list)  # 이번 리포트의 사용자 관심사
    bundle_ids: list[str] = Field(default_factory=list)  # 리포트에 포함할 InsightBundle 목록
    keyword_insight_ids: list[str] = Field(default_factory=list)  # 리포트에 포함할 KeywordInsight 목록
    trend_insight_ids: list[str] = Field(default_factory=list)  # 리포트에 포함할 TrendInsight 목록
