"""pattern registry 단위 테스트."""

import pytest

from patterns.registry import create_pattern, default_pattern_name


# 시나리오 1. 기본 뉴스 리포트 pipeline 이름으로 pattern 구현체를 생성한다.
@pytest.mark.unit
def test_create_pattern__default_pattern_name__returns_news_report_pipeline():
    # Given: runner가 사용하는 기본 pattern 이름을 준비한다.
    pattern_name = default_pattern_name()

    # When: registry가 pattern 이름을 구현체로 변환한다.
    pattern = create_pattern(pattern_name)

    # Then: 기본 뉴스 리포트 pipeline 계약을 만족하는 구현체가 반환된다.
    assert pattern.name == "news_report_v1"
    assert pattern.version == "0.1.0"
    assert callable(pattern.run)


# 시나리오 2. 등록되지 않은 pattern 이름은 명확한 오류로 거부한다.
@pytest.mark.unit
def test_create_pattern__unsupported_pattern_name__raises_value_error():
    # Given: registry에 등록되지 않은 pattern 이름을 준비한다.
    pattern_name = "unknown_pattern"

    # When / Then: pattern 생성 단계에서 ValueError를 발생시킨다.
    with pytest.raises(ValueError, match="지원하지 않는 pattern"):
        create_pattern(pattern_name)
