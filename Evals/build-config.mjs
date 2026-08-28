// 골든셋 케이스에서 promptfooconfig.yaml 을 생성한다.
//
// 정답(expectedGroups)을 YAML 에 손으로 복사하면 골든셋과 어긋나기 시작한다.
// 단일 출처는 Evals/golden/cases/weekly/**/*.json 이고, 이 스크립트가 기계적으로 옮긴다.
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
// weekly/ 만 읽는다 — monthly 는 memos 대신 weeklyGoals 를 받아 입력 모양이 다르다.
const caseRoot = path.join(root, 'Evals/golden/cases/weekly');

/** 하위 폴더까지 훑는다. 케이스가 페르소나별로 갈려 있어 한 겹만 읽으면 전부 놓친다. */
function jsonFilesUnder(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) return jsonFilesUnder(full);
    return e.name.endsWith('.json') ? [full] : [];
  });
}

const cases = jsonFilesUnder(caseRoot)
  .sort()
  .map((f) => JSON.parse(fs.readFileSync(f, 'utf8')));

const config = {
  description: '성취탭 주간 목표 추천 — 골든셋 평가',
  prompts: ['{{caseName}}'],
  providers: [{ id: 'exec:./Evals/replay.sh', label: 'AFM (replay)' }],
  defaultTest: {
    assert: [{ type: 'javascript', value: 'file://Evals/assert-grouping.mjs' }],
  },
  tests: cases.map((c) => ({
    description: c.caseName,
    vars: {
      caseName: c.caseName,
      // 입력 할 일. 정답은 assertion 이 골든셋에서 직접 읽으므로 vars 에 넣지 않는다.
      memos: c.memos.map((m) => m.content).join('\n'),
    },
  })),
};

// YAML 대신 JSON 으로 쓴다. promptfoo 는 promptfooconfig.json 도 읽고,
// JSON 은 이스케이프 걱정 없이 안전하게 생성할 수 있다.
const out = path.join(root, 'promptfooconfig.json');
fs.writeFileSync(out, JSON.stringify(config, null, 2) + '\n');
console.log(`${cases.length}개 케이스 → ${path.relative(root, out)}`);
