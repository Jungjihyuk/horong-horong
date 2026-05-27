"""뉴스 리포트 실행 요청 JSON의 Pydantic 모델."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


ProviderName = Literal["codex", "claude", "gemini", "opencode", "antigravity"]
SourceType = Literal["youtube", "google_news", "linkedin", "yozm_it"]


class NewsSourceConfig(BaseModel):
    """뉴스 수집 소스 1개의 설정."""

    model_config = ConfigDict(
        extra="ignore", # 유연한 JSON 구조 허용 (모델에 없는 JSON 필드 무시) 
        strict=True,    # 엄격한 타입 검사 (자동 타입 변환 방지)
        str_strip_whitespace=True, # 문자열 앞뒤 공백 제거
    )

    type: SourceType
    enabled: bool = True
    channel_id: str | None = Field(default=None, alias="channelId")
    keywords: list[str] = Field(default_factory=list)
    profiles: list[str] = Field(default_factory=list)


class NewsJobRequest(BaseModel):
    """Swift 앱이 `--request` 파일로 전달하는 뉴스 리포트 실행 요청."""

    model_config = ConfigDict(
        extra="ignore",
        populate_by_name=True,  # alias 입력 허용
        strict=True,
        str_strip_whitespace=True,
    )

    job_id: str = Field(alias="jobId", min_length=1)
    requested_at: str | None = Field(default=None, alias="requestedAt")
    provider: ProviderName = "codex"
    interest_keywords: list[str] = Field(
        default_factory=lambda: ["AI", "개발", "생산성", "자동화"],
        alias="interestKeywords",
    )
    max_items_per_source: int = Field(
        default=10,
        alias="maxItemsPerSource",
        ge=1,
        le=50,
    )
    date_range_hours: int = Field(default=24, alias="dateRangeHours", ge=1, le=168)
    output_dir: str = Field(default=".", alias="outputDir", min_length=1)
    sources: list[NewsSourceConfig] = Field(default_factory=list)
