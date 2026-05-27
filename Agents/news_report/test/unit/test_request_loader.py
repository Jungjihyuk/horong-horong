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
    assert request.interest_keywords == ["AI", "개발", "생산성", "자동화"]
    assert request.max_items_per_source == 10
    assert request.date_range_hours == 24
    assert request.output_dir == "."
    assert request.sources == []


# 시나리오 4. 지원하지 않는 뉴스 소스 타입은 요청 검증 단계에서 거부된다.
@pytest.mark.unit
def test_load_request__invalid_source_type__raises_validation_error(
    valid_request_payload,
    tmp_path,
):
    # Given: sources 안에 지원하지 않는 type을 포함한 요청을 준비한다.
    invalid_payload = {
        **valid_request_payload,
        "sources": [{"type": "rss", "enabled": True}],
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
