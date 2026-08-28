// promptfoo javascript assertion — 케이스 하나를 채점하고 사람이 읽을 사유를 만든다.
//
// 정답(expectedGroups)은 vars 로 받지 않고 골든셋 파일에서 직접 읽는다.
// vars 로 넘기면 promptfoo UI 에 raw JSON 칼럼이 생겨 표가 읽기 어려워진다.
import fs from 'node:fs';
import path from 'node:path';
import { score } from './score.mjs';

// `cases/monthly/` 도 안 읽는다 — 월간은 할일이 아니라 주간 목표를 입력으로 받아 모양이 다르다.
// 하위 폴더까지 훑는다(`weekly/developer/` 처럼 페르소나로 나뉜다).
const caseRoot = path.resolve(import.meta.dirname, 'golden/cases/weekly');

/** 하위 폴더까지 훑어 .json 파일 경로를 모은다. */
function jsonFilesUnder(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) return jsonFilesUnder(full);
    return e.name.endsWith('.json') ? [full] : [];
  });
}

let goldenByName = null;
function golden(caseName) {
  if (goldenByName === null) {
    goldenByName = {};
    for (const f of jsonFilesUnder(caseRoot)) {
      const c = JSON.parse(fs.readFileSync(f, 'utf8'));
      goldenByName[c.caseName] = c;
    }
  }
  return goldenByName[caseName];
}

export default function (output, context) {
  let row;
  try {
    row = JSON.parse(output);
  } catch {
    return { pass: false, score: 0, reason: `JSON 파싱 실패: ${String(output).slice(0, 80)}` };
  }
  if (row.error) return { pass: false, score: 0, reason: row.error };

  const c = golden(context.vars.caseName);
  if (!c) return { pass: false, score: 0, reason: `골든셋에 없는 케이스: ${context.vars.caseName}` };

  // 정답 묶음은 `{ type, title, memos }` 다. 채점기는 id 묶음만 알면 되고,
  // **주간 실행이니 주간 정답만** 꺼낸다.
  const expected = (c.expectedGroups ?? [])
    .filter((g) => g.type === 'weekly_goal')
    .map((g) => g.memos);
  const traps = c.traps ?? [];
  const predicted = row.predictedGroups ?? [];
  const s = score(expected, predicted, traps);

  // 금지 조합을 묶은 것은 단순 오답보다 무겁게 본다. 알려진 실패 유형이기 때문이다.
  const pass = s.violations === 0 && s.groupingScore >= 0.7;

  // id(m1)만 보여주면 왜 틀렸는지 판단할 수 없다. 본문으로 풀어서 보여준다.
  const text = Object.fromEntries((c.memos ?? []).map((m) => [m.id, m.content]));
  const readable = (groups) =>
    groups.length === 0
      ? '(없음)'
      : groups.map((g) => g.map((id) => text[id] ?? id).join(' + ')).join('\n      ');

  const titles = row.titles ?? [];
  const modelLines =
    predicted.length === 0
      ? '(없음)'
      : predicted
          .map((g, i) => `"${titles[i] ?? '?'}"\n      ${g.map((id) => text[id] ?? id).join(' + ')}`)
          .join('\n  ');

  const reason = [
    `F1 ${s.f1.toFixed(2)}  (P ${s.precision.toFixed(2)} / R ${s.recall.toFixed(2)})` +
      (s.violations > 0 ? `  ⚠️ 함정 ${s.violations}/${s.trapPairs}쌍을 밟음` : ''),
    ``,
    `모델  ${modelLines}`,
    `정답  ${readable(expected)}`,
  ].join('\n');

  return { pass, score: s.f1, reason };
}
