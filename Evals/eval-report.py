#!/usr/bin/env python3
"""JSONL 평가 결과 및 실사용(Live) 기록을 읽어 사람이 읽기 쉬운 정적 HTML 대시보드로 변환한다."""

import argparse
import json
import os
import glob
import re
from collections import Counter, defaultdict
from datetime import datetime

def load_golden_notes():
    """케이스 설명(note)의 원본은 골든셋 JSON 이다.

    기록(JSONL)에는 담지 않는다 — 실행마다 같은 문장을 되풀이해 저장할 이유가 없고,
    문구를 고치면 옛 기록과 어긋난다. 보여줄 때 여기서 읽는다.

    `datasetType` 과 «함정이 달렸나» 도 같이 읽는다. 지표마다 **분모가 다르기** 때문이다
    (→ `column_summary`).
    """
    notes = {}
    meta = {}
    here = os.path.dirname(os.path.abspath(__file__))
    for folder in ("golden/cases", "golden/drafts"):
        directory = os.path.join(here, folder)
        if not os.path.isdir(directory):
            continue
        # 하위 폴더까지 훑는다. 케이스가 주기(weekly/monthly)와 페르소나로 갈려 있어
        # 한 겹만 읽으면 전부 놓치고 설명이 통째로 비어 버린다.
        for root, _, names in os.walk(directory):
            for name in sorted(names):
                if not name.endswith(".json"):
                    continue
                try:
                    with open(os.path.join(root, name), encoding="utf-8") as f:
                        case = json.load(f)
                    notes[case.get("caseName", "")] = case.get("note") or ""
                    meta[case.get("caseName", "")] = {
                        "datasetType": case.get("datasetType"),
                        "hasTraps": bool(case.get("traps")),
                    }
                except (OSError, ValueError):
                    continue
    return notes, meta


GOLDEN_NOTES, GOLDEN_META = load_golden_notes()

# 묶음 점수를 매길 수 있는 유형. 나머지 둘(`insufficient_information`,
# `non_goal_or_noise`)은 정답이 «묶지 마라» 라서 `expectedGroups` 가 비어 있고,
# 쌍 단위 채점자로는 무엇을 내든 0 이 나온다. 평균에 섞으면 «못한다» 로 읽히지만
# 실제로는 **그 자로 잴 수 없는 것**이다.
GROUPABLE_TYPES = {"general", "context_dependent"}


METRIC_DESC = {
    "honorific": "존댓말 비율",
    "sentenceCount": "문장 수 제한",
    "groundedness": "사실 기반",
    "pairF1": "쌍 단위 F1 — 함정 감점 전",
    "trapAvoidance": "함정 회피율 — 함정을 적어둔 케이스에만 뜬다",
    "groupingScore": "목표 연결 점수 = F1 × 함정 회피 (최종)",
    "guidanceF1": "안내 대상 일치도 — 정보가 부족한 입력에만 표시",
    "noSuggestionCorrect": "비목표 처리 판정 — 침묵 또는 전체 안내",
    "predictedGroups": "추천 목표 개수",
}

METRIC_SHORT = {
    "honorific": "존대",
    "sentenceCount": "문장",
    "groundedness": "사실",
    "pairF1": "F1",
    "trapAvoidance": "함정회피",
    "groupingScore": "목표 연결",
    "guidanceF1": "안내",
    "noSuggestionCorrect": "보류",
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
    <title>{report_title}</title>
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
            --accent: #405f8e;
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
                --accent: #7ea2d5;
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
            margin: 0; padding: 20px 20px 48px;
            background: var(--bg); color: var(--ink);
            -webkit-font-smoothing: antialiased;
        }
        .report-head { margin-bottom: 14px; }
        .report-eyebrow { font-size: 11px; color: var(--faint); margin-bottom: 8px; }
        h1 { font-size: 26px; margin: 0 0 10px; letter-spacing: -0.025em; }
        .report-meta {
            display: flex; flex-wrap: wrap; gap: 5px 18px;
            font-family: monospace; font-size: 11px; color: var(--muted);
        }
        .report-meta b { color: var(--ink); font-weight: 700; }

        /* 탭 */
        .tabs { display: flex; gap: 2px; border-bottom: 1px solid var(--line); margin-bottom: 20px; }
        .tab-button {
            background: none; border: none; padding: 9px 14px; font-size: 13px; font-weight: 500;
            color: var(--muted); cursor: pointer; border-bottom: 2px solid transparent; margin-bottom: -1px;
            font-family: inherit;
        }
        .tab-button:hover { color: var(--ink); }
        .tab-button.active { color: var(--ink); border-bottom-color: var(--accent); }
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
        .comparison-picker { display: flex; align-items: center; gap: 8px; margin: 0 0 10px; font-size: 12px; color: var(--muted); }
        .comparison-picker select { border: 1px solid var(--line); border-radius: 6px; background: var(--panel); color: var(--ink); padding: 5px 8px; font: inherit; }
        .column-pager { display: inline-flex; align-items: center; gap: 6px; font-size: 12px; color: var(--muted); }
        .column-pager button { border: 1px solid var(--line); border-radius: 6px; background: var(--panel); color: var(--ink); padding: 4px 9px; cursor: pointer; font: inherit; }
        .column-pager button:disabled { cursor: default; opacity: 0.45; }
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
        thead th .col-agg .denom { color: var(--faint); font-weight: 400; margin-left: 1px; }
        thead th .col-agg { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 2px 6px; font-size: 11px; color: var(--muted); font-weight: 400; margin-top: 5px; white-space: normal; }
        thead th .col-agg .metric { white-space: nowrap; }
        thead th .col-agg .latency { grid-column: 1 / -1; }
        thead th .model-provider { display: block; font-size: 11px; color: var(--muted); font-weight: 600; margin-bottom: 2px; }
        thead th .model-name { display: block; font-size: 13px; color: var(--ink); }

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

        /* ── 유형별 채점(능력 격자·실행 상세·용어) ───────────────── */
        .cap-panel {
            background: var(--panel); border: 1px solid var(--line); border-radius: 8px;
            overflow: hidden; margin-bottom: 16px;
        }
        .cap-head {
            display: flex; flex-wrap: wrap; align-items: baseline; gap: 4px 14px;
            padding: 11px 16px; border-bottom: 1px solid var(--line); background: var(--panel-alt);
        }
        .cap-head h2 { margin: 0; font-size: 14px; }
        .cap-scope { font-family: monospace; font-size: 11px; color: var(--muted); }
        .cap-body { padding: 14px 16px; }
        .cap-def { margin: 12px 0 0; color: var(--muted); font-size: 12.5px; max-width: 80ch; line-height: 1.6; }
        .cap-wrap { overflow-x: auto; }
        .cap-table { border-collapse: collapse; width: 100%; font-variant-numeric: tabular-nums; }
        .cap-table th, .cap-table td { text-align: right; padding: 7px 10px; white-space: nowrap; }
        .cap-table th {
            font-family: monospace; font-size: 10.5px; font-weight: 700; color: var(--muted);
            vertical-align: bottom; border-bottom: 1px solid var(--line);
        }
        .cap-table th.cap-group {
            text-align: center; color: var(--ink); background: var(--bubble);
            font-size: 11px; letter-spacing: .02em;
        }
        .cap-table thead tr:first-child th { padding-top: 8px; padding-bottom: 6px; }
        .cap-table thead tr:nth-child(2) th { padding-top: 6px; }
        .cap-table th span { display: block; font-weight: 400; color: var(--faint); font-size: 10px; }
        .cap-table th:first-child, .cap-table td:first-child { text-align: left; }
        .cap-table thead tr:nth-child(2) th:first-child { text-align: right; }
        .cap-table td { border-bottom: 1px solid var(--panel-alt); font-size: 12.5px; }
        .cap-table tfoot td {
            border-bottom: 0; border-top: 1px solid var(--line);
            font-family: monospace; font-size: 10.5px; color: var(--faint);
        }
        .cap-name { font-family: monospace; font-size: 12px; }
        .cap-cell { font-family: monospace; font-weight: 700; border-radius: 3px; }
        .cap-split { border-left: 1px solid var(--line); }
        .cap-grouphead td {
            background: var(--panel-alt); font-family: monospace; font-size: 10.5px;
            color: var(--muted); border-bottom: 1px solid var(--line);
        }
        .cap-caseid { font-size: 12px; max-width: 340px; overflow: hidden; text-overflow: ellipsis; }

        .cap-ctxrow { display: grid; grid-template-columns: 150px 1fr 82px; align-items: center; gap: 12px; padding: 5px 0; }
        .cap-bar { display: flex; height: 15px; border-radius: 3px; overflow: hidden; gap: 2px; }
        .cap-up { background: var(--pass-fg); }
        /* 발산형 막대의 중립 구간. `--bubble` 은 패널 배경과 거의 같아 막대가 끊겨 보인다. */
        .cap-flat { background: var(--faint); opacity: .55; }
        .cap-down { background: var(--fail-fg); }
        .cap-delta { font-family: monospace; font-size: 12px; text-align: right; }
        .cap-legend { display: flex; flex-wrap: wrap; gap: 14px; font-family: monospace; font-size: 11px; color: var(--muted); padding-bottom: 10px; }
        .cap-legend i { display: inline-block; width: 10px; height: 10px; border-radius: 2px; margin-right: 5px; vertical-align: -1px; }

        .cap-ctl { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; padding-bottom: 12px; font-family: monospace; font-size: 11px; }
        .cap-ctl label { color: var(--muted); }
        .cap-ctl select {
            font-family: monospace; font-size: 11px; padding: 3px 6px; max-width: 100%;
            background: var(--panel); color: var(--ink); border: 1px solid var(--line); border-radius: 4px;
        }
        .cap-meta { display: flex; flex-wrap: wrap; gap: 5px 14px; font-family: monospace; font-size: 11px; color: var(--muted); padding-bottom: 10px; }
        .cap-meta b { color: var(--ink); font-weight: 700; }
        .cap-pill { display: inline-block; font-family: monospace; font-size: 10px; padding: 1px 7px; border-radius: 9px; border: 1px solid var(--line); color: var(--muted); }
        .cap-final { border: 1px solid var(--line); border-radius: 6px; padding: 10px 12px; margin-bottom: 14px; }
        .cap-final .lab { display: flex; align-items: center; gap: 8px; font-family: monospace; font-size: 10px; letter-spacing: .1em; text-transform: uppercase; color: var(--faint); margin-bottom: 7px; }
        .cap-final pre { margin: 0; font-family: monospace; font-size: 12.5px; line-height: 1.6; color: var(--ink); white-space: pre-wrap; word-break: break-word; }
        .cap-step { border-top: 1px solid var(--panel-alt); }
        .cap-step:first-child { border-top: 0; }
        .cap-step > summary { cursor: pointer; padding: 8px 2px; display: grid; grid-template-columns: 13px 106px 70px 1fr; gap: 10px; align-items: baseline; font-family: monospace; font-size: 11.5px; }
        .cap-step > summary::-webkit-details-marker { display: none; }
        /* 기본 삼각형을 지웠으니 펼칠 수 있다는 표시를 직접 세운다. */
        .cap-step > summary::before { content: "▸"; color: var(--faint); }
        .cap-step[open] > summary::before { content: "▾"; }
        .cap-step > summary:hover { color: var(--accent); }
        .cap-step .sms { color: var(--faint); text-align: right; }
        .cap-step .sfacts { color: var(--muted); font-size: 10.5px; white-space: normal; }
        .cap-step pre {
            margin: 0 0 12px; padding: 11px; background: var(--bubble); border-radius: 4px;
            font-family: monospace; font-size: 11px; line-height: 1.55; white-space: pre-wrap;
            word-break: break-word; color: var(--muted); max-height: 340px; overflow: auto;
        }
        .cap-gloss { margin: 0; display: grid; grid-template-columns: minmax(148px, auto) 1fr; gap: 8px 18px; align-items: baseline; }
        .cap-gloss dt { font-family: monospace; font-size: 12px; color: var(--ink); }
        .cap-gloss dd { margin: 0; color: var(--muted); font-size: 12.5px; line-height: 1.6; }
        .cap-gloss dd em { font-style: normal; font-family: monospace; font-size: 11px; color: var(--faint); display: block; }
        .cap-rules { margin: 0; padding-left: 18px; color: var(--muted); font-size: 12.5px; display: flex; flex-direction: column; gap: 6px; max-width: 80ch; line-height: 1.6; }
        @media (max-width: 640px) {
            .cap-gloss { grid-template-columns: 1fr; gap: 3px 0; }
            .cap-gloss dd { padding-bottom: 8px; }
            .cap-step > summary { grid-template-columns: 13px 90px 60px; }
            .cap-step .sfacts { grid-column: 1 / -1; }
            .cap-ctxrow { grid-template-columns: 110px 1fr 70px; }
        }
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

        function selectComparison(prefix, selectedId) {
            document.querySelectorAll(`[id^="${prefix}-"]`).forEach(el => {
                el.style.display = el.id === selectedId ? '' : 'none';
            });
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

        function filterLiveRows(button, tableId, group, mode) {
            button.parentElement.querySelectorAll('button').forEach(el => el.classList.remove('active'));
            button.classList.add('active');
            const table = document.getElementById(tableId);
            table.dataset[group] = mode;
            const origin = table.dataset.origin || 'all';
            const status = table.dataset.status || 'all';
            table.querySelectorAll('tbody tr').forEach(tr => {
                const originMatch = origin === 'all' || tr.dataset.origin === origin;
                const statusMatch = status === 'all'
                    || (status === 'fail' && tr.dataset.fail === '1')
                    || (status === 'ok' && tr.dataset.fail !== '1');
                tr.style.display = originMatch && statusMatch ? '' : 'none';
            });
        }

        function showColumnPage(tableId, page, pageSize, totalColumns) {
            const pageCount = Math.ceil(totalColumns / pageSize);
            const safePage = Math.max(0, Math.min(page, pageCount - 1));
            const first = safePage * pageSize;
            const last = first + pageSize;
            document.querySelectorAll(`#${tableId} [data-column-index]`).forEach(el => {
                const index = Number(el.dataset.columnIndex);
                el.style.display = index >= first && index < last ? '' : 'none';
            });
            const pager = document.querySelector(`[data-pager-for="${tableId}"]`);
            if (!pager) return;
            pager.dataset.page = safePage;
            pager.querySelector('[data-page-label]').textContent = `${safePage + 1} / ${pageCount}`;
            pager.querySelector('[data-page-prev]').disabled = safePage === 0;
            pager.querySelector('[data-page-next]').disabled = safePage >= pageCount - 1;
        }

        function moveColumnPage(tableId, delta, pageSize, totalColumns) {
            const pager = document.querySelector(`[data-pager-for="${tableId}"]`);
            showColumnPage(tableId, Number(pager.dataset.page || 0) + delta, pageSize, totalColumns);
        }

        /* ── 유형별 채점 탭 ─────────────────────────────── */
        const CAP = {cap_payload};
        const capEsc = s => String(s).replace(/[&<>]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));
        const capF2 = v => (v === null || v === undefined) ? '' : Number(v).toFixed(2);
        const capVar = n => getComputedStyle(document.documentElement).getPropertyValue(n).trim();

        /* 열 안의 상대 농도 — 한 색상 sequential. reverse 열은 낮을수록 진하다. */
        function capPaint(td, v, lo, hi, reverse) {
            let t = (hi === lo) ? 0.5 : (v - lo) / (hi - lo);
            if (reverse) t = 1 - t;
            const pct = Math.round(12 + Math.max(0, Math.min(1, t)) * 74);
            td.style.background = `color-mix(in oklab, ${capVar('--accent')} ${pct}%, ${capVar('--panel')})`;
            td.style.color = pct > 55 ? capVar('--panel') : capVar('--ink');
        }
        function capRange(vals) { return [Math.min(...vals), Math.max(...vals)]; }

        function capGrid(tableId, cols, rows, getter, labels) {
            const table = document.getElementById(tableId);
            if (!table) return;
            const tb = table.querySelector('tbody'), tf = table.querySelector('tfoot');
            tb.innerHTML = '';
            const rg = cols.map(c => capRange(rows.map(r => getter(r, c.key))));
            rows.forEach(r => {
                const tr = document.createElement('tr');
                tr.innerHTML = `<td class="cap-name">${capEsc(r.model)}</td>`;
                cols.forEach((c, i) => {
                    const v = getter(r, c.key);
                    const td = document.createElement('td');
                    td.className = 'cap-cell' + (c.split ? ' cap-split' : '');
                    capPaint(td, v, rg[i][0], rg[i][1], c.reverse);
                    td.textContent = c.integer ? String(v) : capF2(v);
                    td.title = `${r.model} · ${c.key} = ${Number(v).toFixed(3)}` + (c.n ? ` (${c.n}건)` : '');
                    tr.appendChild(td);
                });
                if (labels && labels.tail) {
                    const td = document.createElement('td');
                    td.className = 'cap-split';
                    td.style.fontFamily = 'monospace';
                    td.style.color = capVar('--muted');
                    td.textContent = labels.tail(r);
                    tr.appendChild(td);
                }
                tb.appendChild(tr);
            });
            if (tf) {
                const best = cols.map((c, i) => {
                    const target = c.reverse ? rg[i][0] : rg[i][1];
                    return rows.find(r => getter(r, c.key) === target).model;
                });
                tf.innerHTML = '<tr><td>열 최고</td>' +
                    cols.map((c, i) => `<td class="${c.split ? 'cap-split' : ''}">${capEsc(best[i])}</td>`).join('') +
                    ((labels && labels.tail) ? '<td class="cap-split"></td>' : '') + '</tr>';
            }
        }

        function capRenderAggregate() {
            if (!CAP || !CAP.models || !CAP.models.length) return;
            capGrid('cap-grid',
                [{key:'grouping', n:CAP.counts.grouping}, {key:'trap', n:CAP.counts.grouping},
                 {key:'inventedPairs', n:CAP.counts.inventedPairs, reverse:true, integer:true},
                 {key:'guidance', n:CAP.counts.guidance, split:true},
                 {key:'guidanceTP', n:CAP.counts.guidance},
                 {key:'guidanceFP', n:CAP.counts.guidance},
                 {key:'guidanceFN', n:CAP.counts.guidance},
                 {key:'refusal', n:CAP.counts.refusal, split:true},
                 {key:'restraint', n:CAP.counts.restraint}],
                CAP.models, (r, k) => r[k], {tail: r => r.ms.toFixed(1)});
            capGrid('cap-bytype',
                [{key:'general'}, {key:'context_dependent'},
                 {key:'insufficient_information', split:true}, {key:'non_goal_or_noise'}],
                CAP.models, (r, k) => r.byType[k], null);

            const box = document.getElementById('cap-ctx');
            if (box) {
                box.innerHTML = '';
                CAP.models.forEach(d => {
                    const c = d.ctx, n = Math.max(1, c.up + c.flat + c.down);
                    const row = document.createElement('div');
                    row.className = 'cap-ctxrow';
                    row.innerHTML = `<span class="cap-name">${capEsc(d.model)}</span>
                        <span class="cap-bar">
                          <span class="cap-up" style="width:${c.up / n * 100}%" title="개선 ${c.up}쌍"></span>
                          <span class="cap-flat" style="width:${c.flat / n * 100}%" title="무변 ${c.flat}쌍"></span>
                          <span class="cap-down" style="width:${c.down / n * 100}%" title="악화 ${c.down}쌍"></span>
                        </span>
                        <span class="cap-delta" style="color:${c.mean >= 0 ? capVar('--pass-fg') : capVar('--fail-fg')}">${c.mean >= 0 ? '+' : '−'}${Math.abs(c.mean).toFixed(3)}</span>`;
                    box.appendChild(row);
                });
            }

            const ft = document.querySelector('#cap-fmt tbody');
            if (ft) {
                const keys = ['modelReturned','kept','badID','tooFewIDs','alreadyUsed','overMaxMemo'];
                ft.innerHTML = CAP.models.map(d =>
                    `<tr><td class="cap-name">${capEsc(d.model)}</td>` + keys.map((k, i) =>
                        `<td class="${i === 2 ? 'cap-split' : ''}" style="font-family:monospace;color:${d.fmt[k] === 0 ? capVar('--faint') : capVar('--ink')}">${d.fmt[k]}</td>`
                    ).join('') + '</tr>').join('');
            }

            const mt = document.querySelector('#cap-missing tbody');
            if (mt) {
                mt.innerHTML = CAP.models.map(d =>
                    `<tr><td class="cap-name">${capEsc(d.model)}</td>` +
                    `<td>${d.missingTP}</td><td>${d.missingFP}</td><td>${d.missingFN}</td>` +
                    `<td>${capF2(d.missingF1)}</td></tr>`
                ).join('');
            }

            const judge = CAP.judge || {};
            const jmeta = document.getElementById('cap-judge-meta');
            const jtable = document.querySelector('#cap-judge tbody');
            const jempty = document.getElementById('cap-judge-empty');
            if (jmeta) {
                const m = judge.meta;
                jmeta.textContent = m
                    ? `평가자 ${m.judge} · 기록 모델 라벨 ${m.judgeModel} · ${m.rubricVersion} · 채점 ${m.count}건`
                      + (m.errors ? ` · judge 실패 ${m.errors}건` : '')
                      + ` · 파일 ${m.files.length}개`
                    : '성공한 LLM judge 결과가 없습니다.';
                if (m) jmeta.title = m.files.join('\\n');
            }
            if (jtable) {
                const labels = {
                    semantic_cohesion:'응집성', noise_exclusion:'노이즈 배제', measurability:'측정 가능성',
                    clarity:'명확성', time_fit:'기간 적합성', relevance:'관련성', guidance_fit:'안내 적합성',
                    guidance_actionability:'안내 실행성', grammar:'문법', vocabulary:'어휘', tone:'어투'
                };
                const metrics = judge.metrics || [];
                jtable.innerHTML = (judge.models || []).map(d =>
                    `<tr><td class="cap-name">${capEsc(d.model)}</td>` +
                    metrics.map(k => `<td class="cap-cell">${d.judge[k] == null ? '—' : capF2(d.judge[k])}</td>`).join('') +
                    `<td class="cap-muted">${d.judgeCount}건</td></tr>`
                ).join('');
                if (jempty) jempty.hidden = Boolean((judge.models || []).length);
                const head = document.querySelector('#cap-judge thead tr');
                if (head) head.innerHTML = '<th>모델</th>' + metrics.map(k => `<th>${labels[k] || k}<span>${k}</span></th>`).join('') + '<th>건수</th>';
            }
        }

        function capRenderCases() {
            const table = document.getElementById('cap-cases');
            if (!table || !CAP.cases) return;
            const recipe = document.getElementById('cap-f-recipe').value;
            const task = document.getElementById('cap-f-task').value;
            const type = document.getElementById('cap-f-type').value;
            table.querySelector('thead').innerHTML =
                '<tr><th>케이스</th>' + CAP.modelKeys.map(m => `<th>${capEsc(m)}</th>`).join('') + '</tr>';
            const tb = table.querySelector('tbody');
            tb.innerHTML = '';
            let group = null;
            CAP.cases.forEach(c => {
                if (task && c.task !== task) return;
                if (type && c.type !== type) return;
                const g = `${c.task} · ${c.type}`;
                if (g !== group) {
                    group = g;
                    const tr = document.createElement('tr');
                    tr.className = 'cap-grouphead';
                    tr.innerHTML = `<td colspan="${CAP.modelKeys.length + 1}">${capEsc(g)} — 주력 지표 ${capEsc(CAP.primary[c.type] || '-')}</td>`;
                    tb.appendChild(tr);
                }
                const tr = document.createElement('tr');
                tr.innerHTML = `<td class="cap-caseid" title="${capEsc(c.name)}">${capEsc(c.name)}</td>`;
                CAP.modelKeys.forEach(m => {
                    const cell = CAP.cells[`${c.name}|${m}|${recipe}`];
                    const td = document.createElement('td');
                    td.className = 'cap-cell';
                    if (cell && cell.v !== null && cell.v !== undefined) {
                        capPaint(td, cell.v, 0, 1);
                        td.textContent = capF2(cell.v);
                        td.title = `${m} · ${CAP.primary[c.type]} = ${Number(cell.v).toFixed(3)} · outcome ${cell.o} · ${(cell.ms / 1000).toFixed(1)}s`;
                    } else {
                        td.title = cell ? `${m} · outcome ${cell.o} · ${(cell.ms / 1000).toFixed(1)}s` : '기록 없음';
                    }
                    tr.appendChild(td);
                });
                tb.appendChild(tr);
            });
        }

        function capRenderDetail(i) {
            const s = CAP.runs[i];
            if (!s) return;
            document.getElementById('cap-runmeta').innerHTML =
                [['runId', s.runId], ['model', s.model], ['task', s.task], ['recipe', s.recipe],
                 ['outcome', s.outcome], ['총 소요', (s.totalMs / 1000).toFixed(1) + 's']]
                .map(([k, v]) => `<span>${k} <b>${capEsc(v)}</b></span>`).join('') +
                Object.entries(s.scores || {}).map(([k, v]) => `<span class="cap-pill">${capEsc(k)} ${Number(v).toFixed(2)}</span>`).join(' ');
            const out = (s.output || '').trim();
            document.getElementById('cap-final').innerHTML =
                `<span class="lab">최종 출력 <span class="cap-pill">RunRecord.output</span></span>
                 <pre>${out ? capEsc(out) : '(비어 있음 — 살아남은 제안이 없습니다)'}</pre>`;
            document.getElementById('cap-steps').innerHTML = (s.steps || []).map(st => {
                const body = (st.text || '').length
                    ? capEsc(st.text) + (st.cut ? `\n\n… ${st.full.toLocaleString()}자 중 앞 ${st.text.length.toLocaleString()}자만 표시` : '')
                    : '(이 단계에 남은 원문이 없습니다)';
                const facts = st.facts ? capEsc(Object.entries(st.facts).map(([k, v]) => k + '=' + v).join('  ')) : '';
                return `<details class="cap-step">
                    <summary><span>${capEsc(st.name)}</span><span class="sms">${st.ms} ms</span><span class="sfacts">${facts}</span></summary>
                    <pre>${body}</pre>
                </details>`;
            }).join('');
        }

        function capInit() {
            if (!CAP || !CAP.models) return;
            capRenderAggregate();
            if (CAP.cases && CAP.cases.length) {
                ['cap-f-recipe', 'cap-f-task', 'cap-f-type'].forEach(id => {
                    const el = document.getElementById(id);
                    if (el) el.addEventListener('change', capRenderCases);
                });
                capRenderCases();
            }
            const sel = document.getElementById('cap-f-run');
            if (sel && CAP.runs && CAP.runs.length) {
                sel.addEventListener('change', () => capRenderDetail(Number(sel.value)));
                capRenderDetail(0);
            }
        }
        window.addEventListener('DOMContentLoaded', capInit);
        matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
            capRenderAggregate();
            if (CAP.cases && CAP.cases.length) capRenderCases();
        });
    </script>
</head>
<body>
    <header class="report-head">
        <div class="report-eyebrow">{report_eyebrow}</div>
        <h1>{report_title}</h1>
        <div class="report-meta">{report_meta}</div>
    </header>
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


def visible_scores(case_id, scores):
    """이 케이스에 **의미가 있는** 지표만 남긴다.

    함정을 안 적은 케이스의 `trapAvoidance` 는 «잘 피했다» 가 아니라 **잴 것이 없었다** 는
    뜻이라 1.0 으로 찍힌다. 그걸 그대로 보여주면 만점 배지가 붙어 잘한 것처럼 읽히고,
    평균·경고·색칠까지 전부 끌어올린다. 없는 시험은 만점이 아니라 **무응시**다.
    """
    meta = GOLDEN_META.get(case_id, {})
    result = scores
    if meta.get("datasetType") not in GROUPABLE_TYPES and "datasetType" in meta:
        # 이 유형의 정답은 '묶기'가 아니다. 구조적으로 0이 되는 묶음 점수를 보여주면
        # 모델이 틀린 것이 아니라 자가 다른 것을 실패처럼 보이게 만든다.
        result = {k: v for k, v in result.items() if k not in {"pairF1", "groupingScore", "trapAvoidance"}}
    elif not meta.get("hasTraps", True):
        result = {k: v for k, v in result.items() if k != "trapAvoidance"}
    return result


def is_warning(case_id, case_data):
    """케이스 안에 0.5 미만 점수가 하나라도 있으면 '주의'."""
    for result in case_data.values():
        if is_infrastructure_failure(result):
            return True
        for value in visible_scores(case_id, result.get("scores", {})).values():
            if isinstance(value, (int, float)) and value < 0.5:
                return True
    return False


def worst_class(case_id, case_data):
    if any(is_infrastructure_failure(result) for result in case_data.values()):
        return "fail"
    values = [
        v
        for result in case_data.values()
        for v in visible_scores(case_id, result.get("scores", {})).values()
        if isinstance(v, (int, float))
    ]
    return score_class(min(values)) if values else "pass"


def is_infrastructure_failure(result):
    """모델 품질과 무관하게 추론이 시작되지 않았거나 중단된 실행인가."""
    return result.get("outcome") in {"generationFailed", "serverUnavailable", "modelUnavailable"}


def format_seconds(ms):
    if ms is None:
        return "-"
    sec = ms / 1000.0
    if sec >= 10:
        return f"{sec:.1f}s"
    else:
        return f"{sec:.2f}s"


def column_summary(data_dict, column):
    """열 머리에 붙는 요약: **지표별** 평균과 평균 지연.

    지표를 한 통에 붓고 평균내면 안 된다. 세 가지가 동시에 틀린다.

    - `groupingScore = pairF1 × trapAvoidance` 라 **셋은 독립이 아니다.**
      곱한 값과 그 부품을 같이 평균내면 같은 정보를 세 번 센다
    - `trapAvoidance` 는 함정을 안 적은 케이스에서 **자동으로 1.0** 이다.
      전 케이스로 평균내면 «함정을 적게 적을수록 점수가 오른다» (실측 0.935 vs 0.778)
    - `groupingScore` 는 정답이 «묶지 마라» 인 케이스에서 구조적으로 0 이다.
      섞으면 모델 탓으로 읽힌다 (실측 31개 0.408 vs 묶음 가능 22개 0.574)

    그래서 **지표마다 분모를 따로 고른다.** 괄호 안 숫자가 그 분모다.
    """
    pairs = [
        (case_id, case_data[column])
        for case_id, case_data in data_dict.items()
        if column in case_data and not is_infrastructure_failure(case_data[column])
    ]
    if not pairs:
        return "데이터 없음"

    def average(key, keep):
        picked = [
            row["scores"][key]
            for case_id, row in pairs
            if isinstance(row.get("scores", {}).get(key), (int, float)) and keep(GOLDEN_META.get(case_id, {}))
        ]
        return (sum(picked) / len(picked), len(picked)) if picked else None

    # 골든셋에 없는 케이스(옛 기록 등)는 유형을 모른다. 빼면 통째로 사라지므로 남긴다.
    groupable = lambda m: m.get("datasetType") in GROUPABLE_TYPES or "datasetType" not in m
    parts = []
    for key, label, keep in (
        ("groupingScore", "묶음", groupable),
        ("pairF1", "F1", groupable),
        ("trapAvoidance", "함정회피", lambda m: m.get("hasTraps", True)),
        ("guidanceF1", "안내", lambda m: m.get("datasetType") == "insufficient_information"),
        ("noSuggestionCorrect", "보류", lambda m: m.get("datasetType") == "non_goal_or_noise"),
    ):
        got = average(key, keep)
        if got:
            parts.append(f"<span class='metric'>{label} {got[0]:.2f}<span class='denom'>({got[1]})</span></span>")

    if not parts:  # 옛 기록의 대화용 지표만 있는 경우 — 전부 평균내던 옛 동작으로 물러선다
        scores = [v for _, row in pairs for v in row.get("scores", {}).values() if isinstance(v, (int, float))]
        if scores:
            parts.append(f"<span class='metric'>평균 {sum(scores) / len(scores):.2f}</span>")

    avg_latency = sum(r.get("total_ms", r.get("latency_ms", 0)) for _, r in pairs) // len(pairs)
    return "".join(parts + [f"<span class='latency'>⏱ {format_seconds(avg_latency)}</span>"])


def model_label(model_key):
    """저장용 공급자·모델 키를 사람이 읽는 두 줄 레이블로 바꾼다."""
    provider, _, model = model_key.partition("|")
    provider_name = {
        "appleFoundation": "Apple Foundation Models",
        "ollama": "Ollama",
        "mlx": "MLX",
    }.get(provider, provider or "Unknown")
    short_model = model.removeprefix("mlx-community/")
    if not short_model or short_model == provider:
        short_model = "기본 모델"
    return provider_name, short_model


def display_column_label(column, is_level):
    if is_level:
        return column
    provider, model = model_label(column)
    return f"<span class='model-provider'>{provider}</span><span class='model-name'>{model}</span>"


def render_table(data_dict, table_id, is_level=True, page_size=None):
    columns = set()
    for case_data in data_dict.values():
        columns.update(case_data.keys())
    sorted_cols = sorted(columns)

    headers = ""
    for index, col in enumerate(sorted_cols):
        desc = ""
        if is_level:
            base_lvl = col.split(" ")[0]
            if base_lvl in LEVEL_DESC:
                desc = f"<span class='lvl-desc'>{LEVEL_DESC[base_lvl]}</span>"
        headers += (
            f"<th{' data-column-index=' + repr(index) if page_size else ''}>{display_column_label(col, is_level)}{desc}"
            f"<span class='col-agg'>{column_summary(data_dict, col)}</span></th>"
        )

    rows = []
    warning_count = 0
    for case_id, case_data in sorted(data_dict.items()):
        warn = is_warning(case_id, case_data)
        warning_count += 1 if warn else 0

        # 케이스 설명은 기록이 아니라 골든셋 JSON 이 원본이다(중복 저장하지 않는다).
        input_text = GOLDEN_NOTES.get(case_id, "")

        question = f"<div class='case-q'>{input_text}</div>" if input_text else ""
        dataset_type = GOLDEN_META.get(case_id, {}).get("datasetType")
        type_text = f"<span class='case-q'>{dataset_type}</span>" if dataset_type else ""
        row = [
            f"<td class='case-col'>"
            f"<div class='case-id'><span class='dot {worst_class(case_id, case_data)}'></span>{case_id}</div>"
            f"{type_text}{question}</td>"
        ]

        for index, col in enumerate(sorted_cols):
            column_attr = f" data-column-index='{index}'" if page_size else ""
            if col in case_data:
                result = case_data[col]
                output = result.get("output", "")
                scores = result.get("scores", {})
                latency = result.get("total_ms", result.get("latency_ms", 0))
                outcome = result.get("outcome", "ok")
                outcome_detail = result.get("outcome_detail")
                if is_infrastructure_failure(result):
                    status, tooltip = get_outcome_info(outcome, outcome_detail)
                    cell_content = "<span class='empty'>추론 미실행</span>"
                    score_html = f"<span class='badge fail' title='{tooltip}'>{status}</span>"
                else:
                    cell_content = output
                    score_html = "".join(format_score(k, v) for k, v in sorted(visible_scores(case_id, scores).items()))
                row.append(
                    f"<td{column_attr}>"
                    f"<div class='cell-content'>{cell_content}</div>"
                    f"<div class='score-row'>{score_html}</div>"
                    f"<div class='meta'>⏱ {format_seconds(latency)}</div>"
                    f"</td>"
                )
            else:
                row.append(f"<td class='empty'{column_attr}>데이터 없음</td>")
        rows.append(f"<tr data-warn='{1 if warn else 0}'>{''.join(row)}</tr>")

    pager = ""
    if page_size and len(sorted_cols) > page_size:
        pager = f"""
        <span class="column-pager" data-pager-for="{table_id}" data-page="0">
            <button data-page-prev onclick="moveColumnPage('{table_id}', -1, {page_size}, {len(sorted_cols)})">← 이전</button>
            <span data-page-label>1 / {(len(sorted_cols) + page_size - 1) // page_size}</span>
            <button data-page-next onclick="moveColumnPage('{table_id}', 1, {page_size}, {len(sorted_cols)})">다음 →</button>
        </span>
        """

    toolbar = f"""
    <div class="toolbar">
        <span class="chip">케이스 <b>{len(data_dict)}</b></span>
        <span class="chip{' is-warn' if warning_count else ''}">주의 <b>{warning_count}</b></span>
        <span class="chip">{'레벨' if is_level else '모델'} <b>{len(sorted_cols)}</b></span>
        {pager}
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
    {f"<script>showColumnPage('{table_id}', 0, {page_size}, {len(sorted_cols)});</script>" if page_size and len(sorted_cols) > page_size else ""}
    """


def comparison_selector(prefix, label, tables):
    """한 비교 축을 고른 뒤, 다른 축의 표만 보인다.

    컨텍스트 비교 표에 서로 다른 모델 기록을 섞거나 모델 비교 표에 서로 다른
    컨텍스트 기록을 섞으면, 같은 열이 서로 다른 조건의 실행이 되어 비교가 무의미해진다.
    """
    options = "".join(
        f"<option value='{prefix}-{index}'>{name}</option>"
        for index, (name, _) in enumerate(tables)
    )
    sections = []
    for index, (_, table) in enumerate(tables):
        hidden = "" if index == 0 else " style='display:none'"
        sections.append(f"<div id='{prefix}-{index}' class='comparison-table'{hidden}>{table}</div>")
    return f"""
    <div class="comparison-picker">
        <label>{label}</label>
        <select onchange="selectComparison('{prefix}', this.value)">{options}</select>
    </div>
    {''.join(sections)}
    """


def get_outcome_info(outcome, detail):
    if outcome == "ok":
        return "성공 (ok)", "목표 초안이 정상적으로 생성 및 파싱되었습니다."
    elif outcome == "generationFailed":
        if detail == "modelUnavailable":
            return "모델 불가 (modelUnavailable)", "사전 점검에서 Ollama 모델 목록에 선택한 모델이 없었습니다. 추론은 시작하지 않았습니다."
        elif detail == "serverUnavailable":
            return "서버 불가 (serverUnavailable)", "사전 점검에서 Ollama 서버에 연결하지 못했습니다. 추론은 시작하지 않았습니다."
        elif detail == "timeout":
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
    origin_counts = Counter()

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
        origin = last_record.get("_report_origin", "other")
        if origin not in {"release", "debug"}:
            origin = "other"
        origin_counts[origin] += 1
        origin_label = {"release": "정식 앱", "debug": "Debug", "other": "기타"}[origin]

        row = [
            f"<td class='case-col'>"
            f"<div class='case-id'><span class='dot {'fail' if is_fail else 'pass'}'></span>{run_id}</div>"
            f"<div class='case-q'><b>{task}</b> <span class='cap-pill'>{origin_label}</span>"
            f"<br><span style='font-size:11px;color:var(--faint);'>{started_at}</span></div>"
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

        rows.append(
            f"<tr data-fail='{1 if is_fail else 0}' data-origin='{origin}'>{''.join(row)}</tr>"
        )

    other_chip = (
        f'<span class="chip">기타 <b>{origin_counts["other"]}</b></span>'
        if origin_counts["other"] else ""
    )

    toolbar = f"""
    <div class="toolbar">
        <span class="chip">총 실행 <b>{total_runs}</b></span>
        <span class="chip">정식 앱 <b>{origin_counts['release']}</b></span>
        <span class="chip">Debug <b>{origin_counts['debug']}</b></span>
        {other_chip}
        <span class="chip is-pass">최종 성공 <b>{success_count}</b></span>
        <span class="chip{' is-fail' if fail_count else ''}">최종 실패 <b>{fail_count}</b></span>
        <span class="chip">최대 폴백 시도 <b>{max_attempts}회</b></span>
        <span class="spacer"></span>
        <span class="filter">
            <button class="active" onclick="filterLiveRows(this, 'table-live', 'origin', 'all')">전체</button>
            <button onclick="filterLiveRows(this, 'table-live', 'origin', 'release')">정식 앱</button>
            <button onclick="filterLiveRows(this, 'table-live', 'origin', 'debug')">Debug</button>
        </span>
        <span class="filter">
            <button class="active" onclick="filterLiveRows(this, 'table-live', 'status', 'all')">전체 상태</button>
            <button onclick="filterLiveRows(this, 'table-live', 'status', 'fail')">실패만</button>
            <button onclick="filterLiveRows(this, 'table-live', 'status', 'ok')">성공만</button>
        </span>
    </div>
    """

    return f"""
    {toolbar}
    <div class="table-wrap">
        <table id="table-live" data-origin="all" data-status="all">
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


# ── 유형별 채점 ──────────────────────────────────────────────
#
# 골든셋은 유형마다 **정답의 성격이 반대**다. `general`·`context_dependent` 는 묶어야
# 정답이고, `insufficient_information` 은 안내를 내야, `non_goal_or_noise` 는 아무것도
# 내지 않아야 정답이다. 그런데 `pairF1` 은 「빈 답이 정답인데 빈 답을 냈다」는 이유로
# 뒤 두 유형에서 1.0 이 된다 — 묶기 능력과 무관한 만점이다. 이걸 한 평균에 넣으면
# **거절을 잘하는 모델이 묶기 점수를 얻는다.** 그래서 유형별로 갈라서 모은다.
#
# 유형 정보는 `RunRecord` 에 없고 케이스 파일에만 있으므로 `case_id`(= `caseName`)로
# 조인한다. 재실행 없이 기존 결과에 소급 적용된다.

PRIMARY_METRIC = {
    "general": "groupingScore",
    "context_dependent": "groupingScore",
    "insufficient_information": "guidanceF1",
    "non_goal_or_noise": "noSuggestionCorrect",
}
TRACE_TEXT_CAP = 6000


def evals_dir():
    return os.path.dirname(os.path.abspath(__file__))


def load_case_specs():
    """골든셋 케이스 파일에서 유형·정답묶음 유무·맥락 내용 유무를 읽는다."""
    specs = {}
    root = os.path.join(evals_dir(), "golden", "cases")
    for path in sorted(glob.glob(os.path.join(root, "**", "*.json"), recursive=True)):
        try:
            with open(path, "r", encoding="utf-8") as f:
                case = json.load(f)
        except (OSError, json.JSONDecodeError):
            continue
        name = case.get("caseName")
        if not name:
            continue
        groups = case.get("expectedGroups") or case.get("expectedGoalGroups") or []
        context = case.get("context") or {}
        specs[name] = {
            "type": case.get("datasetType") or "unknown",
            # 유형이 아니라 **정답 묶음의 실제 유무**로 판단한다. 분류가 어긋난 케이스가
            # 있어도(실측: general 인데 expectedGroups 가 없는 케이스 1건) 집계가 흔들리지 않는다.
            "hasGroups": bool(groups),
            # `context` 키는 있지만 내용이 비면 두 recipe 의 프롬프트가 글자 단위로 같다.
            # 그런 짝은 맥락 효과 비교에서 정보가 0 이므로 제외한다.
            "realCtx": bool(context.get("persona")) or bool(context.get("profile")),
            "task": "monthly_goal" if os.sep + "monthly" + os.sep in path else "weekly_goal",
        }
    return specs


def load_traces():
    """실행별 원문 기록. 없으면 빈 딕셔너리 — 상세 탭만 비고 나머지는 그대로 그린다."""
    traces = {}
    root = os.path.join(evals_dir(), "results", "traces")
    for path in sorted(glob.glob(os.path.join(root, "*.json"))):
        try:
            with open(path, "r", encoding="utf-8") as f:
                trace = json.load(f)
        except (OSError, json.JSONDecodeError):
            continue
        run_id = trace.get("runId")
        if run_id:
            traces[run_id] = trace
    return traces


def load_judges():
    """모든 LLM judge 결과 파일의 성공한 레코드를 합친다.

    judge 실행은 결과 JSONL 하나(=대개 모델 하나)를 대상으로 하므로 파일 하나만
    고르면 나머지 모델이 리포트에서 통째로 빠진다. 실패는 파일이 아니라 레코드의
    status로 거르고, 같은 runId가 여러 파일에 있으면 최신 파일의 결과를 쓴다.
    """
    root = os.path.join(evals_dir(), "results", "judges")
    paths = sorted(glob.glob(os.path.join(root, "*.jsonl")),
                   key=lambda p: os.path.getmtime(p))
    rows, files, judges, judge_models, rubrics, errors = {}, [], set(), set(), set(), 0
    for path in paths:
        used = False
        try:
            with open(path, "r", encoding="utf-8") as f:
                for line in f:
                    if not line.strip():
                        continue
                    try:
                        row = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if not row.get("runId"):
                        continue
                    if row.get("status") != "ok":
                        errors += 1
                        continue
                    rows[row["runId"]] = row
                    used = True
                    judges.add(row.get("judge") or "-")
                    judge_models.add(row.get("judgeModel") or "-")
                    rubrics.add(row.get("rubricVersion") or "-")
        except OSError:
            continue
        if used:
            files.append(os.path.basename(path))
    if not rows:
        return {"rows": {}, "meta": None}
    return {
        "rows": rows,
        "meta": {
            "files": files,
            "judge": ", ".join(sorted(judges)),
            "judgeModel": ", ".join(sorted(judge_models)),
            "rubricVersion": ", ".join(sorted(rubrics)),
            "count": len(rows),
            "errors": errors,
        },
    }


def trace_facts(trace, span_name):
    for span in (trace or {}).get("spans", []):
        if span.get("name") == span_name:
            return span.get("facts") or {}
    return {}


def trace_steps(trace):
    """span 기록에서 단계별 소요와 원문을 뽑는다. 기록 해상도가 초 단위인 구간이 있다."""
    spans = (trace or {}).get("spans", [])
    steps, prev = [], None
    for span in spans:
        stamp = span.get("at") or ""
        try:
            now = datetime.fromisoformat(stamp.replace("Z", "+00:00"))
        except ValueError:
            now = prev
        gap = int((now - prev).total_seconds() * 1000) if (prev and now) else 0
        text = span.get("text") or ""
        steps.append({
            "name": span.get("name"),
            "ms": max(0, gap),
            "facts": span.get("facts"),
            "text": text[:TRACE_TEXT_CAP],
            "full": len(text),
            "cut": len(text) > TRACE_TEXT_CAP,
        })
        prev = now or prev
    return steps


def invented_pair_count(trace):
    """정답 묶음이 없는 실행에서 모델이 반환한 묶음의 모든 쌍 수를 센다."""
    extracted = next(
        (span.get("text") for span in (trace or {}).get("spans", [])
         if span.get("name") == "extractedJSON"),
        "",
    )
    try:
        payload = json.loads(extracted)
    except (TypeError, json.JSONDecodeError):
        return 0

    total = 0
    for suggestion in payload.get("suggestions") or []:
        if not isinstance(suggestion, dict):
            continue
        items = suggestion.get("items") or suggestion.get("memoIDs") or suggestion.get("goalIDs") or []
        if isinstance(items, list):
            total += len(items) * (len(items) - 1) // 2
    return total


def _mean(values):
    return (sum(values) / len(values)) if values else 0.0


def build_capability_payload(records, specs, traces, judges=None, max_detail_runs=1200):
    """능력 격자·유형별 분해·맥락 효과·파싱 진단·케이스 격자·실행 상세를 한 번에 계산한다."""
    golden = [r for r in records
              if r.get("case_id") and r.get("source") != "live" and r.get("case_id") in specs]
    if not golden:
        return None

    # **모델 이름이 아니라 실행 배치로 묶는다.** 같은 모델을 여러 번 돌린 기록이 섞이면
    # (예: 케이스 31개짜리 옛 실행 + 124개짜리 최신 실행) 한 모델이 남들보다 행이 많아져
    # 완주 판정이 무너진다. `run_id` 의 케이스 접미사(`-w12` · `-m3`)를 떼면 배치 하나가 남는다.
    batches = defaultdict(list)
    for row in golden:
        run_id = row.get("run_id") or ""
        batches[(row.get("model") or "unknown", re.sub(r"-[wm]\d+$", "", run_id))].append(row)

    def coverage(rows):
        return frozenset((r.get("case_id"), r.get("recipe")) for r in rows)

    # 가장 많은 (케이스 × recipe)를 덮은 배치를 기준으로 삼고, 그것을 온전히 덮은 배치만 비교한다.
    reference = max((coverage(rows) for rows in batches.values()), key=len, default=frozenset())
    if not reference:
        return None

    by_model = {}
    for (model, _), rows in sorted(batches.items()):
        if coverage(rows) != reference:
            continue
        previous = by_model.get(model)
        # 같은 모델이 여러 번 완주했으면 마지막 실행을 쓴다.
        if previous is None or (rows[0].get("started_at") or "") > (previous[0].get("started_at") or ""):
            by_model[model] = rows
    models = sorted(by_model)
    if not models:
        return None
    full = len(reference)

    def spec(row):
        return specs.get(row.get("case_id")) or {}

    judge_rows = (judges or {}).get("rows", {})
    judge_metric_order = [
        "semantic_cohesion", "noise_exclusion", "measurability", "clarity", "time_fit",
        "relevance", "guidance_fit", "guidance_actionability", "grammar", "vocabulary", "tone",
    ]
    payload_models = []
    for model in models:
        rows = by_model[model]
        grouped = [r for r in rows if spec(r).get("hasGroups")]
        ungrouped = [r for r in rows if not spec(r).get("hasGroups")]

        by_type = {}
        for kind, metric in PRIMARY_METRIC.items():
            picked = [r for r in rows if spec(r).get("type") == kind]
            by_type[kind] = _mean([r.get("scores", {}).get(metric, 0.0) for r in picked])

        pairs = defaultdict(dict)
        for r in rows:
            info = spec(r)
            if info.get("hasGroups") and info.get("realCtx"):
                pairs[r["case_id"]][r.get("recipe")] = r.get("scores", {}).get("groupingScore", 0.0)
        deltas = [v["promptWithContext"] - v["promptOnly"]
                  for v in pairs.values()
                  if "promptWithContext" in v and "promptOnly" in v]

        fmt = Counter()
        for r in rows:
            facts = trace_facts(traces.get(r.get("run_id")), "parsed")
            for key in ("modelReturned", "kept", "badID", "tooFewIDs", "alreadyUsed", "overMaxMemo"):
                fmt[key] += facts.get(key, 0)

        durations = sorted(r.get("total_ms", 0) for r in rows)
        missing_tp = sum(r.get("scores", {}).get("missingTP", 0.0)
                         for r in rows if spec(r).get("type") == "insufficient_information")
        missing_fp = sum(r.get("scores", {}).get("missingFP", 0.0)
                         for r in rows if spec(r).get("type") == "insufficient_information")
        missing_fn = sum(r.get("scores", {}).get("missingFN", 0.0)
                         for r in rows if spec(r).get("type") == "insufficient_information")
        missing_precision = missing_tp / (missing_tp + missing_fp) if missing_tp + missing_fp else 0.0
        missing_recall = missing_tp / (missing_tp + missing_fn) if missing_tp + missing_fn else 0.0
        missing_f1 = (2 * missing_precision * missing_recall / (missing_precision + missing_recall)
                      if missing_precision + missing_recall else 0.0)

        judge_values = defaultdict(list)
        judge_count = 0
        for row in rows:
            judged = judge_rows.get(row.get("run_id"))
            if not judged:
                continue
            summary = (judged.get("evaluation") or {}).get("summary") or {}
            judge_count += 1
            for key, value in summary.items():
                if isinstance(value, (int, float)) and not isinstance(value, bool):
                    judge_values[key].append(value)
        judge_scores = {
            key: round(_mean(judge_values[key]), 2) if judge_values.get(key) else None
            for key in judge_metric_order
        }

        payload_models.append({
            "model": model,
            "grouping": round(_mean([r.get("scores", {}).get("groupingScore", 0.0) for r in grouped]), 4),
            "trap": round(_mean([r.get("scores", {}).get("trapAvoidance", 0.0) for r in grouped]), 4),
            "guidance": round(by_type.get("insufficient_information", 0.0), 4),
            # 안내 대상 집합의 혼동행렬. guidanceF1만 남은 옛 기록에는 0으로 표시한다.
            "guidanceTP": sum(r.get("scores", {}).get("guidanceTP", 0.0)
                               for r in rows if spec(r).get("type") == "insufficient_information"),
            "guidanceFP": sum(r.get("scores", {}).get("guidanceFP", 0.0)
                               for r in rows if spec(r).get("type") == "insufficient_information"),
            "guidanceFN": sum(r.get("scores", {}).get("guidanceFN", 0.0)
                               for r in rows if spec(r).get("type") == "insufficient_information"),
            "missingTP": missing_tp,
            "missingFP": missing_fp,
            "missingFN": missing_fn,
            "missingF1": round(missing_f1, 4),
            "refusal": round(by_type.get("non_goal_or_noise", 0.0), 4),
            # `pairF1` 이 이 케이스들에서 만들어내는 공짜 1.0 을 묶기 평균에 넣지 않고 여기서 따로 센다.
            "restraint": round(_mean([1.0 if r.get("outcome") in ("noSuggestion", "guidance") else 0.0
                                      for r in ungrouped]), 4),
            # 빈도(자제)와 별개로, 한 번 잘못 묶을 때 얼마나 크게 묶었는지 센다.
            # 원문 trace에서 계산하므로 기존 실행에도 소급 적용된다.
            "inventedPairs": sum(invented_pair_count(traces.get(r.get("run_id"))) for r in ungrouped),
            "ms": round((durations[len(durations) // 2] if durations else 0) / 1000, 2),
            "byType": {k: round(v, 4) for k, v in by_type.items()},
            "ctx": {
                "up": sum(1 for d in deltas if d > 0.001),
                "flat": sum(1 for d in deltas if abs(d) <= 0.001),
                "down": sum(1 for d in deltas if d < -0.001),
                "mean": round(_mean(deltas), 4),
            },
            "fmt": dict(fmt),
            "judge": judge_scores,
            "judgeCount": judge_count,
        })

    sample = by_model[models[0]]
    counts = {
        "grouping": sum(1 for r in sample if spec(r).get("hasGroups")),
        "guidance": sum(1 for r in sample if spec(r).get("type") == "insufficient_information"),
        "refusal": sum(1 for r in sample if spec(r).get("type") == "non_goal_or_noise"),
        "restraint": sum(1 for r in sample if not spec(r).get("hasGroups")),
        "inventedPairs": sum(1 for r in sample if not spec(r).get("hasGroups")),
    }

    selected = [r for model in models for r in by_model[model]]
    case_names = sorted({r["case_id"] for r in selected},
                        key=lambda n: (specs[n]["task"], specs[n]["type"], n))
    cells = {}
    for r in selected:
        info = spec(r)
        metric = PRIMARY_METRIC.get(info.get("type"), "groupingScore")
        cells[f"{r['case_id']}|{r['model']}|{r.get('recipe')}"] = {
            "v": r.get("scores", {}).get(metric),
            "o": r.get("outcome"),
            "ms": r.get("total_ms", 0),
        }

    runs = []
    for r in sorted(selected, key=lambda x: (x.get("model") or "", x.get("started_at") or "")):
        trace = traces.get(r.get("run_id"))
        if not trace:
            continue
        runs.append({
            "runId": r.get("run_id"),
            "model": r.get("model"),
            "task": r.get("task"),
            "recipe": r.get("recipe"),
            "case": r.get("case_id"),
            "outcome": r.get("outcome"),
            "totalMs": r.get("total_ms", 0),
            "scores": r.get("scores", {}),
            "output": r.get("output") or "",
            "steps": trace_steps(trace),
        })
        if len(runs) >= max_detail_runs:
            break

    started = sorted(r.get("started_at") or "" for r in selected if r.get("started_at"))
    window = f"{started[0][:16].replace('T', ' ')} – {started[-1][11:16]}" if started else "-"

    return {
        "run": {"window": window, "cases": len(case_names), "perModel": full,
                "total": full * len(models)},
        "counts": counts,
        "models": payload_models,
        "modelKeys": models,
        "primary": PRIMARY_METRIC,
        "cases": [{"name": n, **specs[n]} for n in case_names],
        "cells": cells,
        "runs": runs,
        "judge": {
            "meta": (judges or {}).get("meta"),
            "metrics": judge_metric_order,
            "models": [d for d in payload_models if d.get("judgeCount", 0) > 0],
        },
    }


def render_capability_tabs(payload):
    """집계 · 케이스별 · 실행 상세 · 용어 네 탭. 값 해석 문장은 넣지 않는다 —
    다음 실행에서 스크립트가 다시 만들 수 없는 문장은 리포트에 남기지 않는다."""
    run = payload["run"]
    counts = payload["counts"]
    ctx_pairs = payload["models"][0]["ctx"]
    ctx_total = ctx_pairs["up"] + ctx_pairs["flat"] + ctx_pairs["down"]
    excluded = run["cases"] - ctx_total

    run_options = "".join(
        f'<option value="{i}">{html_escape(r["model"])} · {html_escape(r["case"])} · {html_escape(r["recipe"] or "")}</option>'
        for i, r in enumerate(payload["runs"])
    )

    buttons = [
        '<button class="tab-button active" data-tab="tab-capability" onclick="openTab(\'tab-capability\')">집계</button>',
        '<button class="tab-button" data-tab="tab-cases" onclick="openTab(\'tab-cases\')">케이스별</button>',
        '<button class="tab-button" data-tab="tab-detail" onclick="openTab(\'tab-detail\')">실행 상세</button>',
        '<button class="tab-button" data-tab="tab-glossary" onclick="openTab(\'tab-glossary\')">용어</button>',
    ]

    aggregate = f"""
    <div id="tab-capability" class="tab-content active">
        <div class="cap-panel">
            <div class="cap-head"><h2>안내 기준 분해</h2><span class="cap-scope">메모별 missing 기준 쌍 · specific · measurable · time_bound</span></div>
            <div class="cap-body">
                <div class="cap-wrap"><table class="cap-table" id="cap-missing"><thead><tr>
                    <th>모델</th><th>정답 기준 (TP)</th><th>잘못 추가한 기준 (FP)</th><th>놓친 기준 (FN)</th><th>기준 F1</th>
                </tr></thead><tbody></tbody></table></div>
                <p class="cap-def">각 메모의 <code>missing</code> 기준을 <code>메모 ID · 기준명</code> 쌍으로 비교한 결정적 지표입니다. 안내 문장 자체의 품질은 평가하지 않습니다.</p>
            </div>
        </div>
        <div class="cap-panel">
            <div class="cap-head"><h2>LLM judge 품질 점수</h2><span class="cap-scope" id="cap-judge-meta">성공한 judge 결과를 자동 선택합니다</span></div>
            <div class="cap-body">
                <div class="cap-wrap"><table class="cap-table" id="cap-judge"><thead><tr></tr></thead><tbody></tbody></table></div>
                <p class="cap-def" id="cap-judge-empty">표시할 성공한 LLM judge 결과가 없습니다. <code>make llm-judge JUDGE=codex LIMIT=5</code> 실행 후 리포트를 다시 생성하세요.</p>
                <p class="cap-def">0–5점 루브릭의 케이스별 평균입니다. 결정적 지표(목표 연결·안내 대상 F1)와 별도로 생성된 목표·안내 문장의 품질을 평가하며, 관련성은 페르소나/프로필이 있는 케이스에서만 채점됩니다. 대시(—)는 해당 케이스에 적용하지 않은 항목입니다.</p>
            </div>
        </div>
        <div class="cap-panel">
            <div class="cap-head"><h2>능력 격자</h2><span class="cap-scope">열마다 대상 집합이 다릅니다 · 색 농도는 열 안에서의 상대값입니다</span></div>
            <div class="cap-body">
                <div class="cap-wrap"><table class="cap-table" id="cap-grid"><thead>
                    <tr>
                        <th rowspan="2">모델</th>
                        <th colspan="3" class="cap-group">목표 연결</th>
                        <th colspan="4" class="cap-group cap-split">안내</th>
                        <th colspan="2" class="cap-group cap-split">보류 및 자제</th>
                        <th rowspan="2" class="cap-group cap-split">실행 시간<span>초</span></th>
                    </tr>
                    <tr>
                        <th>목표 연결 점수<span>{counts['grouping']}건</span></th>
                        <th>함정 회피<span>{counts['grouping']}건</span></th>
                        <th>잘못 묶은 쌍 (FP)<span>{counts['inventedPairs']}건 · 낮을수록 좋음</span></th>
                        <th class="cap-split">안내 대상 일치도<span>{counts['guidance']}건</span></th>
                        <th>정답 안내 (TP)<span>{counts['guidance']}건</span></th>
                        <th>잘못 안내 (FP)<span>{counts['guidance']}건</span></th>
                        <th>놓친 안내 (FN)<span>{counts['guidance']}건</span></th>
                        <th class="cap-split">거절<span>{counts['refusal']}건</span></th>
                        <th>자제<span>{counts['restraint']}건</span></th>
                    </tr>
                </thead><tbody></tbody><tfoot></tfoot></table></div>
                <p class="cap-def">각 지표의 정의는 <b>용어</b> 탭에 있습니다. 유형마다 정답의 성격이 달라 열을 가로로 더한 값은 정의되지 않으므로 전체 평균 열은 두지 않습니다.</p>
            </div>
        </div>
        <div class="cap-panel">
            <div class="cap-head"><h2>유형별 분해</h2><span class="cap-scope">유형마다 주력 지표 하나</span></div>
            <div class="cap-body">
                <div class="cap-wrap"><table class="cap-table" id="cap-bytype"><thead><tr>
                    <th>모델</th>
                    <th>general<span>목표 연결</span></th>
                    <th>context_dependent<span>목표 연결</span></th>
                    <th class="cap-split">insufficient_information<span>안내</span></th>
                    <th>non_goal_or_noise<span>거절</span></th>
                </tr></thead><tbody></tbody></table></div>
                <p class="cap-def">경계선 왼쪽 두 유형은 <b>목표를 연결해야</b> 정답이고, 오른쪽 두 유형은 <b>연결하지 말아야</b> 정답입니다.</p>
            </div>
        </div>
        <div class="cap-panel">
            <div class="cap-head"><h2>맥락 효과</h2><span class="cap-scope">짝지어 비교 · 대상 {ctx_total}쌍 (전체 {run['cases']}쌍 중 {excluded}쌍 제외)</span></div>
            <div class="cap-body">
                <div class="cap-legend"><span><i class="cap-up"></i>개선</span><span><i class="cap-flat"></i>무변</span><span><i class="cap-down"></i>악화</span></div>
                <div id="cap-ctx"></div>
                <p class="cap-def">같은 케이스의 <code>promptOnly</code>와 <code>promptWithContext</code> 결과를 짝지어 차이를 냅니다. <code>context</code> 필드는 있으나 <code>persona</code>·<code>profile</code>이 비어 두 recipe의 프롬프트가 동일해지는 케이스는 대상에서 제외합니다. 오른쪽 숫자는 짝별 차이의 평균입니다.</p>
            </div>
        </div>
        <div class="cap-panel">
            <div class="cap-head"><h2>파싱 진단</h2><span class="cap-scope">모델당 {run['perModel']}건 누적 · trace의 parsed 단계에서 집계</span></div>
            <div class="cap-body">
                <div class="cap-wrap"><table class="cap-table" id="cap-fmt"><thead><tr>
                    <th>모델</th><th>modelReturned</th><th>kept</th>
                    <th class="cap-split">badID</th><th>tooFewIDs</th><th>alreadyUsed</th><th>overMaxMemo</th>
                </tr></thead><tbody></tbody></table></div>
                <p class="cap-def"><code>modelReturned</code>과 <code>kept</code>의 차이가 파서에서 버려진 양입니다. 오른쪽 네 열이 버려진 이유별 내역입니다. 각 용어의 뜻은 <b>용어</b> 탭에 있습니다.</p>
            </div>
        </div>
    </div>"""

    cases = f"""
    <div id="tab-cases" class="tab-content">
        <div class="cap-panel">
            <div class="cap-head"><h2>케이스별 점수</h2><span class="cap-scope">행 = 케이스 · 열 = 모델 · 값 = 그 케이스 유형의 주력 지표</span></div>
            <div class="cap-body">
                <div class="cap-ctl">
                    <label for="cap-f-recipe">recipe</label>
                    <select id="cap-f-recipe"><option value="promptOnly">promptOnly</option><option value="promptWithContext">promptWithContext</option></select>
                    <label for="cap-f-task">task</label>
                    <select id="cap-f-task"><option value="">전체</option><option value="weekly_goal">weekly_goal</option><option value="monthly_goal">monthly_goal</option></select>
                    <label for="cap-f-type">유형</label>
                    <select id="cap-f-type"><option value="">전체</option><option>general</option><option>context_dependent</option><option>insufficient_information</option><option>non_goal_or_noise</option></select>
                </div>
                <div class="cap-wrap"><table class="cap-table" id="cap-cases"><thead></thead><tbody></tbody></table></div>
                <p class="cap-def">셀의 색 농도는 표 전체(0–1) 기준입니다. 빈 칸은 그 유형에 해당 지표가 부여되지 않은 경우입니다. 셀에 마우스를 올리면 결과 종류와 소요 시간이 나옵니다.</p>
            </div>
        </div>
    </div>"""

    detail_body = f"""
                <div class="cap-ctl"><label for="cap-f-run">실행</label><select id="cap-f-run">{run_options}</select></div>
                <div class="cap-meta" id="cap-runmeta"></div>
                <div class="cap-final" id="cap-final"></div>
                <div id="cap-steps"></div>
                <p class="cap-def">단계 시각은 trace의 span 기록에서 계산한 값입니다. 기록 해상도가 초 단위인 구간이 있어 밀리초 자리는 참고용입니다. 각 단계는 접혀 있으며 머리글을 누르면 원문이 펼쳐집니다.</p>""" if payload["runs"] else """
                <p class="cap-def">원문 기록이 없습니다. 골든셋 실행에서 <code>TraceRecorder</code>가 켜져 있어야 이 탭이 채워집니다 (<code>Evals/results/traces/</code>).</p>"""

    detail = f"""
    <div id="tab-detail" class="tab-content">
        <div class="cap-panel">
            <div class="cap-head"><h2>실행 상세</h2><span class="cap-scope">한 건이 거쳐 간 단계 · 입력 · 프롬프트 전문 · 모델 원문 · 추출 JSON · 파싱 결과</span></div>
            <div class="cap-body">{detail_body}</div>
        </div>
    </div>"""

    glossary = """
    <div id="tab-glossary" class="tab-content">
        <div class="cap-panel">
            <div class="cap-head"><h2>목표를 연결해야 정답인 유형의 지표</h2><span class="cap-scope">general · context_dependent</span></div>
            <div class="cap-body"><dl class="cap-gloss">
                <dt>pairF1</dt><dd>정답 묶음이 만드는 「메모 쌍」 집합과 모델이 만든 쌍 집합의 F1.<em>정답이 [1,2,3] 한 묶음이면 쌍은 1-2 · 1-3 · 2-3 세 개</em></dd>
                <dt>trapAvoidance</dt><dd>케이스가 지정한 「묶이면 안 되는 쌍」 중 밟지 않은 비율. 함정이 지정되지 않은 케이스는 1.0.<em>1 − 밟은 함정 쌍 ÷ 전체 함정 쌍</em></dd>
                <dt>groupingScore</dt><dd>목표 연결의 최종 점수. 함정을 전부 밟으면 연결을 잘해도 0이 됩니다.<em>pairF1 × trapAvoidance</em></dd>
            </dl></div>
        </div>
        <div class="cap-panel">
            <div class="cap-head"><h2>목표를 연결하지 말아야 정답인 유형의 지표</h2><span class="cap-scope">insufficient_information · non_goal_or_noise</span></div>
            <div class="cap-body"><dl class="cap-gloss">
                <dt>guidanceF1</dt><dd>안내를 붙여야 할 입력 ID 집합과 모델이 실제로 붙인 집합의 F1. 안내 문장의 내용은 채점하지 않고, 어느 입력을 골랐는지만 봅니다.<em>insufficient_information 유형에 부여</em></dd>
                <dt>안내 TP/FP/FN</dt><dd>안내 대상 ID 집합의 혼동행렬입니다. <b>TP</b>는 안내해야 할 입력에 안내한 경우, <b>FP</b>는 안내하면 안 될 입력에 안내한 경우, <b>FN</b>은 안내해야 할 입력을 놓친 경우입니다. 이전 실행 기록에 원시 개수가 없으면 0으로 표시됩니다.</dd>
                <dt>missing 기준 TP/FP/FN</dt><dd>메모 ID와 보완 기준(<code>specific</code>·<code>measurable</code>·<code>time_bound</code>)의 쌍을 비교합니다. 안내 문장 자체가 아니라 모델이 지적한 보완 기준의 정확도를 봅니다.</dd>
                <dt>noSuggestionCorrect</dt><dd>목표로 묶지 말아야 하는 케이스에서 아무 제안 없이 끝냈거나(<code>noSuggestion</code>), 정답 입력 ID 전체를 빠짐없이 안내했으면(<code>guidance</code>) 1, 일부만 안내하거나 목표를 제안했으면 0. 안내 문장의 의미 품질은 별도 LLM judge가 평가합니다.<em>non_goal_or_noise 유형에 부여</em></dd>
                <dt>자제</dt><dd>정답 묶음이 없는 케이스에서 <b>제안을 만들지 않았는지</b>의 비율. 결과가 <code>noSuggestion</code>이나 <code>guidance</code>면 1, 제안을 냈으면 0.
                    <br>위 두 지표가 못 가르는 자리를 가릅니다 — <code>guidanceF1</code>은 <b>묶지 말아야 할 것을 묶은</b> 실패와 <b>아무 말도 하지 않은</b> 실패를 똑같이 0으로 처리하고, <code>noSuggestionCorrect</code>는 12건짜리 <code>non_goal_or_noise</code>만 보므로 <code>insufficient_information</code>에서 벌어지는 과잉 묶음을 못 봅니다.
                    <em>집계 전용 · RunRecord의 outcome에서 계산 · 묶기 평균에는 넣지 않습니다</em></dd>
                <dt>잘못 묶은 쌍 (FP)</dt><dd>False Positive. 정답 묶음이 없는 케이스에서 모델이 같은 목표로 잘못 연결한 메모 쌍의 총수입니다. 낮을수록 좋습니다. 제안 하나에 항목을 2개 넣으면 1쌍, 5개 넣으면 10쌍으로 세어 과잉 묶음의 크기를 드러냅니다.
                    <em>집계 전용 · trace의 extractedJSON에서 계산 · 기존 실행에도 소급 적용</em></dd>
            </dl></div>
        </div>
        <div class="cap-panel">
            <div class="cap-head"><h2>파싱 진단</h2><span class="cap-scope">파서가 모델 응답을 후보 목록으로 바꿀 때 세는 값</span></div>
            <div class="cap-body"><dl class="cap-gloss">
                <dt>modelReturned</dt><dd>모델이 낸 제안의 개수.</dd>
                <dt>kept</dt><dd>그중 파서를 통과해 살아남은 개수. 개수 상한으로 자르기 <b>전</b> 값입니다.</dd>
                <dt>requestedIDs</dt><dd>모델이 제안에 넣으려 한 항목 번호의 총 개수.</dd>
                <dt>badID</dt><dd>존재하지 않는 번호를 가리켜 버려진 항목 수.<em>입력에 없는 번호 · 범위를 벗어난 번호</em></dd>
                <dt>tooFewIDs</dt><dd>유효 항목이 2개 미만이라 <b>제안 통째로</b> 버려진 개수. 목표 하나에는 최소 2개가 들어가야 합니다.<em>이 값이 크면 모델이 묶지 못한 것이 아니라 형식을 지키지 못한 것</em></dd>
                <dt>alreadyUsed</dt><dd>앞선 제안이 이미 쓴 메모를 다시 넣어 제거된 항목 수.<em>같은 메모는 한 목표에만 들어갑니다</em></dd>
                <dt>overMaxMemo</dt><dd>한 제안에 상한을 넘겨 넣어 잘려나간 항목 수.<em>주간 상한 5개</em></dd>
            </dl></div>
        </div>
        <div class="cap-panel">
            <div class="cap-head"><h2>실행 단계</h2><span class="cap-scope">trace의 span 이름</span></div>
            <div class="cap-body"><dl class="cap-gloss">
                <dt>input</dt><dd>문자 예산에 맞춰 실제로 프롬프트에 실린 입력 메모.<em>facts: candidates = 후보 전체 · selected = 실린 수</em></dd>
                <dt>prompt</dt><dd>모델에 보낸 프롬프트 전문.</dd>
                <dt>rawResponse</dt><dd>모델이 돌려준 원문.<em>facts: tokensIn · tokensOut · characters</em></dd>
                <dt>extractedJSON</dt><dd>원문에서 JSON 객체만 뽑아낸 결과. 원문과 비교하면 코드펜스·사고 흔적 제거가 실제로 동작했는지 보입니다.</dd>
                <dt>parsed</dt><dd>파싱을 통과해 남은 결과와 위의 진단 숫자들.</dd>
                <dt>failure</dt><dd>생성이 실패했을 때의 오류 설명. 성공한 실행에는 없습니다.</dd>
            </dl></div>
        </div>
        <div class="cap-panel">
            <div class="cap-head"><h2>집계 규칙</h2><span class="cap-scope">이 리포트가 값을 모으는 방식</span></div>
            <div class="cap-body"><ul class="cap-rules">
                <li>묶기 지표는 <b>정답 묶음이 있는 케이스에서만</b> 모읍니다. 유형(<code>datasetType</code>)이 아니라 <code>expectedGroups</code>의 실제 유무로 판단합니다.</li>
                <li><code>pairF1</code>은 정답 묶음이 없는 케이스에서 「빈 답이 정답인데 빈 답을 냈다」는 이유로 1.0이 됩니다. 묶기 능력과 무관한 값이라 묶기 평균에서 빼고, 그 자리는 <b>자제</b> 열이 대신합니다.</li>
                <li><b>잘못 묶은 쌍 (FP)</b>은 다른 점수 열과 반대로 낮을수록 좋으므로 색 농도와 「열 최고」 판정도 반대로 적용합니다.</li>
                <li>유형마다 정답의 성격이 반대라 전체 평균 열은 두지 않습니다.</li>
                <li>열 머리에 대상 건수를 함께 적습니다. 대상이 12건인 지표는 한 건이 0.083씩 움직입니다.</li>
                <li>표시는 소수점 두 자리까지입니다. 원값은 셀에 마우스를 올리면 세 자리로 나옵니다.</li>
                <li>맥락 효과는 평균 두 개를 나란히 놓지 않고 같은 케이스끼리 짝지어 차이를 냅니다.</li>
                <li>케이스를 다 돌지 못한 모델은 평균을 왜곡하므로 집계에서 제외합니다.</li>
            </ul></div>
        </div>
    </div>"""

    return buttons, [aggregate, cases, detail, glossary]


def html_escape(text):
    return (str(text).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            .replace('"', "&quot;"))


def generate_html(data_by_level_by_model, data_by_model_by_level, live_runs, capability=None):
    has_live = bool(live_runs)
    live_origin_counts = Counter()
    for attempts in live_runs.values():
        if not attempts:
            continue
        record = attempts[max(attempts)]
        origin = record.get("_report_origin", "other")
        live_origin_counts[origin if origin in {"release", "debug"} else "other"] += 1
    tab_buttons = []
    tab_contents = []

    # Claude artifact의 네 탭을 기본 뼈대로 두고 실사용 기록을 실행 상세 뒤에 끼운다.
    if capability:
        cap_buttons, cap_contents = render_capability_tabs(capability)
        tab_buttons.extend(cap_buttons[:3])
        tab_contents.extend(cap_contents[:3])

    if has_live:
        active_class = " active" if not capability else ""
        tab_buttons.append(
            f'<button class="tab-button{active_class}" data-tab="tab-live" '
            'onclick="openTab(\'tab-live\')">실사용 기록</button>'
        )
        table_live = render_live_table(live_runs)
        tab_contents.append(f"""
        <div id="tab-live" class="tab-content{active_class}">
            <div class="cap-panel">
                <div class="cap-head"><h2>실사용 실행 기록</h2><span class="cap-scope">출처 = 정식 앱 · Debug · 행 = 실행 · 열 = 폴백 시도</span></div>
                <div class="cap-body">
                    {table_live}
                    <p class="cap-def">실제 앱 구동 중 수집된 <code>RunRecord</code>입니다. 각 실행의 제공자·모델·입력 크기·파싱 결과·토큰·소요 시간을 함께 표시합니다.</p>
                </div>
            </div>
        </div>
        """)

    if capability:
        tab_buttons.append(cap_buttons[3])
        tab_contents.append(cap_contents[3])

    if capability:
        run = capability["run"]
        report_meta = " ".join(
            f"<span>{k} <b>{v}</b></span>" for k, v in [
                ("실행", run["window"]), ("모델", len(capability["models"])),
                ("케이스", run["cases"]), ("모델당 실행", run["perModel"]),
                ("총", run["total"]),
            ]
        )
        if has_live:
            report_meta += (
                f" <span>정식 앱 <b>{live_origin_counts['release']}</b></span>"
                f" <span>Debug <b>{live_origin_counts['debug']}</b></span>"
            )
        report_eyebrow = "골든셋 · 목표 추천"
        report_title = "유형별 채점 리포트"
    else:
        report_eyebrow = "목표 추천"
        report_title = "실사용 실행 기록"
        report_meta = (
            f"<span>정식 앱 <b>{live_origin_counts['release']}</b></span>"
            f" <span>Debug <b>{live_origin_counts['debug']}</b></span>"
            if has_live else "<span>기록 없음</span>"
        )

    if not tab_contents:
        tab_contents.append('<div class="cap-panel"><div class="cap-body"><p class="cap-def">표시할 평가 또는 실사용 기록이 없습니다.</p></div></div>')

    payload = json.dumps(capability or {}, ensure_ascii=False, separators=(",", ":"))
    # 페이로드가 `</script>` 를 품으면 스크립트 블록이 그 자리에서 끊긴다.
    payload = payload.replace("</", "<\\/")
    return (HTML_TEMPLATE
            .replace("{cap_payload}", payload)
            .replace("{report_eyebrow}", report_eyebrow)
            .replace("{report_title}", report_title)
            .replace("{report_meta}", report_meta)
            .replace("{tab_buttons}", "".join(tab_buttons))
            .replace("{rows}", "".join(tab_contents)))


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
            expanded = os.path.expanduser(p)
            if "HorongHorong-Debug" in expanded:
                origin = "debug"
            elif "Application Support/HorongHorong/runs" in expanded:
                origin = "release"
            else:
                origin = "other"
            loaded = load_records_from_path(p)
            for record in loaded:
                record["_report_origin"] = origin
            records.extend(loaded)
    else:
        here = os.path.dirname(os.path.abspath(__file__))
        default_paths = [
            (os.path.expanduser("~/Library/Application Support/HorongHorong/runs"), "release"),
            (os.path.expanduser("~/Library/Application Support/HorongHorong-Debug/runs"), "debug"),
            (os.path.join(here, "results"), "golden"),
        ]
        for p, origin in default_paths:
            if os.path.exists(p):
                loaded = load_records_from_path(p)
                for record in loaded:
                    record["_report_origin"] = origin
                records.extend(loaded)

    # 같은 모델·같은 케이스를 컨텍스트별로 여러 번 실행할 수 있다. 평면 딕셔너리에
    # 넣으면 마지막 실행이 앞 결과를 덮어쓴다. 두 비교 탭이 서로 다른 축을 고를 수 있게
    # 3차원 기록을 두 방향으로 보존한다.
    data_by_level_by_model = defaultdict(lambda: defaultdict(dict))
    data_by_model_by_level = defaultdict(lambda: defaultdict(dict))
    live_runs = defaultdict(dict)

    for row in records:
        case_id = row.get("case_id")
        source = row.get("source")

        # 실사용(Live) 기록 판별: case_id가 없거나 source가 "live"
        if not case_id or source == "live":
            run_id = row.get("run_id") or "UNKNOWN_RUN"
            task = row.get("task") or "weekly_goal"
            origin = row.get("_report_origin", "other")
            run_key = f"{origin}:{run_id} ({task})"
            attempt = row.get("attempt", 1)
            live_runs[run_key][attempt] = row
        else:
            # 골든셋/평가 레코드
            level = row.get("recipe", row.get("level", "promptOnly"))
            provider = row.get("provider", "unknown")
            model = row.get("model", "unknown")
            model_key = f"{provider}|{model}"

            data_by_level_by_model[model_key][case_id][level] = row
            if model:
                data_by_model_by_level[level][case_id][model_key] = row

    # 유형 정보는 `RunRecord` 에 없고 케이스 파일에만 있으므로 `case_id` 로 조인한다.
    # 원문(trace)은 있으면 쓰고 없으면 상세 탭만 비운다.
    capability = build_capability_payload(
        records, load_case_specs(), load_traces(), load_judges()
    )

    html = generate_html(data_by_level_by_model, data_by_model_by_level, live_runs, capability)

    with open(args.output, "w", encoding="utf-8") as f:
        f.write(html)

    print(f"✅ HTML 대시보드 생성 완료: {os.path.abspath(args.output)}")
    print(f"터미널에서 'open {args.output}' 명령어를 실행하여 브라우저에서 확인하세요.")


if __name__ == "__main__":
    main()
