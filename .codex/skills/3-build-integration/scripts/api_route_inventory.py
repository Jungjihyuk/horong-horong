#!/usr/bin/env python3
"""Extract a lightweight API route inventory from FastAPI router files."""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path

ROUTER_PREFIX_RE = re.compile(r"APIRouter\([^\)]*prefix\s*=\s*['\"]([^'\"]+)['\"]")
ROUTE_RE = re.compile(
    r"@router\.(get|post|put|patch|delete|options|head)\(\s*['\"]([^'\"]*)['\"]"
)


@dataclass
class Route:
    method: str
    path: str
    file: str


def join_path(prefix: str, path: str) -> str:
    prefix = prefix.strip()
    path = path.strip()
    if not prefix.startswith("/"):
        prefix = "/" + prefix
    if path in {"", "/"}:
        return prefix
    if not path.startswith("/"):
        path = "/" + path
    return prefix.rstrip("/") + path


def extract_routes(py_file: Path) -> list[Route]:
    text = py_file.read_text(encoding="utf-8")
    prefix_match = ROUTER_PREFIX_RE.search(text)
    prefix = prefix_match.group(1) if prefix_match else ""

    routes: list[Route] = []
    for match in ROUTE_RE.finditer(text):
        method = match.group(1).upper()
        path = match.group(2)
        full = join_path(prefix, path)
        routes.append(Route(method=method, path=full, file=str(py_file)))
    return routes


def build_markdown(routes: list[Route]) -> str:
    routes = sorted(routes, key=lambda r: (r.path, r.method))
    lines = [
        "# API Route Inventory",
        "",
        "| Method | Path | Source File |",
        "|---|---|---|",
    ]
    for r in routes:
        lines.append(f"| {r.method} | `{r.path}` | `{r.file}` |")
    if not routes:
        lines.append("| - | - | - |")
    lines.append("")
    lines.append(f"Total routes: **{len(routes)}**")
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description="Extract FastAPI route inventory")
    parser.add_argument("--api-dir", required=True, help="Directory containing router .py files")
    parser.add_argument("--out", help="Optional markdown output path")
    args = parser.parse_args()

    api_dir = Path(args.api_dir)
    if not api_dir.exists():
        raise SystemExit(f"API directory not found: {api_dir}")

    routes: list[Route] = []
    for py_file in sorted(api_dir.rglob("*.py")):
        if py_file.name.startswith("__"):
            continue
        routes.extend(extract_routes(py_file))

    md = build_markdown(routes)

    if args.out:
        out = Path(args.out)
        out.write_text(md, encoding="utf-8")
        print(f"Wrote route inventory: {out}")
    else:
        print(md)


if __name__ == "__main__":
    main()
