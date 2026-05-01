from .base_provider import BaseCliProvider


class CodexCliProvider(BaseCliProvider):
    def _build_command(self, prompt: str) -> list[str]:
        return ["codex", prompt]
