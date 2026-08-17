#!/usr/bin/env python3
"""JSONL 평가 결과 및 실사용(Live) 기록을 읽어 사람이 읽기 쉬운 정적 HTML 대시보드로 변환한다."""

import argparse
import json
import os
import glob
from collections import defaultdict

def load_golden_notes():
    """케이스 설명(note)의 원본은 골든셋 JSON 이다.

    기록(JSONL)에는 담지 않는다 — 실행마다 같은 문장을 되풀이해 저장할 이유가 없고,
    문구를 고치면 옛 기록과 어긋난다. 보여줄 때 여기서 읽는다.
    """
    notes = {}
    here = os.path.dirname(os.path.abspath(__file__))
    for folder in ("golden/cases", "golden/drafts"):
        directory = os.path.join(here, folder)
        if not os.path.isdir(directory):
            continue
        for name in sorted(os.listdir(directory)):
            if not name.endswith(".json"):
                continue
            try:
                with open(os.path.join(directory, name), encoding="utf-8") as f:
                    case = json.load(f)
                notes[case.get("caseName", "")] = case.get("note") or ""
            except (OSError, ValueError):
                continue
    return notes


GOLDEN_NOTES = load_golden_notes()


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
        .chip.is-pass b { color: var(--pass-fg); }
        .chip.is-fail b { color: var(--fail-fg); }
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

        .case-col { position: sticky; left: 0; z-index: 2; background: var(--panel); width: 230px; min-width: 230px; }
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

        /* 실사용 카드 스타일 */
        .live-card {
            background: var(--panel); border: 1px solid var(--line); border-radius: 8px;
            padding: 10px; display: flex; flex-direction: column; gap: 6px; font-size: 12px;
        }
        .live-card-header {
            display: flex; align-items: center; justify-content: space-between; gap: 6px;
        }
        .live-provider { font-weight: 700; font-size: 13px; }
        .live-model { font-size: 11px; color: var(--muted); }
        .live-params {
            background: var(--bubble); padding: 4px 6px; border-radius: 4px; font-size: 11px;
            color: var(--muted); font-family: monospace;
        }
        .live-stat-row { display: flex; justify-content: space-between; font-size: 11px; color: var(--muted); }
    </style>
    <script>
        function openTab(tabId) {
            document.querySelectorAll('.tab-content').forEach(el => el.classList.remove('active'));
            document.querySelectorAll('.tab-button').forEach(el => el.classList.remove('active'));
            const content = document.getElementById(tabId);
            if (content) content.classList.add('active');
            const btn = document.querySelector(`[data-tab="${tabId}"]`);
            if (btn) btn.classList.add('active');
        }

        /** 표 안의 행을 '전체 / 주의' 로 걸러낸다. 주의 = 0.5 미만 점수 또는 실패가 있는 케이스. */
        function filterRows(button, tableId, mode) {
            button.parentElement.querySelectorAll('button').forEach(el => el.classList.remove('active'));
            button.classList.add('active');
            document.querySelectorAll(`#${tableId} tbody tr`).forEach(tr => {
                if (mode === 'all') {
                    tr.style.display = '';
                } else if (mode === 'warn') {
                    tr.style.display = (tr.dataset.warn === '1') ? '' : 'none';
                } else if (mode === 'fail') {
                    tr.style.display = (tr.dataset.fail === '1') ? '' : 'none';
                } else if (mode === 'ok') {
                    tr.style.display = (tr.dataset.fail !== '1') ? '' : 'none';
                }
            });
        }
    </script>
</head>
<body>
    <h1>AI 실험실 · 평가 매트릭스</h1>
    <p class="subtitle">행은 테스트 케이스/실행, 열은 비교 축입니다. 0.5 미만 점수 또는 실패는 주황/빨강으로 표시됩니다.</p>
    <div class="tabs">
        {tab_buttons}
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


def format_seconds(ms):
    if ms is None:
        return "-"
    sec = ms / 1000.0
    if sec >= 10:
        return f"{sec:.1f}s"
    else:
        return f"{sec:.2f}s"


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
    avg_latency = sum(r.get("total_ms", r.get("latency_ms", 0)) for r in results) // len(results)
    return f"평균 {avg_score:.2f} · {format_seconds(avg_latency)}"


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

        # 케이스 설명은 기록이 아니라 골든셋 JSON 이 원본이다(중복 저장하지 않는다).
        input_text = GOLDEN_NOTES.get(case_id, "")

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
                latency = result.get("total_ms", result.get("latency_ms", 0))
                score_html = "".join(format_score(k, v) for k, v in sorted(scores.items()))
                row.append(
                    f"<td>"
                    f"<div class='cell-content'>{output}</div>"
                    f"<div class='score-row'>{score_html}</div>"
                    f"<div class='meta'>⏱ {format_seconds(latency)}</div>"
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


def get_outcome_info(outcome, detail):
    if outcome == "ok":
        return "성공 (ok)", "목표 초안이 정상적으로 생성 및 파싱되었습니다."
    elif outcome == "generationFailed":
        if detail == "timeout":
            return "타임아웃 (timeout)", "60초 동안 모델이 응답하지 않아 시간 초과되었습니다."
        elif detail == "connectionRefused":
            return "서버 연결 실패 (connectionRefused)", "로컬 Ollama 데몬이 꺼져 있거나 포트에 접속할 수 없습니다."
        elif detail == "networkDisconnected":
            return "네트워크 단절", "네트워크 연결이 끊겼습니다."
        elif detail == "networkError":
            return "네트워크 오류", "모델 통신 중 네트워크 오류가 발생했습니다."
        elif detail:
            return f"생성 실패 ({detail})", f"LLM 추론 실패: {detail}"
        return "생성 실패 (generationFailed)", "LLM 추론 실패 또는 60초 타임아웃이 발생했습니다."
    elif outcome == "serverUnavailable":
        return "서버 불가 (serverUnavailable)", "Ollama 데몬이 꺼져 있거나 서버에 연결할 수 없습니다."
    elif outcome == "modelUnavailable":
        return "모델 불가 (modelUnavailable)", "해당 기기에서 지원하지 않거나 모델 파일이 없습니다."
    elif outcome == "decodeFailed":
        if detail == "noJSON":
            return "JSON 누락 (noJSON)", "모델 응답 안에 JSON 객체({})가 전혀 없습니다. (자연어로만 답변)"
        elif detail == "malformed":
            return "문법 오류 (malformed)", "JSON 형식이 깨져 파싱할 수 없습니다."
        elif detail == "missingKeys":
            return "필수 키 누락 (missingKeys)", "JSON에 title, memos 등 필수 필드가 빠졌습니다."
        elif detail == "truncated":
            return "응답 잘림 (truncated)", "최대 토큰 길이에 도달해 JSON이 중간에 잘렸습니다."
        elif detail:
            return f"해석 실패 ({detail})", f"JSON 디코딩 실패: {detail}"
        return "JSON 해석 실패", "모델 출력을 JSON으로 파싱하지 못했습니다."
    elif outcome in ("parsedEmpty", "validationFailed"):
        if detail == "emptyList":
            return "초안 목록 비어있음 (emptyList)", "모델이 빈 목록([])을 반환했습니다."
        elif detail == "hallucinatedIDs":
            return "가짜 ID 환각 (hallucinatedIDs)", "입력에 없는 가짜 메모 ID를 생성하여 비즈니스 검증에서 모두 탈락했습니다."
        elif detail == "tooFewMemos":
            return "메모 개수 부족 (tooFewMemos)", "목표당 최소 메모 묶음 기준에 미달하여 제외되었습니다."
        elif detail == "duplicateMemos":
            return "중복 메모 (duplicateMemos)", "이미 사용된 메모를 중복 재사용하여 제외되었습니다."
        elif detail:
            return f"검증 탈락 ({detail})", f"비즈니스 규칙 검증 실패: {detail}"
        return "유효 결과 없음 (parsedEmpty)", "JSON은 읽었으나 메모 ID 불일치/환각 등으로 쓸 수 있는 초안이 0개입니다."
    else:
        text = f"{outcome}:{detail}" if detail else outcome
        return text, text


def render_live_table(live_runs_by_key):
    """실사용(Live) 기록을 렌더링한다: 행=실행(run_id + task), 열=시도(attempt 1, 2, ...)."""
    if not live_runs_by_key:
        return "<p class='hint'>실사용(Live) 기록이 없습니다.</p>"

    # 최대 시도 횟수 확인
    max_attempts = 1
    for attempts in live_runs_by_key.values():
        if attempts:
            max_attempts = max(max_attempts, max(attempts.keys()))

    headers = "".join(f"<th>시도 {i} (Attempt {i})</th>" for i in range(1, max_attempts + 1))

    rows = []
    total_runs = len(live_runs_by_key)
    success_count = 0
    fail_count = 0

    # 최신 실행 순 정렬 (run_id 역순)
    for run_key, attempts in sorted(live_runs_by_key.items(), key=lambda x: x[0], reverse=True):
        last_attempt_idx = max(attempts.keys()) if attempts else 1
        last_record = attempts.get(last_attempt_idx, {})
        is_fail = (last_record.get("outcome") != "ok")
        if is_fail:
            fail_count += 1
        else:
            success_count += 1

        run_id = last_record.get("run_id", run_key)
        task = last_record.get("task", "")
        started_at = last_record.get("started_at", "")

        row = [
            f"<td class='case-col'>"
            f"<div class='case-id'><span class='dot {'fail' if is_fail else 'pass'}'></span>{run_id}</div>"
            f"<div class='case-q'><b>{task}</b><br><span style='font-size:11px;color:var(--faint);'>{started_at}</span></div>"
            f"</td>"
        ]

        for att_idx in range(1, max_attempts + 1):
            if att_idx in attempts:
                rec = attempts[att_idx]
                outcome = rec.get("outcome", "unknown")
                outcome_detail = rec.get("outcome_detail")
                provider = rec.get("provider", "unknown")
                model = rec.get("model", "")
                total_ms = rec.get("total_ms", 0)
                timings = rec.get("timings", {})
                gen_ms = timings.get("generate", total_ms)
                input_sum = rec.get("input_summary", {})
                cand_cnt = input_sum.get("candidate_count", "-")
                item_cnt = input_sum.get("item_count", "-")
                prompt_chars = input_sum.get("prompt_characters", 0)
                output = rec.get("output", "")
                parse_sum = rec.get("parse")
                params = rec.get("parameters")

                badge_cls = "pass" if outcome == "ok" else ("warn" if outcome == "parsedEmpty" else "fail")
                badge_text, badge_tooltip = get_outcome_info(outcome, outcome_detail)

                params_html = ""
                if params:
                    params_str = ", ".join(f"{k}:{v:g}" for k, v in params.items())
                    params_html = f"<div class='live-params' title='Hyperparameters'>⚙️ {params_str}</div>"

                parse_html = ""
                if parse_sum:
                    m_ret = parse_sum.get('model_returned', 0)
                    kept = parse_sum.get('kept', 0)
                    parse_html = (
                        f"<div class='live-stat-row' title='모델이 제안한 추천 목표 총 {m_ret}개 중 유효성 검증을 통과한 최종 추천 목표 {kept}개'><span>추천 목표</span>"
                        f"<span>총 <b>{m_ret}</b>개 중 최종 <b>{kept}</b>개 채택</span></div>"
                    )

                usage_html = ""
                usage_dict = rec.get("usage")
                if usage_dict and (usage_dict.get("tokens_in") is not None or usage_dict.get("tokens_out") is not None):
                    t_in = usage_dict.get("tokens_in", 0)
                    t_out = usage_dict.get("tokens_out", 0)
                    usage_html = (
                        f"<div class='live-stat-row'><span>토큰</span>"
                        f"<span>in:<b>{t_in}</b> / out:<b>{t_out}</b></span></div>"
                    )

                output_html = ""
                if output:
                    output_html = (
                        f"<div style='margin-bottom:4px;background:rgba(128,128,128,0.06);padding:6px;border-radius:6px;'>"
                        f"<div style='font-size:10px;font-weight:bold;color:var(--faint);margin-bottom:2px;'>💬 출력 (추천 결과)</div>"
                        f"<div class='cell-content'>{output}</div>"
                        f"</div>"
                    )

                card = f"""
                <div class="live-card">
                    <div class="live-card-header">
                        <span class="live-provider">{provider}</span>
                        <span class="badge {badge_cls}" title="{badge_tooltip}"><b>{badge_text}</b></span>
                    </div>
                    {f"<div class='live-model'>{model}</div>" if model else ""}
                    {params_html}
                    <div class="live-stat-row">
                        <span>후보 → 입력</span>
                        <span><b>{cand_cnt}</b> → <b>{item_cnt}</b> ({prompt_chars}자)</span>
                    </div>
                    {parse_html}
                    {usage_html}
                    {output_html}
                    <div class="live-stat-row meta" style="margin-top:2px;">
                        <span>생성 {format_seconds(gen_ms)}</span>
                        <span>총 <b>{format_seconds(total_ms)}</b></span>
                    </div>
                </div>
                """
                row.append(f"<td>{card}</td>")
            else:
                row.append("<td class='empty'>-</td>")

        rows.append(f"<tr data-fail='{1 if is_fail else 0}'>{''.join(row)}</tr>")

    toolbar = f"""
    <div class="toolbar">
        <span class="chip">총 실행 <b>{total_runs}</b></span>
        <span class="chip is-pass">최종 성공 <b>{success_count}</b></span>
        <span class="chip{' is-fail' if fail_count else ''}">최종 실패 <b>{fail_count}</b></span>
        <span class="chip">최대 폴백 시도 <b>{max_attempts}회</b></span>
        <span class="spacer"></span>
        <span class="filter">
            <button class="active" onclick="filterRows(this, 'table-live', 'all')">전체</button>
            <button onclick="filterRows(this, 'table-live', 'fail')">실패만</button>
            <button onclick="filterRows(this, 'table-live', 'ok')">성공만</button>
        </span>
    </div>
    """

    return f"""
    {toolbar}
    <div class="table-wrap">
        <table id="table-live">
            <thead>
                <tr>
                    <th class="case-col">실행 ID / 태스크</th>
                    {headers}
                </tr>
            </thead>
            <tbody>
                {"".join(rows)}
            </tbody>
        </table>
    </div>
    """


def generate_html(data_by_level, data_by_model, live_runs):
    has_golden = bool(data_by_level or data_by_model)
    has_live = bool(live_runs)

    tab_buttons = []
    tab_contents = []

    # 1. 실사용 기록 탭
    if has_live:
        tab_buttons.append('<button class="tab-button active" data-tab="tab-live" onclick="openTab(\'tab-live\')">1. 실사용 실행 기록 (Live)</button>')
        table_live = render_live_table(live_runs)
        tab_contents.append(f"""
        <div id="tab-live" class="tab-content active">
            <p class="hint">실제 앱 구동 중 수집된 실행 기록(`RunRecord`)입니다. 행은 실행 단위(`run_id`), 열은 폴백 사슬 시도(`attempt`)입니다.</p>
            {table_live}
        </div>
        """)

    # 2 & 3. 골든셋 평가 탭
    if has_golden:
        active_cls_level = " active" if not has_live else ""
        btn_num_level = "2." if has_live else "1."
        btn_num_model = "3." if has_live else "2."

        tab_buttons.append(f'<button class="tab-button{active_cls_level}" data-tab="tab-level" onclick="openTab(\'tab-level\')">{btn_num_level} 골든셋: 컨텍스트 레벨별 비교</button>')
        tab_buttons.append(f'<button class="tab-button" data-tab="tab-model" onclick="openTab(\'tab-model\')">{btn_num_model} 골든셋: LLM 모델별 비교</button>')

        table_level = render_table(data_by_level, "table-level", is_level=True)
        table_model = render_table(data_by_model, "table-model", is_level=False)

        tab_contents.append(f"""
        <div id="tab-level" class="tab-content{active_cls_level}">
            <p class="hint">동일한 모델 환경에서 문맥(Context)을 얼마나 제공했는지에 따른 답변 차이를 비교합니다.</p>
            {table_level}
        </div>
        """)

        tab_contents.append(f"""
        <div id="tab-model" class="tab-content">
            <p class="hint">동일한 컨텍스트 환경에서 모델(Provider)에 따른 답변 퀄리티와 속도 차이를 비교합니다.</p>
            {table_model}
        </div>
        """)

    return HTML_TEMPLATE.replace("{tab_buttons}", "".join(tab_buttons)).replace("{rows}", "".join(tab_contents))


def load_records_from_path(input_path):
    """파일 또는 디렉터리 경로에서 모든 JSONL 레코드를 읽어온다."""
    records = []
    files_to_read = []

    expanded_path = os.path.expanduser(input_path)

    if os.path.isdir(expanded_path):
        files_to_read = sorted(glob.glob(os.path.join(expanded_path, "*.jsonl")))
    elif os.path.isfile(expanded_path):
        files_to_read = [expanded_path]
    elif os.path.exists(expanded_path):
        files_to_read = [expanded_path]
    else:
        # 혹시 글롭 패턴일 경우
        files_to_read = sorted(glob.glob(expanded_path))

    for filepath in files_to_read:
        try:
            with open(filepath, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        record = json.loads(line)
                        records.append(record)
                    except json.JSONDecodeError:
                        continue
        except OSError as e:
            print(f"경고: 파일 읽기 실패 ({filepath}) - {e}")

    return records


def main():
    parser = argparse.ArgumentParser(description="JSONL 평가 결과 및 실사용 기록을 정적 HTML 대시보드로 변환합니다.")
    parser.add_argument(
        "--input", "-i",
        nargs="*",
        default=None,
        help="입력 JSONL 파일 또는 디렉터리 경로 (미지정 시 Application Support runs 및 Evals/results 자동 로드)"
    )
    parser.add_argument("--output", "-o", type=str, default="eval-report.html", help="출력 HTML 파일 경로")
    args = parser.parse_args()

    records = []
    if args.input:
        for p in args.input:
            records.extend(load_records_from_path(p))
    else:
        here = os.path.dirname(os.path.abspath(__file__))
        default_paths = [
            os.path.expanduser("~/Library/Application Support/HorongHorong/runs"),
            os.path.expanduser("~/Library/Application Support/HorongHorong-Debug/runs"),
            os.path.join(here, "results"),
        ]
        for p in default_paths:
            if os.path.exists(p):
                records.extend(load_records_from_path(p))

    data_by_level = defaultdict(dict)
    data_by_model = defaultdict(dict)
    live_runs = defaultdict(dict)

    for row in records:
        case_id = row.get("case_id")
        source = row.get("source")

        # 실사용(Live) 기록 판별: case_id가 없거나 source가 "live"
        if not case_id or source == "live":
            run_id = row.get("run_id") or "UNKNOWN_RUN"
            task = row.get("task") or "weekly_goal"
            run_key = f"{run_id} ({task})"
            attempt = row.get("attempt", 1)
            live_runs[run_key][attempt] = row
        else:
            # 골든셋/평가 레코드
            level = row.get("recipe", row.get("level", "promptOnly"))
            model = row.get("model", "unknown")

            data_by_level[case_id][level] = row
            if model:
                data_by_model[case_id][model] = row

    html = generate_html(data_by_level, data_by_model, live_runs)

    with open(args.output, "w", encoding="utf-8") as f:
        f.write(html)

    print(f"✅ HTML 대시보드 생성 완료: {os.path.abspath(args.output)}")
    print(f"터미널에서 'open {args.output}' 명령어를 실행하여 브라우저에서 확인하세요.")


if __name__ == "__main__":
    main()
