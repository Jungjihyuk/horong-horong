from .base_provider import BaseCliProvider


class OpencodeCliProvider(BaseCliProvider):
    def _build_command(self, prompt: str) -> list[str]:
        return ["opencode", "run", "--message", prompt, "--non-interactive"]
