"""뉴스 리포트 실행 요청 JSON의 Pydantic 모델."""

from __future__ import annotations

from typing import ClassVar, Literal

from pydantic import BaseModel, ConfigDict, Field


ProviderName = Literal["codex", "claude", "gemini", "opencode", "antigravity", "ollama"]
# Swift NewsSourceStore가 보낼 수 있는 모든 type을 포함해야 한다.
# 여기 없는 type은 요청 전체가 검증 실패로 중단되므로, connector 미구현 type도
# 일단 받아서 collector의 is_supported_source 단계에서 건너뛰게 한다.
SourceType = Literal["youtube", "google_news", "linkedin", "yozm_it", "rss", "hacker_news"]


class NewsPlaylistConfig(BaseModel):
    """YouTube 재생목록 1개의 설정 (Swift NewsPlaylist와 1:1)."""

    model_config: ClassVar[ConfigDict] = ConfigDict(
        extra="ignore",
        strict=True,
        str_strip_whitespace=True,
    )

    name: str | None = None
    playlist_id: str = Field(alias="playlistId", min_length=1)


class NewsSourceConfig(BaseModel):
    """뉴스 수집 소스 1개의 설정.

    주의: extra="ignore"라서 여기 정의되지 않은 필드는 조용히 버려진다.
    Swift NewsSource가 보내는 필드는 빠짐없이 선언해야 connector까지 전달된다.
    """

    model_config: ClassVar[ConfigDict] = ConfigDict(
        extra="ignore", # 유연한 JSON 구조 허용 (모델에 없는 JSON 필드 무시)
        strict=True,    # 엄격한 타입 검사 (자동 타입 변환 방지)
        str_strip_whitespace=True, # 문자열 앞뒤 공백 제거
    )

    type: SourceType
    enabled: bool = True
    channel_id: str | None = Field(default=None, alias="channelId")
    channel_ids: list[str] = Field(default_factory=list, alias="channelIds")
    playlists: list[NewsPlaylistConfig] = Field(default_factory=list)
    keywords: list[str] = Field(default_factory=list)
    profiles: list[str] = Field(default_factory=list)


class ProviderOptionsConfig(BaseModel):
    """provider 구현체에 전달할 선택 옵션."""

    model_config: ClassVar[ConfigDict] = ConfigDict(
        extra="ignore",
        populate_by_name=True,
        strict=True,
        str_strip_whitespace=True,
    )

    model: str | None = Field(default=None, min_length=3)
    endpoint: str | None = Field(default=None, min_length=1)
    timeout: float | None = Field(default=None, gt=0)


class NewsJobRequest(BaseModel):
    """Swift 앱이 `--request` 파일로 전달하는 뉴스 리포트 실행 요청."""

    model_config: ClassVar[ConfigDict] = ConfigDict(
        extra="ignore",
        populate_by_name=True,  # alias 입력 허용
        strict=True,
        str_strip_whitespace=True,
    )

    job_id: str = Field(alias="jobId", min_length=1)
    requested_at: str | None = Field(default=None, alias="requestedAt")
    provider: ProviderName = "codex"
    provider_options: ProviderOptionsConfig = Field(
        default_factory=ProviderOptionsConfig,
        alias="providerOptions",
    )
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
