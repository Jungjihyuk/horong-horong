"""Swift 앱이 만든 뉴스 리포트 요청 JSON을 Python 객체로 바꾼다.

Swift 쪽 JSON은 `jobId`, `maxItemsPerSource`처럼 camelCase 이름을 쓴다.
이 모듈은 파일을 읽고, 실제 필드 검증과 snake_case 변환은 Pydantic 모델에 맡긴다.
"""

import json

from contracts.news_job_request import NewsJobRequest


def load_request(path: str) -> tuple[NewsJobRequest, list[str]]:
    """요청 JSON 파일을 읽어 `NewsJobRequest`로 변환한다.

    Args:
        path: Swift 앱이 `--request` 인자로 넘긴 JSON 파일 경로.

    Returns:
        `(요청, 경고 목록)`. 경고는 «거부하는 대신 기본값으로 강등한» 필드를 알린다 —
        튜플로 돌려주는 이유는 호출부가 경고를 잊지 못하게 하기 위해서다.

    Raises:
        FileNotFoundError: 요청 파일이 존재하지 않을 때.
        json.JSONDecodeError: 요청 파일이 올바른 JSON이 아닐 때.
        pydantic.ValidationError: 요청 JSON의 필드 타입이나 값이 올바르지 않을 때.
    """
    with open(path, "r", encoding="utf-8") as file:
        raw = json.load(file)

    request = NewsJobRequest.model_validate(raw)
    return request, _demotion_warnings(raw, request)


def _demotion_warnings(raw: dict, request: NewsJobRequest) -> list[str]:
    """원본에는 값이 있었는데 파싱 결과가 비었다면 강등된 것이다."""
    warnings: list[str] = []
    options = raw.get("providerOptions")
    if isinstance(options, dict):
        raw_effort = options.get("effort")
        if raw_effort is not None and request.provider_options.effort is None:
            warnings.append(
                f"providerOptions.effort 값 {raw_effort!r} 을 알 수 없어 기본값을 사용합니다."
            )
    return warnings
