"""뉴스 카테고리 체계를 생성, 저장, 분류하는 ontology 패키지.

사용자 관심 키워드를 기반으로 카테고리 체계를 만들고, 캐시하고, 뉴스 항목을
분류한다. semantic classifier, topic discovery, ontology evolution, GraphRAG 관련
로직을 이 패키지의 확장 지점으로 둔다.
"""

from ontology.classifier import keyword_match
from ontology.models import NewsCategory, NewsOntology
from ontology.service import load_or_build, load_or_build_for_output_dir

__all__ = [
    "NewsCategory",
    "NewsOntology",
    "keyword_match",
    "load_or_build",
    "load_or_build_for_output_dir",
]
