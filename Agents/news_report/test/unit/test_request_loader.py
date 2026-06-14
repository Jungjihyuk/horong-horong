"""뉴스 리포트 요청 JSON loader 단위 테스트."""

import json

import pytest
from pydantic import ValidationError

from contracts.request_loader import load_request


# 시나리오 1. Swift 앱이 만든 정상 요청 JSON을 Python runner 설정 객체로 읽는다.
@pytest.mark.unit
def test_load_request__valid_swift_json__returns_request_model(
    valid_request_payload,
    tmp_path,
):
    # Given: Swift 앱이 생성한 정상 요청 JSON 파일을 준비한다.
    request_path = tmp_path / "request.json"
    request_path.write_text(
        json.dumps(valid_request_payload, ensure_ascii=False),
        encoding="utf-8",
    )

    # When: loader가 요청 파일을 읽어 Pydantic 모델로 변환한다.
    request = load_request(str(request_path))

    # Then: camelCase 입력값이 Python snake_case 필드로 올바르게 매핑된다.
    assert request.job_id == "job-20260527-001"
    assert request.provider == "codex"
    assert request.provider_options.model is None
    assert request.interest_keywords == ["AI", "Swift"]
    assert request.max_items_per_source == 3
    assert request.output_dir == "/tmp/horong-news"
    assert request.sources[0].type == "youtube"
    assert request.sources[0].channel_id == "channel-1"


# 시나리오 2. 요청 JSON이 계약을 위반하면 runner 실행 전에 검증 오류로 중단한다.
@pytest.mark.unit
def test_load_request__invalid_fields__raises_validation_error(
    valid_request_payload,
    tmp_path,
):
    # Given: provider와 maxItemsPerSource가 계약을 위반하는 요청을 준비한다.
    invalid_payload = {
        **valid_request_payload,
        "provider": "unknown-provider",
        "maxItemsPerSource": 0,
    }
    request_path = tmp_path / "request.json"
    request_path.write_text(
        json.dumps(invalid_payload, ensure_ascii=False),
        encoding="utf-8",
    )

    # When / Then: loader가 요청 검증 단계에서 ValidationError를 발생시킨다.
    with pytest.raises(ValidationError) as error:
        load_request(str(request_path))

    errors = error.value.errors()
    assert any(err["loc"] == ("provider",) for err in errors)
    assert any(err["loc"] == ("maxItemsPerSource",) for err in errors)


# 시나리오 3. 선택 필드가 빠진 요청 JSON은 runner 기본값으로 보완된다.
@pytest.mark.unit
def test_load_request__missing_optional_fields__uses_defaults(tmp_path):
    # Given: 필수 jobId만 포함한 최소 요청 JSON 파일을 준비한다.
    request_path = tmp_path / "request.json"
    request_path.write_text(
        json.dumps({"jobId": "job-minimal"}, ensure_ascii=False),
        encoding="utf-8",
    )

    # When: loader가 요청 파일을 읽어 Pydantic 모델로 변환한다.
    request = load_request(str(request_path))

    # Then: 생략된 선택 필드들은 runner 기본값으로 채워진다.
    assert request.job_id == "job-minimal"
    assert request.provider == "codex"
    assert request.provider_options.model is None
    assert request.interest_keywords == ["AI", "개발", "생산성", "자동화"]
    assert request.max_items_per_source == 10
    assert request.date_range_hours == 24
    assert request.output_dir == "."
    assert request.sources == []


# 시나리오 4. 알 수 없는 뉴스 소스 타입은 요청 검증 단계에서 거부된다.
@pytest.mark.unit
def test_load_request__invalid_source_type__raises_validation_error(
    valid_request_payload,
    tmp_path,
):
    # Given: sources 안에 Swift 앱이 보낼 수 없는 type을 포함한 요청을 준비한다.
    invalid_payload = {
        **valid_request_payload,
        "sources": [{"type": "tiktok", "enabled": True}],
    }
    request_path = tmp_path / "request.json"
    request_path.write_text(
        json.dumps(invalid_payload, ensure_ascii=False),
        encoding="utf-8",
    )

    # When / Then: source type 검증 단계에서 ValidationError를 발생시킨다.
    with pytest.raises(ValidationError) as error:
        load_request(str(request_path))

    errors = error.value.errors()
    assert any(err["loc"] == ("sources", 0, "type") for err in errors)


# 시나리오 4-1. Swift 앱이 보낼 수 있는 모든 source type은 요청 검증을 통과한다.
# connector 미구현 type(rss, hacker_news)도 요청 전체를 깨지 않고
# collector의 is_supported_source 단계에서 건너뛴다.
@pytest.mark.unit
def test_load_request__swift_source_types__accepted(
    valid_request_payload,
    tmp_path,
):
    # Given: Swift NewsSourceStore가 보낼 수 있는 type들을 포함한 요청을 준비한다.
    payload = {
        **valid_request_payload,
        "sources": [
            {"type": "rss", "enabled": True},
            {"type": "hacker_news", "enabled": True},
        ],
    }
    request_path = tmp_path / "request.json"
    request_path.write_text(
        json.dumps(payload, ensure_ascii=False),
        encoding="utf-8",
    )

    # When: loader가 요청 파일을 읽어 Pydantic 모델로 변환한다.
    request = load_request(str(request_path))

    # Then: rss/hacker_news source가 요청 검증을 통과한다.
    assert [source.type for source in request.sources] == ["rss", "hacker_news"]


# 시나리오 4-2. YouTube channelIds/playlists 설정은 contract를 통과해 connector까지 보존된다.
# 회귀 방지: 과거 NewsSourceConfig에 두 필드가 없어 extra="ignore"가
# Swift 설정을 조용히 버렸다 (#83).
@pytest.mark.unit
def test_load_request__youtube_channel_ids_and_playlists__preserved_to_connector_config(
    valid_request_payload,
    tmp_path,
):
    # Given: Swift 앱이 채널/재생목록을 등록한 YouTube source 요청을 준비한다.
    payload = {
        **valid_request_payload,
        "sources": [
            {
                "type": "youtube",
                "enabled": True,
                "channelIds": ["UC-channel-1", "UC-channel-2"],
                "playlists": [
                    {"name": "AI 트렌드", "playlistId": "PL-list-1"},
                ],
            }
        ],
    }
    request_path = tmp_path / "request.json"
    request_path.write_text(
        json.dumps(payload, ensure_ascii=False),
        encoding="utf-8",
    )

    # When: loader로 파싱한 source를 runner와 같은 방식으로 connector config로 dump한다.
    request = load_request(str(request_path))
    config = request.sources[0].model_dump(by_alias=True, exclude_none=True)

    # Then: connector가 읽는 camelCase 키가 그대로 보존된다.
    assert config["channelIds"] == ["UC-channel-1", "UC-channel-2"]
    assert config["playlists"] == [{"name": "AI 트렌드", "playlistId": "PL-list-1"}]


# 시나리오 5. 로컬 ollama provider는 요청 JSON provider 값으로 허용된다.
@pytest.mark.unit
def test_load_request__ollama_provider__returns_request_model(tmp_path):
    # Given: provider가 ollama인 최소 요청 JSON 파일을 준비한다.
    request_path = tmp_path / "request.json"
    request_path.write_text(
        json.dumps({"jobId": "job-ollama", "provider": "ollama"}, ensure_ascii=False),
        encoding="utf-8",
    )

    # When: loader가 요청 파일을 읽어 Pydantic 모델로 변환한다.
    request = load_request(str(request_path))

    # Then: ollama provider 값이 요청 계약에서 허용된다.
    assert request.job_id == "job-ollama"
    assert request.provider == "ollama"


# 시나리오 6. ollama providerOptions는 요청 JSON에서 모델과 endpoint 설정을 읽는다.
@pytest.mark.unit
def test_load_request__ollama_provider_options__returns_provider_options(tmp_path):
    # Given: ollama 모델과 endpoint를 명시한 요청 JSON 파일을 준비한다.
    request_path = tmp_path / "request.json"
    request_path.write_text(
        json.dumps(
            {
                "jobId": "job-ollama-options",
                "provider": "ollama",
                "providerOptions": {
                    "model": "qwen3:32b",
                    "endpoint": "http://localhost:11435",
                    "timeout": 180.0,
                },
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )

    # When: loader가 요청 파일을 읽어 Pydantic 모델로 변환한다.
    request = load_request(str(request_path))

    # Then: providerOptions 값이 runner 내부 provider_options로 매핑된다.
    assert request.provider == "ollama"
    assert request.provider_options.model == "qwen3:32b"
    assert request.provider_options.endpoint == "http://localhost:11435"
    assert request.provider_options.timeout == 180.0
