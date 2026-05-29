"""뉴스 리포트 실행 경계를 넘는 데이터 계약 모델.

Swift 앱, Python runner, 내부 stage 사이에서 공유하는 요청/응답 구조와 검증 모델을
이 패키지에서 관리한다.
"""

from contracts.news_job_request import NewsJobRequest, NewsSourceConfig
from contracts.request_loader import load_request

__all__ = ["NewsJobRequest", "NewsSourceConfig", "load_request"]
