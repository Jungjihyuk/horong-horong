"""외부 뉴스 소스에서 원천 데이터를 수집하는 connector 패키지.

Google News, YouTube, LinkedIn, Yozm 같은 source별 수집 구현체와 connector registry를
관리한다. 각 connector는 `collect() -> list[dict]` 계약을 따른다.
"""
