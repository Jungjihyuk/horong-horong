"""뉴스 리포트 runner 테스트 fixture."""

import pytest


@pytest.fixture
def valid_request_payload():
    """Swift 앱이 생성하는 요청 JSON과 같은 camelCase 입력 payload."""
    return {
        "jobId": "job-20260527-001",
        "requestedAt": "2026-05-27T10:00:00Z",
        "provider": "codex",
        "interestKeywords": ["AI", "Swift"],
        "maxItemsPerSource": 3,
        "dateRangeHours": 24,
        "outputDir": "/tmp/horong-news",
        "sources": [
            {
                "type": "youtube",
                "enabled": True,
                "channelId": "channel-1",
                "keywords": ["agent"],
            }
        ],
    }

@pytest.fixture
def fake_step_logger():
    """StepReporter가 호출한 logger.info 인자를 기록하는 fake logger."""

    class FakeStepLogger:
        def __init__(self):
            self.info_calls = []

        def info(self, scope: str, message: str) -> None:
            self.info_calls.append((scope, message))

    return FakeStepLogger()
