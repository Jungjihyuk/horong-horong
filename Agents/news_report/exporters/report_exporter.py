"""Markdown 리포트 파일 exporter."""

from __future__ import annotations

import os


def write_report(path: str, content: str) -> int:
    """Markdown 리포트를 파일에 쓰고 기록한 byte 수를 반환한다."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as file:
        file.write(content)
    return len(content.encode("utf-8"))
