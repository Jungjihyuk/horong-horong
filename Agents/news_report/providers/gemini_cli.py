from .base_provider import BaseCliProvider


class GeminiCliProvider(BaseCliProvider):
    def _build_command(self, prompt: str) -> list[str]:
        return ["gemini", "--skip-trust", "-p", prompt]
