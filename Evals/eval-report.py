#!/usr/bin/env python3
"""JSONL 평가 결과를 읽어 사람이 읽기 쉬운 정적 HTML 매트릭스(히트맵)로 변환한다."""

import argparse
import json
import os
from collections import defaultdict

METRIC_DESC = {
    "honorific": "존댓말 비율",
    "sentenceCount": "문장 수 제한",
    "groundedness": "사실 기반",
    "pairF1": "F1 스코어",
    "predictedGroups": "추천 목표 개수",
}

METRIC_SHORT = {
    "honorific": "존대",
    "sentenceCount": "문장",
    "groundedness": "사실",
    "pairF1": "F1",
    "predictedGroups": "개수",
}

LEVEL_DESC = {
    "L0": "Prompt-only",
    "L1": "Structured-context",
    "L2": "Lexical-retrieval",
    "L3": "Hybrid-retrieval",
    "L4": "Graph-augmented",
}

HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>AI 실험실 - 평가 매트릭스</title>
    <style>
        :root {
            --bg: #f4f5f7;
            --panel: #ffffff;
            --panel-alt: #fafbfc;
            --ink: #1b1f24;
            --muted: #6b7280;
            --faint: #9ca3af;
            --line: #e3e6ea;
            --bubble: #f1f3f5;
            --accent: #2563eb;
            --pass-bg: #dcfce7; --pass-fg: #15803d;
            --mid-bg:  #fef9c3; --mid-fg:  #a16207;
            --warn-bg: #ffedd5; --warn-fg: #c2410c;
            --fail-bg: #fee2e2; --fail-fg: #b91c1c;
            --shadow: 0 1px 3px rgba(0,0,0,0.08);
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --bg: #17191c;
                --panel: #1f2226;
                --panel-alt: #24282d;
                --ink: #e8eaed;
                --muted: #9aa1a9;
                --faint: #6b7280;
                --line: #32363c;
                --bubble: #2a2e34;
                --accent: #60a5fa;
                --pass-bg: #10331f; --pass-fg: #4ade80;
                --mid-bg:  #3a3213; --mid-fg:  #fbbf24;
                --warn-bg: #3d2410; --warn-fg: #fb923c;
                --fail-bg: #3d1a1a; --fail-fg: #f87171;
                --shadow: 0 1px 3px rgba(0,0,0,0.4);
            }
        }

        * { box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            margin: 0; padding: 24px 28px 48px;
            background: var(--bg); color: var(--ink);
            -webkit-font-smoothing: antialiased;
        }
        h1 { font-size: 22px; margin: 0 0 4px; letter-spacing: -0.01em; }
        .subtitle { font-size: 13px; color: var(--muted); margin: 0 0 18px; }

        /* 탭 */
        .tabs { display: flex; gap: 4px; border-bottom: 1px solid var(--line); margin-bottom: 16px; }
        .tab-button {
            background: none; border: none; padding: 9px 16px; font-size: 14px; font-weight: 600;
            color: var(--muted); cursor: pointer; border-bottom: 2px solid transparent; margin-bottom: -1px;
            font-family: inherit;
        }
        .tab-button:hover { color: var(--ink); }
        .tab-button.active { color: var(--accent); border-bottom-color: var(--accent); }
        .tab-content { display: none; }
        .tab-content.active { display: block; }

        /* 요약 + 필터 바 */
        .toolbar {
            display: flex; align-items: center; gap: 8px; flex-wrap: wrap;
            margin-bottom: 14px;
        }
        .chip {
            display: inline-flex; align-items: center; gap: 5px;
            font-size: 12px; padding: 4px 9px; border-radius: 6px;
            background: var(--panel); border: 1px solid var(--line);
        }
        .chip b { font-weight: 600; }
        .chip.is-warn b { color: var(--warn-fg); }
        .toolbar .spacer { flex: 1; }
        .filter { display: inline-flex; border: 1px solid var(--line); border-radius: 6px; overflow: hidden; }
        .filter button {
            background: var(--panel); border: none; border-right: 1px solid var(--line);
            padding: 5px 12px; font-size: 12px; color: var(--muted); cursor: pointer; font-family: inherit;
        }
        .filter button:last-child { border-right: none; }
        .filter button.active { background: var(--accent); color: #fff; font-weight: 600; }
        .hint { font-size: 12px; color: var(--muted); margin: 0 0 12px; }

        /* 표 */
        .table-wrap {
            background: var(--panel); border: 1px solid var(--line); border-radius: 10px;
            box-shadow: var(--shadow); overflow: auto; max-height: 78vh;
        }
        /* 열 폭을 내용이 아니라 표가 정한다. 열마다 균등하게 나뉘어 비교하기 쉬워진다. */
        table { border-collapse: separate; border-spacing: 0; width: 100%; table-layout: fixed; }
        th, td {
            border-bottom: 1px solid var(--line); border-right: 1px solid var(--line);
            padding: 10px 12px; text-align: left; vertical-align: top;
            overflow-wrap: break-word;
        }
        th:last-child, td:last-child { border-right: none; }
        tbody tr:last-child td { border-bottom: none; }

        thead th {
            position: sticky; top: 0; z-index: 3;
            background: var(--panel-alt); font-weight: 600; font-size: 13px;
            white-space: nowrap;
        }
        thead th .lvl-desc { font-size: 11px; color: var(--muted); font-weight: 400; margin-left: 6px; }
        thead th .col-agg { display: block; font-size: 11px; color: var(--muted); font-weight: 400; margin-top: 3px; }

        .case-col { position: sticky; left: 0; z-index: 2; background: var(--panel); width: 200px; min-width: 200px; }
        thead .case-col { z-index: 4; background: var(--panel-alt); }
        tbody tr:nth-child(even) td { background: var(--panel-alt); }
        tbody tr:hover td { background: color-mix(in srgb, var(--accent) 7%, var(--panel)); }

        .case-id { font-size: 13px; font-weight: 600; display: flex; align-items: center; gap: 6px; }
        .dot { width: 7px; height: 7px; border-radius: 50%; flex: none; }
        .dot.pass { background: var(--pass-fg); }
        .dot.mid  { background: var(--mid-fg); }
        .dot.warn { background: var(--warn-fg); }
        .dot.fail { background: var(--fail-fg); }
        .case-q { font-size: 12px; color: var(--muted); margin-top: 4px; line-height: 1.45; }

        .cell-content {
            font-size: 13px; line-height: 1.55; color: var(--ink);
            background: var(--bubble); padding: 8px 10px; border-radius: 7px;
            white-space: pre-wrap; margin-bottom: 8px;
        }
        .score-row { display: flex; flex-wrap: wrap; gap: 4px; }
        .badge {
            display: inline-flex; align-items: baseline; gap: 4px;
            padding: 2px 7px; border-radius: 5px; font-size: 11px; white-space: nowrap;
        }
        .badge b { font-weight: 700; }
        .badge.pass { background: var(--pass-bg); color: var(--pass-fg); }
        .badge.mid  { background: var(--mid-bg);  color: var(--mid-fg); }
        .badge.warn { background: var(--warn-bg); color: var(--warn-fg); }
        .badge.fail { background: var(--fail-bg); color: var(--fail-fg); }
        .meta { font-size: 11px; color: var(--faint); margin-top: 8px; text-align: right; }
        .empty { color: var(--faint); text-align: center; font-size: 12px; }
    </style>
    <script>
        function openTab(tabId) {
            document.querySelectorAll('.tab-content').forEach(el => el.classList.remove('active'));
            document.querySelectorAll('.tab-button').forEach(el => el.classList.remove('active'));
            document.getElementById(tabId).classList.add('active');
            document.querySelector(`[data-tab="${tabId}"]`).classList.add('active');
        }

        /** 표 안의 행을 '전체 / 주의' 로 걸러낸다. 주의 = 0.5 미만 점수가 하나라도 있는 케이스. */
        function filterRows(button, tableId, mode) {
            button.parentElement.querySelectorAll('button').forEach(el => el.classList.remove('active'));
            button.classList.add('active');
            document.querySelectorAll(`#${tableId} tbody tr`).forEach(tr => {
                tr.style.display = (mode === 'warn' && tr.dataset.warn !== '1') ? 'none' : '';
            });
        }
    </script>
</head>
<body>
    <h1>AI 실험실 · 평가 매트릭스</h1>
    <p class="subtitle">행은 테스트 케이스, 열은 비교 축입니다. 0.5 미만 점수는 주황/빨강으로 표시됩니다.</p>
    <div class="tabs">
        <button class="tab-button active" data-tab="tab-level" onclick="openTab('tab-level')">1. 컨텍스트 주입 레벨별 비교</button>
        <button class="tab-button" data-tab="tab-model" onclick="openTab('tab-model')">2. LLM 모델별 비교</button>
    </div>
    {rows}
</body>
</html>
"""


def score_class(value):
    """AILabView 와 같은 임계값. 1.0 통과 / 0.0 실패 / 0.5 미만 주의 / 나머지 중간."""
    if value >= 0.99:
        return "pass"
    if value <= 0.01:
        return "fail"
    if value < 0.5:
        return "warn"
    return "mid"


def format_score(name, value):
    display_name = METRIC_DESC.get(name, name)
    short_name = METRIC_SHORT.get(name, name)

    if isinstance(value, (int, float)):
        cls = score_class(value)
        return (
            f"<span class='badge {cls}' title='{display_name}'>"
            f"{short_name} <b>{value:.2f}</b></span>"
        )
    return f"<span class='badge mid' title='{display_name}'>{short_name} <b>{value}</b></span>"


def is_warning(case_data):
    """케이스 안에 0.5 미만 점수가 하나라도 있으면 '주의'."""
    for result in case_data.values():
        for value in result.get("scores", {}).values():
            if isinstance(value, (int, float)) and value < 0.5:
                return True
    return False


def worst_class(case_data):
    values = [
        v
        for result in case_data.values()
        for v in result.get("scores", {}).values()
        if isinstance(v, (int, float))
    ]
    return score_class(min(values)) if values else "pass"


def column_summary(data_dict, column):
    """열 머리에 붙는 요약: 평균 점수 · 평균 지연."""
    results = [case_data[column] for case_data in data_dict.values() if column in case_data]
    if not results:
        return "데이터 없음"
    scores = [
        v
        for result in results
        for v in result.get("scores", {}).values()
        if isinstance(v, (int, float))
    ]
    avg_score = sum(scores) / len(scores) if scores else 0
    avg_latency = sum(r.get("latency_ms", 0) for r in results) // len(results)
    return f"평균 {avg_score:.2f} · {avg_latency}ms"


def render_table(data_dict, table_id, is_level=True):
    columns = set()
    for case_data in data_dict.values():
        columns.update(case_data.keys())
    sorted_cols = sorted(columns)

    headers = ""
    for col in sorted_cols:
        desc = ""
        if is_level:
            base_lvl = col.split(" ")[0]
            if base_lvl in LEVEL_DESC:
                desc = f"<span class='lvl-desc'>{LEVEL_DESC[base_lvl]}</span>"
        headers += (
            f"<th>{col}{desc}"
            f"<span class='col-agg'>{column_summary(data_dict, col)}</span></th>"
        )

    rows = []
    warning_count = 0
    for case_id, case_data in sorted(data_dict.items()):
        warn = is_warning(case_data)
        warning_count += 1 if warn else 0

        input_text = ""
        for result in case_data.values():
            if result.get("input"):
                input_text = result["input"]
                break

        question = f"<div class='case-q'>{input_text}</div>" if input_text else ""
        row = [
            f"<td class='case-col'>"
            f"<div class='case-id'><span class='dot {worst_class(case_data)}'></span>{case_id}</div>"
            f"{question}</td>"
        ]

        for col in sorted_cols:
            if col in case_data:
                result = case_data[col]
                output = result.get("output", "")
                scores = result.get("scores", {})
                latency = result.get("latency_ms", 0)
                score_html = "".join(format_score(k, v) for k, v in sorted(scores.items()))
                row.append(
                    f"<td>"
                    f"<div class='cell-content'>{output}</div>"
                    f"<div class='score-row'>{score_html}</div>"
                    f"<div class='meta'>⏱ {latency}ms</div>"
                    f"</td>"
                )
            else:
                row.append("<td class='empty'>데이터 없음</td>")
        rows.append(f"<tr data-warn='{1 if warn else 0}'>{''.join(row)}</tr>")

    toolbar = f"""
    <div class="toolbar">
        <span class="chip">케이스 <b>{len(data_dict)}</b></span>
        <span class="chip{' is-warn' if warning_count else ''}">주의 <b>{warning_count}</b></span>
        <span class="chip">{'레벨' if is_level else '모델'} <b>{len(sorted_cols)}</b></span>
        <span class="spacer"></span>
        <span class="filter">
            <button class="active" onclick="filterRows(this, '{table_id}', 'all')">전체</button>
            <button onclick="filterRows(this, '{table_id}', 'warn')">주의만</button>
        </span>
    </div>
    """

    return f"""
    {toolbar}
    <div class="table-wrap">
        <table id="{table_id}">
            <thead>
                <tr>
                    <th class="case-col">케이스 / 질문</th>
                    {headers}
                </tr>
            </thead>
            <tbody>
                {"".join(rows)}
            </tbody>
        </table>
    </div>
    """


def generate_html(data_by_level, data_by_model):
    table_level = render_table(data_by_level, "table-level", is_level=True)
    table_model = render_table(data_by_model, "table-model", is_level=False)

    html_body = f"""
    <div id="tab-level" class="tab-content active">
        <p class="hint">동일한 모델 환경에서 문맥(Context)을 얼마나 제공했는지에 따른 답변 차이를 비교합니다.</p>
        {table_level}
    </div>

    <div id="tab-model" class="tab-content">
        <p class="hint">동일한 컨텍스트 환경에서 모델(Provider)에 따른 답변 퀄리티와 속도 차이를 비교합니다.</p>
        {table_model}
    </div>
    """

    return HTML_TEMPLATE.replace("{rows}", html_body)

def main():
    parser = argparse.ArgumentParser(description="JSONL 평가 결과를 정적 HTML 대시보드로 변환합니다.")
    parser.add_argument("--input", "-i", type=str, required=True, help="입력 JSONL 파일 경로")
    parser.add_argument("--output", "-o", type=str, default="eval-report.html", help="출력 HTML 파일 경로")
    args = parser.parse_args()

    if not os.path.exists(args.input):
        print(f"Error: 입력 파일을 찾을 수 없습니다 - {args.input}")
        # 테스트를 위한 더미 데이터 생성
        print("테스트용 더미 데이터를 생성합니다...")
        with open(args.input, "w", encoding="utf-8") as f:
            cases = [
                ("tone-01", "테마 어디서 바꿔?", "설정에서 바꿀 수 있어요.", "설정 → 외관에서 바꾸실 수 있어요."),
                ("tone-02", "야 설정가서 바꿔라", "야, 설정가서 바꿔라", "외관 설정 탭에서 변경이 가능합니다. 감사합니다."),
                ("qa-01", "야", "네?", "네, 호롱호롱입니다. 무엇을 도와드릴까요?"),
                ("qa-02", "너는 누구야", "저는 AI 어시스턴트입니다.", "저는 호롱호롱 앱의 AI 컴패니언 '루미롱'입니다."),
                ("qa-03", "너는 무슨 모델이야?", "저는 언어 모델입니다.", "저는 설정하신 Apple 온디바이스(또는 MLX/Ollama) 모델로 구동되고 있습니다."),
                ("qa-04", "카테고리 매핑 하는 법 설명해줘", "카테고리는 설정에서 매핑합니다.", "설정 → 카테고리 매핑 탭에서 특정 앱이나 웹사이트를 원하시는 카테고리에 연결하실 수 있습니다."),
                ("qa-05", "몰입 기능 설명해줘", "몰입은 집중하는 기능입니다.", "몰입 기능은 세션마다 몰입도를 재고, 기준선 아래로 떨어지면 루미롱이 말을 걸어주는 집중 넛지 기능입니다."),
                ("qa-06", "몰입에서 집중 넛지는 뭐야?", "집중하라고 알림을 주는 것입니다.", "집중 넛지는 몰입도가 설정된 기준선 밑으로 떨어졌을 때, 화면 위에서 루미롱이 동기를 부여하는 잔소리를 해주는 기능입니다."),
                ("qa-07", "뉴스 리포트 생성 기능 설명해줘", "뉴스를 모아서 리포트로 줍니다.", "설정 → 뉴스 탭에서 관심사 키워드를 등록해두면, 정해진 수집 간격마다 요약 에이전트가 뉴스를 모아 일일 리포트를 자동 생성해 줍니다."),
                ("qa-08", "미리알림 연동하는 법 설명해줘", "미리알림 앱을 켜서 연결하세요.", "설정 → 메모 탭에서 '미리알림 가져오기'를 켜고 연동할 캘린더를 선택하시면 됩니다."),
                ("qa-09", "AI Agent 기능이 뭐야?", "AI가 작업을 대신 해줍니다.", "AI Agent 기능은 Codex, Claude, Antigravity 등의 모델을 활용해 터미널 명령을 실행하거나 자동화된 실험을 수행할 수 있게 해주는 기능입니다."),
                ("qa-10", "성취 설정에서 모델 설정 하는 법 알려줘", "성취 설정에서 모델을 선택하세요.", "설정 → 성취 탭의 '추천 엔진'에서 Apple 온디바이스, MLX, Ollama 중 하나를 선택하실 수 있습니다."),
                ("qa-11", "루미롱 활용법 알려줘", "루미롱은 비서입니다.", "루미롱은 화면 위에 띄워두고 대화를 나누거나, 집중 모드일 때 숨기기, 오늘 일정 브리핑 받기 등 설정 → 루미롱 탭에서 다양하게 커스텀하여 활용할 수 있습니다."),
                ("qa-12", "Apple 온디바이스, MLX, Ollama 이거 차이가 뭐야?", "각각 다른 모델 제공자입니다.", "Apple 온디바이스는 빠르고 준비가 필요 없지만, MLX는 더 많은 할 일을 묶을 수 있는 대신 메모리를 쓰고, Ollama는 앱 외부 프로세스로 큰 모델을 구동할 수 있습니다.")
            ]
            for cid, q, l0, l1 in cases:
                f.write(f'{{"case_id": "{cid}", "input": "{q}", "level": "L0", "model": "mlx-llama3", "output": "{l0}", "scores": {{"honorific": 1.0, "sentenceCount": 1.0, "groundedness": 0.2}}, "latency_ms": 400}}\n')
                f.write(f'{{"case_id": "{cid}", "input": "{q}", "level": "L1", "model": "gpt-4o-mini", "output": "{l1}", "scores": {{"honorific": 1.0, "sentenceCount": 1.0, "groundedness": 0.9}}, "latency_ms": 800}}\n')

    data_by_level = defaultdict(dict)
    data_by_model = defaultdict(dict)

    with open(args.input, "r", encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            try:
                row = json.loads(line)
                case_id = row.get("case_id", "unknown")
                level = row.get("level", "L0")
                model = row.get("model", "unknown")

                # 레벨별 표: 행=case, 열=level
                data_by_level[case_id][level] = row

                # 모델별 표: 행=case, 열=model
                if model:
                    data_by_model[case_id][model] = row
            except json.JSONDecodeError:
                continue

    html = generate_html(data_by_level, data_by_model)

    with open(args.output, "w", encoding="utf-8") as f:
        f.write(html)

    print(f"✅ HTML 대시보드 생성 완료: {os.path.abspath(args.output)}")
    print(f"터미널에서 'open {args.output}' 명령어를 실행하여 브라우저에서 확인하세요.")

if __name__ == "__main__":
    main()
