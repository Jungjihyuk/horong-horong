from .base_provider import BaseCliProvider

class AntigravityCliProvider(BaseCliProvider):
    def _build_command(self, prompt: str) -> list[str]:
        return ["agy", "-p", prompt]