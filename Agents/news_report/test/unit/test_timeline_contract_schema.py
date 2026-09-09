"""타임라인 상태 계약과 커밋된 JSON Schema 가 어긋나지 않는지 검증한다.

`Contracts/news/*.schema.json` 은 생성 스크립트 없이 손으로 동기화하는 파일이라
조용히 낡는다. Swift 가 디코딩에 실패해서 알게 되는 대신 여기서 빨간불이 켜지게 한다
(관례 근거: `Contracts/news/report_artifacts.schema.json`).
"""

import json
import pathlib

import pytest

from contracts.timeline_artifact import TimelineState

SCHEMA_PATH = (
    pathlib.Path(__file__).resolve().parents[2] / ".." / ".." / "Contracts" / "news"
    / "timeline_state.schema.json"
)


# 시나리오 1. 커밋된 스키마가 현재 pydantic 모델과 일치한다.
@pytest.mark.unit
def test_timeline_state_schema__committed_file__matches_pydantic_model():
    # Given: 저장소에 커밋된 계약 규격서.
    committed = json.loads(SCHEMA_PATH.resolve().read_text(encoding="utf-8"))

    # When: 현재 모델에서 스키마를 다시 만든다.
    generated = TimelineState.model_json_schema()

    # Then: 같아야 한다. 다르면 모델을 바꾸고 규격서를 갱신하지 않은 것이다.
    assert generated == committed, (
        "TimelineState 가 바뀌었는데 Contracts/news/timeline_state.schema.json 이 낡았습니다. "
        "재생성하세요."
    )
