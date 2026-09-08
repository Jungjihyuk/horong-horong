"""API 키를 환경변수와 `.env` 에서 찾는다.

새 의존성을 들이지 않으려고 최소한의 `KEY=VALUE` 파서만 둔다. `.env` 는 이미
`.gitignore:164` 로 제외되어 있다.

Swift 앱을 통해 실행될 때는 `NewsPipelineService.enrichedEnvironment` 가 러너
프로세스에 환경변수를 넣어주므로 `os.environ` 에서 바로 잡힌다.
"""

from __future__ import annotations

import os
from collections.abc import Sequence


def load_env_file(path: str) -> dict[str, str]:
    """`KEY=VALUE` 줄만 읽는다. 없거나 못 읽으면 빈 dict."""
    values: dict[str, str] = {}
    try:
        with open(path, encoding="utf-8") as handle:
            lines = handle.read().splitlines()
    except OSError:
        return values

    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        value = value.strip()
        # 따옴표로 감싼 값을 허용한다.
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        values[key.strip()] = value
    return values


def resolve_api_key(
    name: str = "ANTHROPIC_API_KEY",
    *,
    search_dirs: Sequence[str] | None = None,
    environ: dict[str, str] | None = None,
) -> str | None:
    """환경변수 → 각 디렉터리의 `.env` 순으로 찾는다. 첫 번째로 찾은 것이 이긴다."""
    env = os.environ if environ is None else environ
    direct = (env.get(name) or "").strip()
    if direct:
        return direct

    dirs = search_dirs if search_dirs is not None else [os.path.dirname(os.path.dirname(__file__))]
    for directory in dirs:
        value = load_env_file(os.path.join(directory, ".env")).get(name, "").strip()
        if value:
            return value
    return None
