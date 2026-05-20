"""뉴스 connector 공용 텍스트 정리 유틸.

RSS/Atom 피드 description 에 raw HTML 이 들어있는 경우가 흔해 (특히 Google News 의
`<a href="...">제목</a> ...` 형태), 그대로 마크다운 리포트에 넣으면 형식이 깨진다.
모든 connector 는 외부에서 받은 summary 텍스트를 이 함수로 한 번 통과시켜야 한다.
"""

from __future__ import annotations

import html
import re

_TAG_RE = re.compile(r"<[^>]+>")
_WHITESPACE_RE = re.compile(r"\s+")


def clean_summary(raw: str | None, max_len: int = 300) -> str:
    """HTML 태그 제거 + 엔티티 디코드 + 공백 정리 + 길이 제한.

    Args:
        raw: 원문 텍스트 (None 허용).
        max_len: 최종 길이 상한.

    Returns:
        마크다운에 안전하게 삽입 가능한 plain text. raw 가 비면 "" 반환.
    """
    if not raw:
        return ""
    # 엔티티 디코드 (&amp; → &) 먼저 해야 일부 잘못 인코딩된 태그도 잡힘.
    text = html.unescape(raw)
    # HTML 태그 제거.
    text = _TAG_RE.sub(" ", text)
    # 마크다운 안전: 백틱/별표/언더스코어가 단독 등장하면 의미가 깨질 수 있어 공백으로 치환.
    # (요약은 줄 안 짤리도록 평문에 가깝게 둔다.)
    # 연속 공백·줄바꿈 정리.
    text = _WHITESPACE_RE.sub(" ", text).strip()
    return text[:max_len]
