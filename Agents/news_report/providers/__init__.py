"""LLM 또는 agent 실행 구현체를 제공하는 provider 패키지.

Codex, Claude, Gemini 같은 외부 CLI provider와 Ollama, MLX 같은 로컬 provider를
같은 `run(prompt) -> str` 계약으로 다룬다.
"""
