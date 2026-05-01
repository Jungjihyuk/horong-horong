#!/usr/bin/env python3
"""Create a study note scaffold file under docs/8. 기술 문서/학습 노트."""

from __future__ import annotations

import argparse
import re
from datetime import datetime
from pathlib import Path


def slugify(text: str) -> str:
    text = text.strip().lower()
    text = re.sub(r"\s+", "-", text)
    text = re.sub(r"[^a-z0-9가-힣_-]", "", text)
    text = re.sub(r"-+", "-", text).strip("-")
    return text or "study-note"


def ensure_unique_path(path: Path) -> Path:
    if not path.exists():
        return path
    stem = path.stem
    suffix = path.suffix
    parent = path.parent
    i = 2
    while True:
        cand = parent / f"{stem}-{i}{suffix}"
        if not cand.exists():
            return cand
        i += 1


def load_template(template_path: Path, topic: str, today: str, keywords: str) -> str:
    if template_path.exists():
        content = template_path.read_text(encoding="utf-8")
    else:
        content = "# 📘 <주제>\n\n- 작성일: <YYYY-MM-DD>\n- 키워드: <k1>, <k2>, <k3>\n"

    content = content.replace("<주제>", topic)
    content = content.replace("<YYYY-MM-DD>", today)
    content = content.replace("<k1>, <k2>, <k3>", keywords if keywords else topic)
    return content


def append_index(index_path: Path, title: str, rel_file: str) -> None:
    line = f"- [[학습 노트/{rel_file}|{title}]]"
    if index_path.exists():
        current = index_path.read_text(encoding="utf-8")
        if line in current:
            return
        if not current.endswith("\n"):
            current += "\n"
        current += line + "\n"
        index_path.write_text(current, encoding="utf-8")
        return

    base = "# 📚 학습 노트 INDEX\n\n" + line + "\n"
    index_path.write_text(base, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Create study note scaffold")
    parser.add_argument("--docs-root", default="docs", help="Docs root path")
    parser.add_argument("--topic", required=True, help="Topic title or keyword")
    parser.add_argument("--keywords", default="", help="Comma-separated keywords")
    parser.add_argument(
        "--template",
        default=".claude/skills/5-operate-study/references/study-note-template.md",
        help="Template path",
    )
    args = parser.parse_args()

    today = datetime.now().strftime("%Y-%m-%d")
    topic = args.topic.strip()
    slug = slugify(topic)

    notes_dir = Path(args.docs_root) / "8. 기술 문서" / "학습 노트"
    notes_dir.mkdir(parents=True, exist_ok=True)

    out_path = ensure_unique_path(notes_dir / f"{today}-{slug}.md")
    template_path = Path(args.template)
    content = load_template(template_path, topic=topic, today=today, keywords=args.keywords)
    out_path.write_text(content, encoding="utf-8")

    index_path = notes_dir / "INDEX.md"
    append_index(index_path, title=topic, rel_file=out_path.name)

    print(f"Created note: {out_path}")
    print(f"Updated index: {index_path}")


if __name__ == "__main__":
    main()
