"""기존 리포트들을 artifacts.json 형태로 복원하는 백필 스크립트."""

import argparse
import json
import logging
from pathlib import Path
from typing import Any

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")

def build_dummy_artifacts(meta: dict[str, Any], md_content: str) -> dict[str, Any]:
    # 기존 meta.json과 md_content를 통해 최소한의 아티팩트 복원
    # 현재는 정보 손실을 감수하고, 앱이 깨지지 않는 구조만 생성
    return {
        "schemaVersion": 1,
        "jobId": meta.get("jobId", "unknown"),
        "reportDate": meta.get("reportDate", "unknown"),
        "generationContext": None,
        "taxonomy": None,
        "candidates": [],
        "assignments": [],
        "sourceInsights": [],
        "keywordInsights": [],
        "trends": [],
        "bundles": [],
        "reportContent": {
            "report_id": meta.get("jobId", "unknown"),
            "title": f"{meta.get('reportDate', 'unknown')} 뉴스 리포트",
            "generated_at": meta.get("generatedAt", "unknown"),
            "interest_keywords": [],
            "bundle_ids": [],
            "keyword_insight_ids": [],
            "trend_insight_ids": [],
        },
    }

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="실제 저장을 수행하지 않음")
    parser.add_argument("--data-dir", type=str, default="data", help="데이터 디렉터리 경로")
    args = parser.parse_args()

    data_dir = Path(args.data_dir)
    meta_dir = data_dir / "meta"
    reports_dir = data_dir / "reports"
    artifacts_dir = data_dir / "artifacts"

    if not args.dry_run:
        artifacts_dir.mkdir(parents=True, exist_ok=True)

    if not meta_dir.exists():
        logging.error(f"Meta directory not found: {meta_dir}")
        return

    success_count = 0
    for meta_path in meta_dir.glob("*.meta.json"):
        try:
            with open(meta_path, "r", encoding="utf-8") as f:
                meta = json.load(f)
            
            report_path = reports_dir / f"{meta_path.name.replace('.meta.json', '.md')}"
            md_content = report_path.read_text(encoding="utf-8") if report_path.exists() else ""

            artifacts = build_dummy_artifacts(meta, md_content)
            artifacts_path = artifacts_dir / meta_path.name.replace(".meta.json", ".artifacts.json")

            if args.dry_run:
                logging.info(f"[Dry-run] Would create {artifacts_path}")
            else:
                with open(artifacts_path, "w", encoding="utf-8") as f:
                    json.dump(artifacts, f, indent=2, ensure_ascii=False)
                logging.info(f"Created {artifacts_path}")
            
            success_count += 1
        except Exception as e:
            logging.error(f"Failed to process {meta_path.name}: {e}")
    
    logging.info(f"Backfill complete: {success_count} reports processed.")

if __name__ == "__main__":
    main()
