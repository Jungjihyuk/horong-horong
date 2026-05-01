import subprocess
from abc import ABC, abstractmethod


class BaseCliProvider(ABC):
    timeout = 120

    @abstractmethod
    def _build_command(self, prompt: str) -> list[str]:
        pass

    def run(self, prompt: str) -> str:
        cmd = self._build_command(prompt)
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=self.timeout,
        )
        if result.returncode != 0:
            raise RuntimeError(
                f"{self.__class__.__name__} 실행 실패 (exit {result.returncode}): {result.stderr[:200]}"
            )
        return result.stdout.strip()
