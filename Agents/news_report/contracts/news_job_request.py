"""뉴스 리포트 실행 요청 JSON의 Pydantic 모델."""

from __future__ import annotations

from typing import ClassVar, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


VALID_EFFORTS = ("low", "medium", "high")

ProviderName = Literal[
    "codex", "claude", "opencode", "antigravity", "hermes", "ollama", "anthropic"
]
# "anthropic" 은 유일한 과금형 provider 다. 나머지는 구독 CLI 또는 로컬 모델이라
# 호출 한 번이 곧 청구가 아니다.
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
    # antigravity(agy) 전용. CLI 가 `--model gemini-3.8-flash` 에 `--effort` 를
    # 함께 요구하도록 바뀌었다. 빠뜨리면 호출이 통째로 실패한다.
    effort: Literal["low", "medium", "high"] | None = Field(default=None)

    @field_validator("effort", mode="before")
    @classmethod
    def _demote_unknown_effort(cls, value: object) -> str | None:
        """모르는 값은 거부하지 않고 None 으로 강등한다.

        설정 문자열 하나가 잘못됐다고 수집 전체가 죽으면 손해가 너무 크다. None 이
        되면 provider 의 `effort or DEFAULT_EFFORT` 가 기본값을 채운다. 강등했다는
        사실은 `request_loader` 가 경고로 남기므로 조용히 삼켜지지는 않는다.

        같은 처리를 `model` 에는 하지 않는다 — 모델 이름 오타를 삼키면 사용자가
        모르는 모델이 도는 상태가 되어, 실패하는 편이 낫다.
        """
        if value is None:
            return None
        text = str(value).strip().lower()
        return text if text in VALID_EFFORTS else None


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
