import SwiftUI
import SwiftData

struct StatsPage: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage(Constants.AppStorageKey.timelineStartHour)
    private var timelineStartHour: Int = Constants.defaultTimelineStartHour
    @AppStorage(Constants.AppStorageKey.timelineEndHour)
    private var timelineEndHour: Int = Constants.defaultTimelineEndHour
    @AppStorage(Constants.AppStorageKey.timelineBucketMinutes)
    private var timelineBucketMinutes: Int = Constants.defaultTimelineBucketMinutes

    @State private var trackerStore = TrackerStateStore.shared
    @State private var retention: String = "90"
    @State private var weeklyReport: Bool = false

    @State private var showAddVacation: Bool = false
    @State private var newVacationStart: Date = Date()
    @State private var newVacationEnd: Date = Date()
    @State private var newVacationLabel: String = ""
    @State private var newVacationDeletesExisting: Bool = false

    var body: some View {
        SettingsPageScroll {
            SettingsPageHeader(title: SettingsTab.stats.label, subtitle: SettingsTab.stats.subtitle)

            SettingsGroupCard("타임라인 표시") {
                SettingsRow("시작 시간", subtitle: "일간 차트의 시작 시각") {
                    Picker("", selection: $timelineStartHour) {
                        ForEach(0..<24, id: \.self) { h in
                            Text("\(h)시").tag(h)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 80)
                }
                SettingsRow("종료 시간", subtitle: "일간 차트의 종료 시각") {
                    Picker("", selection: $timelineEndHour) {
                        ForEach(1...24, id: \.self) { h in
                            Text(h == 24 ? "24시" : "\(h)시").tag(h)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 80)
                }
                SettingsRow("시간 간격", subtitle: "버킷 단위") {
                    Picker("", selection: $timelineBucketMinutes) {
                        ForEach(Constants.timelineBucketMinuteOptions, id: \.self) { m in
                            Text("\(m)분").tag(m)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 80)
                }

                if timelineStartHour >= timelineEndHour {
                    Text("⚠️ 시작 시간이 종료 시간보다 늦거나 같습니다")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }
            }

            trackingCard
            vacationCard

            SettingsGroupCard("보관") {
                SettingsRow(
                    "데이터 보관 기간",
                    subtitle: "기간이 지난 기록은 자동 삭제됩니다.",
                    comingSoon: true
                ) {
                    Picker("", selection: $retention) {
                        Text("30일").tag("30")
                        Text("90일").tag("90")
                        Text("365일").tag("365")
                        Text("영구").tag("forever")
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
                SettingsRow(
                    "주간 리포트 자동 생성",
                    subtitle: "매주 월요일 오전 9시에 지난주 통계를 마크다운으로 저장합니다.",
                    comingSoon: true
                ) {
                    Toggle("", isOn: $weeklyReport).labelsHidden()
                }
            }
        }
        .sheet(isPresented: $showAddVacation, onDismiss: resetVacationForm) {
            addVacationSheet
        }
    }

    // MARK: - 추적 카드

    private var trackingCard: some View {
        SettingsGroupCard("추적") {
            SettingsRow(
                "앱 사용 시간 추적",
                subtitle: "활성 앱과 브라우저 호스트를 기록해 카테고리별 통계로 보여줍니다. 민감한 작업을 할 때나 휴가 기간 동안 기록을 남기고 싶지 않다면 이 스위치 또는 아래 옵션으로 잠시 끌 수 있어요."
            ) {
                Toggle("", isOn: Binding(
                    get: { trackerStore.isTrackingEnabled },
                    set: { trackerStore.isTrackingEnabled = $0 }
                ))
                .labelsHidden()
            }

            SettingsRow(
                "민감 작업 모드",
                subtitle: "지금부터 끌 때까지 기록을 일시 중단합니다. 이 모드 동안의 시간은 통계에 남지 않아요."
            ) {
                if trackerStore.isSensitiveMode {
                    Label("기록 중지 중", systemImage: "eye.slash")
                        .font(.caption2)
                        .foregroundStyle(SettingsTheme.accent)
                }
                Toggle("", isOn: Binding(
                    get: { trackerStore.isSensitiveMode },
                    set: { trackerStore.isSensitiveMode = $0 }
                ))
                .labelsHidden()
            }

            SettingsRow(
                "전체 추적 상태",
                subtitle: trackerStore.shouldRecord()
                    ? "지금 기록이 진행되고 있습니다."
                    : "현재 기록이 중단된 상태입니다 (전체 OFF · 민감 작업 · 휴가 중 하나)."
            ) {
                Circle()
                    .fill(trackerStore.shouldRecord() ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(trackerStore.shouldRecord() ? "기록 중" : "중단됨")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(trackerStore.shouldRecord() ? .green : .secondary)
            }
        }
    }

    // MARK: - 휴가 카드

    private var vacationCard: some View {
        SettingsGroupCard("휴가 기간") {
            VStack(spacing: 0) {
                Text("등록한 기간 동안에는 기록이 자동으로 중단되고, 통계 상세 보기의 일간 / 주간 / 월간 화면에서 해당 날짜가 \"휴가\" 로 표시됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 4)

                if trackerStore.vacationRanges.isEmpty {
                    Text("등록된 휴가 기간이 없습니다")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                } else {
                    ForEach(trackerStore.vacationRanges) { range in
                        vacationRow(range)
                    }
                }

                HStack {
                    Button {
                        let cal = Calendar.current
                        newVacationStart = cal.startOfDay(for: Date())
                        newVacationEnd = cal.startOfDay(for: Date())
                        newVacationLabel = ""
                        newVacationDeletesExisting = false
                        showAddVacation = true
                    } label: {
                        Label("휴가 기간 추가", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    private func vacationRow(_ range: VacationRange) -> some View {
        SettingsRow(
            range.label.isEmpty ? "휴가" : "🏖️ \(range.label)",
            subtitle: "\(Self.dayFormatter.string(from: range.start)) ~ \(Self.dayFormatter.string(from: range.end)) · \(range.dayCount)일"
        ) {
            Button(role: .destructive) {
                trackerStore.removeVacation(id: range.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help("이 휴가 기간 삭제")
        }
    }

    private var addVacationSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("휴가 기간 추가")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("라벨 (선택)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("예: 여름휴가", text: $newVacationLabel)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("시작")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DatePicker("", selection: $newVacationStart, displayedComponents: .date)
                        .labelsHidden()
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("종료")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DatePicker("", selection: $newVacationEnd, in: newVacationStart..., displayedComponents: .date)
                        .labelsHidden()
                }
            }

            let count = existingRecordCount(start: newVacationStart, end: newVacationEnd)
            if count > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("이 기간에 작업 기록이 \(count)건 있어요")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.orange)
                    Picker("", selection: $newVacationDeletesExisting) {
                        Text("기존 기록 그대로 두기").tag(false)
                        Text("기존 기록 삭제").tag(true)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    Text(newVacationDeletesExisting
                         ? "이 기간의 앱 사용 / 집중 세션 기록이 모두 삭제됩니다. 되돌릴 수 없어요."
                         : "기록은 그대로 보존되고, 통계 화면에서는 휴가 안내 배너로 표시됩니다.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.25), lineWidth: 0.5)
                )
            }

            HStack {
                Spacer()
                Button("취소") {
                    showAddVacation = false
                }
                Button("추가") {
                    if newVacationDeletesExisting {
                        deleteRecords(start: newVacationStart, end: newVacationEnd)
                    }
                    trackerStore.addVacation(
                        start: newVacationStart,
                        end: newVacationEnd,
                        label: newVacationLabel
                    )
                    showAddVacation = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func resetVacationForm() {
        newVacationLabel = ""
        newVacationDeletesExisting = false
    }

    // MARK: - 기록 조회 / 삭제

    private func dateBounds(start: Date, end: Date) -> (Date, Date) {
        let cal = Calendar.current
        let s = cal.startOfDay(for: start)
        let e = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: end)) ?? end
        return (s, e)
    }

    private func existingRecordCount(start: Date, end: Date) -> Int {
        let (s, e) = dateBounds(start: start, end: end)
        let recordDescriptor = FetchDescriptor<AppUsageRecord>(
            predicate: #Predicate { $0.date >= s && $0.date < e }
        )
        let segmentDescriptor = FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate { $0.startTime >= s && $0.startTime < e }
        )
        let focusDescriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.startedAt >= s && $0.startedAt < e }
        )
        let recordCount = (try? modelContext.fetch(recordDescriptor).count) ?? 0
        let segmentCount = (try? modelContext.fetch(segmentDescriptor).count) ?? 0
        let focusCount = (try? modelContext.fetch(focusDescriptor).count) ?? 0
        return recordCount + segmentCount + focusCount
    }

    private func deleteRecords(start: Date, end: Date) {
        let (s, e) = dateBounds(start: start, end: end)
        let recordDescriptor = FetchDescriptor<AppUsageRecord>(
            predicate: #Predicate { $0.date >= s && $0.date < e }
        )
        let segmentDescriptor = FetchDescriptor<AppUsageSegment>(
            predicate: #Predicate { $0.startTime >= s && $0.startTime < e }
        )
        let focusDescriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.startedAt >= s && $0.startedAt < e }
        )
        for record in (try? modelContext.fetch(recordDescriptor)) ?? [] {
            modelContext.delete(record)
        }
        for segment in (try? modelContext.fetch(segmentDescriptor)) ?? [] {
            modelContext.delete(segment)
        }
        for session in (try? modelContext.fetch(focusDescriptor)) ?? [] {
            modelContext.delete(session)
        }
        try? modelContext.save()
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy년 M월 d일 (E)"
        return f
    }()
}
