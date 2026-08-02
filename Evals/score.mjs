// 골든셋 채점: 쌍(pair) 단위 precision / recall.
//
// 묶음 단위로 채점하면 부분 정답(3개 중 2개만 맞춤)이 0점이 되어 개선이 보이지 않는다.
// 쌍 단위는 부분 정답을 부분 점수로 잡아준다.
//
// promptfoo 의 javascript assertion 에서 import 해서 쓴다.

/** 한 묶음에서 나올 수 있는 모든 2개 조합을 "a|b"(정렬) 형태로 만든다. */
export function pairsOf(group) {
  const ids = [...group].sort();
  const out = new Set();
  for (let i = 0; i < ids.length; i += 1) {
    for (let j = i + 1; j < ids.length; j += 1) {
      out.add(`${ids[i]}|${ids[j]}`);
    }
  }
  return out;
}

/** 여러 묶음의 쌍을 합집합으로 모은다. */
export function pairsOfAll(groups) {
  const out = new Set();
  for (const g of groups ?? []) {
    for (const p of pairsOf(g)) out.add(p);
  }
  return out;
}

/**
 * @param {string[][]} expectedGroups 정답 묶음들
 * @param {string[][]} predictedGroups 모델이 낸 묶음들
 * @param {string[][]} shouldNotGroup 같이 묶이면 안 되는 조합들
 */
export function score(expectedGroups, predictedGroups, shouldNotGroup = []) {
  const expected = pairsOfAll(expectedGroups);
  const predicted = pairsOfAll(predictedGroups);
  const forbidden = pairsOfAll(shouldNotGroup);

  let hit = 0;
  let violations = 0;
  for (const p of predicted) {
    if (expected.has(p)) hit += 1;
    if (forbidden.has(p)) violations += 1;
  }

  // 정답이 "묶을 것 없음"인데 실제로 아무것도 안 묶었으면 만점으로 본다.
  const precision = predicted.size === 0 ? (expected.size === 0 ? 1 : 0) : hit / predicted.size;
  const recall = expected.size === 0 ? (predicted.size === 0 ? 1 : 0) : hit / expected.size;
  const f1 = precision + recall === 0 ? 0 : (2 * precision * recall) / (precision + recall);

  return {
    precision,
    recall,
    f1,
    hit,
    expectedPairs: expected.size,
    predictedPairs: predicted.size,
    violations,
  };
}
