"""Markdown renderer 단위 테스트."""

import pytest

from ontology import NewsCategory, NewsOntology
from renderers.markdown import render_markdown_report


# 시나리오 1. 정제된 리포트 데이터를 Markdown 문서로 변환한다.
@pytest.mark.unit
def test_render_markdown_report__categorized_items__includes_report_sections():
    # Given: 카테고리와 요약이 포함된 리포트 item을 준비한다.
    ontology = NewsOntology(
        categories=[NewsCategory(label="AI", keywords=["AI"], description="")]
    )
    items = [
        {
            "title": "AI 뉴스",
            "url": "https://example.com",
            "category": "AI",
            "importanceScore": 90,
            "headline": "AI 에이전트 시장이 확대되고 있다.",
            "bullets": ["기업 도입 사례 증가"],
        }
    ]

    # When: Markdown renderer를 실행한다.
    markdown = render_markdown_report(
        items=items,
        date_str="2026-05-27",
        generated_at="2026-05-27 10:00",
        interest_keywords=["AI"],
        source_stats={"google_news": {"used": 1, "failed": 0}},
        warnings=[],
        ontology=ontology,
        category_keywords={"AI": ["agent"]},
        category_trends={"AI": "AI 에이전트 도입이 늘고 있다."},
    )

    # Then: 기본 섹션, 카테고리, item 내용이 Markdown에 포함된다.
    assert "# 뉴스 큐레이션 리포트 - 2026-05-27" in markdown
    assert "## 수집 현황" in markdown
    assert "## AI" in markdown
    assert "🔑 키워드: agent" in markdown
    assert "[AI 뉴스](https://example.com)" in markdown
    assert "## 오늘의 액션 아이템" in markdown
