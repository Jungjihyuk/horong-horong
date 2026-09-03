import Foundation
import HorongAI

/// `Evals/` 폴더의 골든셋 채점 결과를 읽어 모델 비교표로 집계한다.
///
/// **`eval-report.py` 와 열 이름·지표 정의를 그대로 맞춘다.** 같은 데이터를 두 화면이
/// 다른 이름으로 부르거나 다른 숫자를 내면 이야기가 통하지 않는다. 특히 아래 규약을 옮겼다:
///
/// - 케이스를 가르는 축은 **`expectedGroups` 유무**(`hasGroups`)다. «묶어야 정답» 인 케이스와
///   «묶지 말아야 정답» 인 케이스는 같은 자로 재면 안 된다.
/// - 유형(`datasetType`)마다 **주력 지표가 하나씩** 있다(→ `primaryMetric`).
/// - **케이스를 다 돌지 못한 모델은 제외한다.** 절반만 돈 실행의 평균은 다 돈 모델과
///   나란히 놓을 수 없다. 같은 모델이 여러 번 완주했으면 마지막 실행을 쓴다.
/// - 맥락 효과는 평균 두 개를 나란히 놓지 않고 **같은 케이스끼리 짝지어** 차이를 낸다.
///
/// 결과(`results/`)는 gitignore 된 산출물이라 앱에 번들할 수 없다. 그래서 폴더를 받는다.
enum GoldenEvalReport {

    /// 유형마다 «무엇을 잘한 것으로 칠 것인가» 가 다르다. `eval-report.py` 의 `PRIMARY_METRIC`.
    static let primaryMetric: [String: String] = [
        "general": "groupingScore",
        "context_dependent": "groupingScore",
        "insufficient_information": "guidanceF1",
        "non_goal_or_noise": "noSuggestionCorrect",
    ]

    /// 유형별 분해에 세우는 순서. 경계선 왼쪽 둘은 **묶어야** 정답, 오른쪽 둘은 **묶지 말아야** 정답이다.
    static let typeOrder = ["general", "context_dependent", "insufficient_information", "non_goal_or_noise"]

    /// 파서가 모델 응답을 후보 목록으로 바꿀 때 세는 값. 원문(trace)의 `parsed` 단계에서 나온다.
    static let parseKeys = ["modelReturned", "kept", "badID", "tooFewIDs", "alreadyUsed", "overMaxMemo"]

    /// LLM judge 루브릭 항목. 순서와 이름 모두 `eval-report.py` 와 같다.
    static let judgeMetrics = [
        "semantic_cohesion", "noise_exclusion", "measurability", "clarity", "time_fit",
        "relevance", "guidance_fit", "guidance_actionability", "grammar", "vocabulary", "tone",
    ]

    static let judgeLabels: [String: String] = [
        "semantic_cohesion": "응집성", "noise_exclusion": "노이즈 배제", "measurability": "측정 가능성",
        "clarity": "명확성", "time_fit": "기간 적합성", "relevance": "관련성", "guidance_fit": "안내 적합성",
        "guidance_actionability": "안내 실행성", "grammar": "문법", "vocabulary": "어휘", "tone": "어투",
    ]

    // MARK: - 결과 모양

    struct ModelRow: Identifiable, Sendable {
        var id: String { "\(provider)|\(model)" }
        let model: String
        let provider: String

        // 목표 연결 — 정답 묶음이 있는 케이스에서만 잰다.
        let groupingScore: Double
        let trapAvoidance: Double

        // 안내 — `insufficient_information` 케이스에서만 잰다.
        let guidance: Double
        let guidanceTP: Double
        let guidanceFP: Double
        let guidanceFN: Double

        // 보류 및 자제
        /// `non_goal_or_noise` 유형의 주력 지표.
        let refusal: Double
        /// 정답 묶음이 없는 케이스에서 **묶지 않고 넘어간** 비율.
        ///
        /// `pairF1` 이 이 케이스들에서 만들어내는 공짜 1.0 을 묶기 평균에 넣지 않고 여기서 따로 센다.
        let restraint: Double

        /// 실행 시간 중앙값(초).
        let seconds: Double

        // 안내 기준 분해 — 메모별 `missing` 기준을 «메모 ID · 기준명» 쌍으로 비교한다.
        let missingTP: Double
        let missingFP: Double
        let missingFN: Double
        let missingF1: Double

        /// 유형별 주력 지표. 값이 없는 유형은 담지 않는다.
        let byType: [String: Double]

        // 맥락 효과 — 짝지어 비교한 케이스 수와 차이의 평균.
        let contextUp: Int
        let contextFlat: Int
        let contextDown: Int
        let contextMean: Double

        /// 파싱 진단 누적값.
        let parse: [String: Int]

        /// LLM judge 항목별 평균. 판정되지 않은 항목은 담지 않는다.
        let judgeScores: [String: Double]
        let judgeAverage: Double?
        /// 판정된 실행 수.
        let judgeCount: Int
    }

    struct JudgeMeta: Sendable {
        let judge: String
        let judgeModel: String
        let rubricVersion: String
        let fileCount: Int
    }

    struct Summary: Sendable {
        let rows: [ModelRow]
        /// 기준이 된 (케이스 × recipe) 조합 수.
        let coverage: Int
        /// 완주하지 못해 비교에서 빠진 모델.
        let excluded: [String]
        /// 열마다 대상 집합이 다르다 — 머리글에 «N건» 으로 적는다.
        let groupingCount: Int
        let guidanceCount: Int
        let refusalCount: Int
        let restraintCount: Int
        /// 맥락 효과 비교 대상 쌍 수와, 정보가 0 이라 제외한 쌍 수.
        let contextPairs: Int
        let contextExcluded: Int
        let fileCount: Int
        let caseCount: Int
        let judgeMeta: JudgeMeta?
        /// 원문(trace)을 하나도 찾지 못했나. 파싱 진단이 비는 이유를 화면에 알려야 한다.
        let hasTraces: Bool

        static let empty = Summary(
            rows: [], coverage: 0, excluded: [],
            groupingCount: 0, guidanceCount: 0, refusalCount: 0, restraintCount: 0,
            contextPairs: 0, contextExcluded: 0,
            fileCount: 0, caseCount: 0, judgeMeta: nil, hasTraces: false
        )
    }

    /// 케이스 파일에서 읽는 것. 채점에 필요한 최소한만 뽑는다.
    struct CaseSpec: Sendable {
        let datasetType: String
        /// 정답 묶음이 있는가. **유형이 아니라 이것으로 가른다** — 분류가 어긋난 케이스가
        /// 있어도 집계가 흔들리지 않는다(`eval-report.py` 와 같은 규약).
        let hasGroups: Bool
        /// `context` 키는 있지만 `persona`·`profile` 이 비면 두 recipe 의 프롬프트가 글자 단위로
        /// 같아진다. 그런 짝은 맥락 효과에서 정보가 0 이므로 제외한다.
        let realContext: Bool
    }

    // MARK: - 읽기

    /// 폴더가 골든셋 평가 폴더로 쓸 만한가. 둘 중 하나라도 있으면 받아들인다.
    static func looksLikeEvalsDirectory(_ url: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: url.appendingPathComponent("results").path)
            || fm.fileExists(atPath: url.appendingPathComponent("golden").path)
    }

    /// `golden/**/*.json` 에서 케이스 이름 → 유형·정답묶음·맥락 유무를 읽는다.
    ///
    /// 파일이 깨져 있으면 조용히 건너뛴다 — **정답지 한 장 때문에 화면 전체가 비면 안 된다.**
    static func loadCaseSpecs(evalsDirectory: URL) -> [String: CaseSpec] {
        let root = evalsDirectory.appendingPathComponent("golden", isDirectory: true)
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return [:]
        }
        var specs: [String: CaseSpec] = [:]
        for case let url as URL in walker where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = object["caseName"] as? String else { continue }
            let groups = (object["expectedGroups"] as? [Any]) ?? (object["expectedGoalGroups"] as? [Any]) ?? []
            let context = object["context"] as? [String: Any] ?? [:]
            let persona = (context["persona"] as? String).map { !$0.isEmpty } ?? false
            // **비어 있으면 없는 것으로 친다.** `profile: []` 로만 적힌 케이스가 8개 있는데
            // 키가 있다는 이유로 «맥락 있음» 으로 세면 두 recipe 의 프롬프트가 똑같은 짝이
            // 비교 대상에 들어와 «무변» 을 부풀린다(실측 2026-08-28: 모델마다 5쌍씩).
            let profile = switch context["profile"] {
            case let dictionary as [String: Any]: !dictionary.isEmpty
            case let array as [Any]: !array.isEmpty
            case let text as String: !text.isEmpty
            case .none, is NSNull: false
            default: true
            }
            specs[name] = CaseSpec(
                datasetType: object["datasetType"] as? String ?? "unknown",
                hasGroups: !groups.isEmpty,
                realContext: persona || profile
            )
        }
        return specs
    }

    /// `results/*.jsonl` 을 읽는다. **하위 폴더는 훑지 않는다** — `v1`·`v2` 같은 보관용
    /// 폴더가 섞이면 스키마가 다른 옛 실행이 평균에 들어온다(`eval-report.py` 와 같은 규약).
    static func loadRecords(evalsDirectory: URL) -> (records: [RunRecord], fileCount: Int) {
        let root = evalsDirectory.appendingPathComponent("results", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var records: [RunRecord] = []
        var used = 0
        for file in files where file.pathExtension == "jsonl" {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            var any = false
            for line in text.split(separator: "\n") {
                guard let data = line.data(using: .utf8),
                      let record = try? decoder.decode(RunRecord.self, from: data) else { continue }
                records.append(record)
                any = true
            }
            if any { used += 1 }
        }
        return (records, used)
    }

    /// `results/judges/*.jsonl` 의 **성공한** 판정만 모은다.
    ///
    /// judge 실행은 결과 파일 하나(대개 모델 하나)를 대상으로 하므로 파일 하나만 고르면
    /// 나머지 모델이 통째로 빠진다. 실패는 파일이 아니라 레코드의 `status` 로 거르고,
    /// 같은 `runId` 가 여러 파일에 있으면 나중 파일의 결과를 쓴다.
    static func loadJudgements(evalsDirectory: URL) -> (byRunID: [String: [String: Double]], meta: JudgeMeta?) {
        let root = evalsDirectory.appendingPathComponent("results/judges", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        let ordered = files.filter { $0.pathExtension == "jsonl" }.sorted { left, right in
            let l = (try? left.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let r = (try? right.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return l < r
        }

        var byRunID: [String: [String: Double]] = [:]
        var judges: Set<String> = [], judgeModels: Set<String> = [], rubrics: Set<String> = []
        var usedFiles = 0
        for file in ordered {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            var any = false
            for line in text.split(separator: "\n") {
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let runID = object["runId"] as? String,
                      object["status"] as? String == "ok",
                      let evaluation = object["evaluation"] as? [String: Any],
                      let summary = evaluation["summary"] as? [String: Any] else { continue }
                byRunID[runID] = summary.compactMapValues { $0 as? Double ?? ($0 as? Int).map(Double.init) }
                judges.insert(object["judge"] as? String ?? "-")
                judgeModels.insert(object["judgeModel"] as? String ?? "-")
                rubrics.insert(object["rubricVersion"] as? String ?? "-")
                any = true
            }
            if any { usedFiles += 1 }
        }
        guard !byRunID.isEmpty else { return ([:], nil) }
        return (byRunID, JudgeMeta(
            judge: judges.sorted().joined(separator: ", "),
            judgeModel: judgeModels.sorted().joined(separator: ", "),
            rubricVersion: rubrics.sorted().joined(separator: ", "),
            fileCount: usedFiles
        ))
    }

    /// 원문(trace)의 `parsed` 단계 값을 실행 id 별로 읽는다.
    ///
    /// **필요한 실행만 읽는다.** 폴더에 4,700개가 넘게 쌓여 있어 전부 열면 화면이 멈춘다.
    /// 파일 이름이 `{runId}_{task}_{attempt}.json` 이라 앞부분으로 걸러낼 수 있다.
    static func loadParseFacts(evalsDirectory: URL, runIDs: Set<String>) -> [String: [String: Int]] {
        let root = evalsDirectory.appendingPathComponent("results/traces", isDirectory: true)
        guard !runIDs.isEmpty,
              let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return [:] }

        var facts: [String: [String: Int]] = [:]
        for name in names where name.hasSuffix(".json") {
            guard let underscore = name.firstIndex(of: "_") else { continue }
            let runID = String(name[name.startIndex..<underscore])
            guard runIDs.contains(runID), facts[runID] == nil else { continue }
            guard let data = try? Data(contentsOf: root.appendingPathComponent(name)),
                  let trace = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let spans = trace["spans"] as? [[String: Any]] else { continue }
            for span in spans where span["name"] as? String == "parsed" {
                if let raw = span["facts"] as? [String: Any] {
                    facts[runID] = raw.compactMapValues { $0 as? Int }
                }
            }
        }
        return facts
    }

    // MARK: - 집계

    static func summarize(evalsDirectory: URL) -> Summary {
        let specs = loadCaseSpecs(evalsDirectory: evalsDirectory)
        let (all, fileCount) = loadRecords(evalsDirectory: evalsDirectory)

        // 골든셋 행만 남긴다. 정답지에 없는 이름은 옛 케이스라 유형을 못 붙인다.
        let golden = all.filter { record in
            guard let caseId = record.caseId, record.source != "live" else { return false }
            return specs[caseId] != nil
        }
        guard !golden.isEmpty else { return .empty }

        // **모델 이름이 아니라 실행 배치로 묶는다.** 같은 모델을 여러 번 돌린 기록이 섞이면
        // 한 모델만 행이 많아져 완주 판정이 무너진다. run_id 의 케이스 접미사(`-w12`·`-m3`)를
        // 떼면 배치 하나가 남는다.
        var batches: [BatchKey: [RunRecord]] = [:]
        for record in golden {
            let key = BatchKey(
                model: record.model ?? "unknown",
                provider: record.provider ?? "unknown",
                batch: batchID(from: record.runId ?? "")
            )
            batches[key, default: []].append(record)
        }

        // 가장 많은 (케이스 × recipe) 를 덮은 배치를 기준으로 삼고, 그것을 온전히 덮은 것만 비교한다.
        let coverages = batches.mapValues { rows in Set(rows.map { "\($0.caseId ?? "")|\($0.recipe ?? "")" }) }
        guard let reference = coverages.values.max(by: { $0.count < $1.count }), !reference.isEmpty else {
            return .empty
        }

        var latest: [BatchKey: [RunRecord]] = [:]
        var excluded: Set<String> = []
        for (key, rows) in batches {
            guard coverages[key] == reference else {
                excluded.insert(key.model)
                continue
            }
            let modelKey = BatchKey(model: key.model, provider: key.provider, batch: "")
            // 같은 모델이 여러 번 완주했으면 마지막 실행을 쓴다.
            if let previous = latest[modelKey],
               (previous.first?.startedAt ?? .distantPast) >= (rows.first?.startedAt ?? .distantPast) {
                continue
            }
            latest[modelKey] = rows
        }
        excluded.subtract(latest.keys.map(\.model))

        let (judgements, judgeMeta) = loadJudgements(evalsDirectory: evalsDirectory)
        let neededRunIDs = Set(latest.values.flatMap { $0.compactMap(\.runId) })
        let parseFacts = loadParseFacts(evalsDirectory: evalsDirectory, runIDs: neededRunIDs)

        let rows = latest
            .map { key, records in
                row(model: key.model, provider: key.provider, records: records,
                    specs: specs, judgements: judgements, parseFacts: parseFacts)
            }
            .sorted { $0.groupingScore > $1.groupingScore }

        // 열마다 대상 집합이 다르다. 아무 모델 하나의 행 수로 세면 된다 — 모두 같은 케이스를 돌았다.
        let sample = latest.values.first ?? []
        func spec(_ record: RunRecord) -> CaseSpec? { specs[record.caseId ?? ""] }
        let contextPairs = rows.first.map { $0.contextUp + $0.contextFlat + $0.contextDown } ?? 0
        let caseNames = Set(sample.compactMap(\.caseId))

        return Summary(
            rows: rows,
            coverage: reference.count,
            excluded: excluded.sorted(),
            groupingCount: sample.filter { spec($0)?.hasGroups == true }.count,
            guidanceCount: sample.filter { spec($0)?.datasetType == "insufficient_information" }.count,
            refusalCount: sample.filter { spec($0)?.datasetType == "non_goal_or_noise" }.count,
            restraintCount: sample.filter { spec($0)?.hasGroups == false }.count,
            contextPairs: contextPairs,
            contextExcluded: max(0, caseNames.count - contextPairs),
            fileCount: fileCount,
            caseCount: specs.count,
            judgeMeta: judgeMeta,
            hasTraces: !parseFacts.isEmpty
        )
    }

    // MARK: - 안쪽

    private struct BatchKey: Hashable {
        let model: String
        let provider: String
        let batch: String
    }

    /// `G-2026-08-27T12-54-28+0900-w12` → `G-2026-08-27T12-54-28+0900`
    private static func batchID(from runID: String) -> String {
        guard let range = runID.range(of: "-[wm][0-9]+$", options: .regularExpression) else { return runID }
        return String(runID[runID.startIndex..<range.lowerBound])
    }

    private static func row(
        model: String,
        provider: String,
        records: [RunRecord],
        specs: [String: CaseSpec],
        judgements: [String: [String: Double]],
        parseFacts: [String: [String: Int]]
    ) -> ModelRow {
        func spec(_ record: RunRecord) -> CaseSpec? { specs[record.caseId ?? ""] }

        let grouped = records.filter { spec($0)?.hasGroups == true }
        let ungrouped = records.filter { spec($0)?.hasGroups == false }
        let insufficient = records.filter { spec($0)?.datasetType == "insufficient_information" }

        var byType: [String: Double] = [:]
        for (kind, metric) in primaryMetric {
            let picked = records.filter { spec($0)?.datasetType == kind }
            guard !picked.isEmpty else { continue }
            byType[kind] = mean(picked.map { $0.scores[metric] ?? 0 })
        }

        let missingTP = insufficient.reduce(0.0) { $0 + ($1.scores["missingTP"] ?? 0) }
        let missingFP = insufficient.reduce(0.0) { $0 + ($1.scores["missingFP"] ?? 0) }
        let missingFN = insufficient.reduce(0.0) { $0 + ($1.scores["missingFN"] ?? 0) }
        let missingPrecision = missingTP + missingFP > 0 ? missingTP / (missingTP + missingFP) : 0
        let missingRecall = missingTP + missingFN > 0 ? missingTP / (missingTP + missingFN) : 0
        let missingF1 = missingPrecision + missingRecall > 0
            ? 2 * missingPrecision * missingRecall / (missingPrecision + missingRecall)
            : 0

        // 맥락 효과 — 같은 케이스의 두 recipe 를 짝지어 차이를 낸다. 프롬프트가 실제로
        // 달라지는 케이스(`realContext`)만 대상이다.
        var pairs: [String: [String: Double]] = [:]
        for record in records {
            guard let info = spec(record), info.hasGroups, info.realContext,
                  let caseId = record.caseId, let recipe = record.recipe else { continue }
            pairs[caseId, default: [:]][recipe] = record.scores["groupingScore"] ?? 0
        }
        let deltas = pairs.values.compactMap { value -> Double? in
            guard let with = value["promptWithContext"], let only = value["promptOnly"] else { return nil }
            return with - only
        }

        var parse: [String: Int] = [:]
        for record in records {
            guard let facts = parseFacts[record.runId ?? ""] else { continue }
            for key in parseKeys { parse[key, default: 0] += facts[key] ?? 0 }
        }

        var judgeValues: [String: [Double]] = [:]
        var judgeCount = 0
        for record in records {
            guard let summary = judgements[record.runId ?? ""] else { continue }
            judgeCount += 1
            for (key, value) in summary { judgeValues[key, default: []].append(value) }
        }
        let judgeScores = judgeValues.compactMapValues { $0.isEmpty ? nil : mean($0) }
        let judgeAverage = judgeScores.isEmpty ? nil : mean(Array(judgeScores.values))

        let durations = records.map(\.totalMs).sorted()

        return ModelRow(
            model: model,
            provider: provider,
            groupingScore: mean(grouped.map { $0.scores["groupingScore"] ?? 0 }),
            trapAvoidance: mean(grouped.map { $0.scores["trapAvoidance"] ?? 0 }),
            guidance: byType["insufficient_information"] ?? 0,
            guidanceTP: insufficient.reduce(0.0) { $0 + ($1.scores["guidanceTP"] ?? 0) },
            guidanceFP: insufficient.reduce(0.0) { $0 + ($1.scores["guidanceFP"] ?? 0) },
            guidanceFN: insufficient.reduce(0.0) { $0 + ($1.scores["guidanceFN"] ?? 0) },
            refusal: byType["non_goal_or_noise"] ?? 0,
            // 묶지 말아야 할 자리에서 실제로 묶지 않았나. `outcome` 으로 센다.
            restraint: mean(ungrouped.map { ($0.outcome == "noSuggestion" || $0.outcome == "guidance") ? 1.0 : 0.0 }),
            seconds: durations.isEmpty ? 0 : Double(durations[durations.count / 2]) / 1000,
            missingTP: missingTP,
            missingFP: missingFP,
            missingFN: missingFN,
            missingF1: missingF1,
            byType: byType,
            contextUp: deltas.filter { $0 > 0.001 }.count,
            contextFlat: deltas.filter { abs($0) <= 0.001 }.count,
            contextDown: deltas.filter { $0 < -0.001 }.count,
            contextMean: mean(deltas),
            parse: parse,
            judgeScores: judgeScores,
            judgeAverage: judgeAverage,
            judgeCount: judgeCount
        )
    }

    private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
