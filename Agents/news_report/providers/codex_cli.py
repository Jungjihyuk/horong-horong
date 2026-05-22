from .base_provider import BaseCliProvider


class CodexCliProvider(BaseCliProvider):
    """OpenAI Codex CLI 비대화 모드.

    `codex <prompt>` 형태는 대화형 진입이라 stdin TTY 가 없으면 'stdin is not a terminal' 로 실패한다.
    `codex exec <prompt>` 가 1회성 비대화 실행이며 subprocess 환경에서 정상 동작한다.
    앱의 뉴스 데이터 디렉터리는 git 저장소 밖일 수 있으므로 repo 신뢰 검사를 건너뛴다.
    """

    def _build_command(self, prompt: str) -> list[str]:
        return ["codex", "exec", "--skip-git-repo-check", prompt]
