from .base_provider import BaseCliProvider


class ClaudeCliProvider(BaseCliProvider):
    def _build_command(self, prompt: str) -> list[str]:
        return ["claude", "-p", prompt]
