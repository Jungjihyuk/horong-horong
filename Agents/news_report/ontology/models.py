"""뉴스 온톨로지 데이터 모델."""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any


@dataclass
class NewsCategory:
    label: str
    keywords: list[str]
    description: str = ""


@dataclass
class NewsOntology:
    version: int = 1
    interestKeywordsHash: str = ""
    interestKeywords: list[str] = field(default_factory=list)
    generatedAt: str = ""
    source: str = "seed"  # "llm" | "seed"
    categories: list[NewsCategory] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "NewsOntology":
        categories = [NewsCategory(**category) for category in data.get("categories", [])]
        return cls(
            version=int(data.get("version", 1)),
            interestKeywordsHash=str(data.get("interestKeywordsHash", "")),
            interestKeywords=list(data.get("interestKeywords", [])),
            generatedAt=str(data.get("generatedAt", "")),
            source=str(data.get("source", "seed")),
            categories=categories,
        )

    def labels(self) -> list[str]:
        return [category.label for category in self.categories]
