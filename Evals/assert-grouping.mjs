// promptfoo javascript assertion — 케이스 하나를 채점하고 사람이 읽을 사유를 만든다.
//
// 정답(expectedGroups)은 vars 로 받지 않고 골든셋 파일에서 직접 읽는다.
// vars 로 넘기면 promptfoo UI 에 raw JSON 칼럼이 생겨 표가 읽기 어려워진다.
import fs from 'node:fs';
import path from 'node:path';
import { score } from './score.mjs';

const caseDirs = ['golden/cases', 'golden/drafts'].map((d) => path.resolve(import.meta.dirname, d));

let goldenByName = null;
function golden(caseName) {
  if (goldenByName === null) {
    goldenByName = {};
    for (const dir of caseDirs.filter((d) => fs.existsSync(d))) {
      for (const f of fs.readdirSync(dir).filter((x) => x.endsWith('.json'))) {
        const c = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
        goldenByName[c.caseName] = c;
      }
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

  const expected = c.expectedGroups ?? [];
  const forbidden = c.shouldNotGroup ?? [];
  const predicted = row.predictedGroups ?? [];
  const s = score(expected, predicted, forbidden);

  // 금지 조합을 묶은 것은 단순 오답보다 무겁게 본다. 알려진 실패 유형이기 때문이다.
  const pass = s.violations === 0 && s.f1 >= 0.7;

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
      (s.violations > 0 ? `  ⚠️ 금지 조합 ${s.violations}건` : ''),
    ``,
    `모델  ${modelLines}`,
    `정답  ${readable(expected)}`,
  ].join('\n');

  return { pass, score: s.f1, reason };
}
