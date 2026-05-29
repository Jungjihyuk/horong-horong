"""Swift 앱이 만든 뉴스 리포트 요청 JSON을 Python 객체로 바꾼다.

Swift 쪽 JSON은 `jobId`, `maxItemsPerSource`처럼 camelCase 이름을 쓴다.
이 모듈은 파일을 읽고, 실제 필드 검증과 snake_case 변환은 Pydantic 모델에 맡긴다.
"""

import json

from contracts.news_job_request import NewsJobRequest


def load_request(path: str) -> NewsJobRequest:
    """요청 JSON 파일을 읽어 `NewsJobRequest`로 변환한다.

    Args:
        path: Swift 앱이 `--request` 인자로 넘긴 JSON 파일 경로.

    Returns:
        runner가 바로 사용할 수 있는 `NewsJobRequest`.

    Raises:
        FileNotFoundError: 요청 파일이 존재하지 않을 때.
        json.JSONDecodeError: 요청 파일이 올바른 JSON이 아닐 때.
        pydantic.ValidationError: 요청 JSON의 필드 타입이나 값이 올바르지 않을 때.
    """
    with open(path, "r", encoding="utf-8") as file:
        raw = json.load(file)

    return NewsJobRequest.model_validate(raw)
