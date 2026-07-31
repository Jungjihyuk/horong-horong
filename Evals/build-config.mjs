// 골든셋 케이스에서 promptfooconfig.yaml 을 생성한다.
//
// 정답(expectedGroups)을 YAML 에 손으로 복사하면 골든셋과 어긋나기 시작한다.
// 단일 출처는 Evals/golden/cases/*.json 이고, 이 스크립트가 기계적으로 옮긴다.
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
const casesDir = path.join(root, 'Evals/golden/cases');

const cases = fs
  .readdirSync(casesDir)
  .filter((f) => f.endsWith('.json'))
  .sort()
  .map((f) => JSON.parse(fs.readFileSync(path.join(casesDir, f), 'utf8')));

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
