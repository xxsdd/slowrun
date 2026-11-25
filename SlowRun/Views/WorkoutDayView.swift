import SwiftUI
import RunCore

struct WorkoutDayView: View {
    let day: String
    @EnvironmentObject private var store: RunStore
    private var records: [WorkoutRecord] { (WorkoutDay.groups(store.history)[day] ?? []).sorted { $0.startedAt < $1.startedAt } }
    private var summary: DailyWorkoutSummary { DailyWorkoutSummary(records) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                Text(day).font(.caption).foregroundStyle(Theme.secondary)
                Text(records.count == 1 ? RunLanguage.text("今天，完成了一次。") : RunLanguage.text("今天，%1$@ 次出发。", "\(records.count)"))
                    .font(.system(size: 28, weight: .semibold))
                HStack {
                    Metric(value: String(format: "%.2f", summary.mainMeters / 1000), label: RunLanguage.text("正式训练 · 公里"), size: 36)
                    Metric(value: RunFormat.time(summary.mainSeconds), label: RunLanguage.text("正式训练用时"), size: 29)
                }.padding(.vertical, 8)
                Text(RunLanguage.text("含训练中的跑与走，热身与放松另计。")).font(.caption2).foregroundStyle(Theme.secondary)
                Divider().overlay(RunPalette.line)
                Text(RunLanguage.text("每次训练")).font(.headline)
                ForEach(records) { record in
                    NavigationLink { WorkoutDetailView(initialRecord: record) } label: { entry(record) }.buttonStyle(.plain)
                }
                if records.isEmpty {
                    Text(RunLanguage.text("当天没有训练记录。")).foregroundStyle(Theme.secondary)
                } else {
                    Divider().overlay(RunPalette.line)
                    DisclosureGroup(RunLanguage.text("全程与分阶段合计")) {
                        VStack(spacing: 15) {
                            DataRow(title: RunLanguage.text("全程 · 公里"), value: String(format: "%.2f", summary.meters / 1000))
                            DataRow(title: RunLanguage.text("全程用时"), value: RunFormat.time(summary.seconds))
                            DataRow(title: RunLanguage.text("估算热量 · 千卡"), value: summary.calories.map { String(format: "%.0f", $0) } ?? "—")
                            let stepValues = records.compactMap(\.totalSteps)
                            DataRow(title: stepValues.count == records.count ? RunLanguage.text("全程步数") : RunLanguage.text("已知部分步数"), value: stepValues.isEmpty ? "—" : "\(stepValues.reduce(0, +))")
                            ForEach(WorkoutPhase.allCases) { phase in
                                let values = records.compactMap { $0.phaseStatistics?[phase] }
                                if !values.isEmpty {
                                    DataRow(title: phase.title + (values.count == records.count ? "" : RunLanguage.text("（部分）")), value: String(format: RunLanguage.text("%.2f 公里 · "), values.reduce(0) { $0 + $1.meters } / 1000) + RunFormat.time(values.reduce(0) { $0 + $1.seconds }))
                                }
                            }
                            if summary.hasPartialCalories { Text(RunLanguage.text("部分记录没有热量，合计仅含已知数据。")).font(.caption2).foregroundStyle(Theme.secondary) }
                        }.padding(.top, 15)
                    }.tint(Theme.secondary)
                }
            }.padding(22)
        }.background(Theme.background).navigationTitle(RunLanguage.text("当天记录")).navigationBarTitleDisplayMode(.inline)
    }
    private func entry(_ record: WorkoutRecord) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(record.startedAt, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(Theme.secondary)
                        Text(record.title).font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                }
                HStack { Metric(value: String(format: "%.2f", record.mainMeters / 1000), label: RunLanguage.text("训练公里")); Metric(value: RunFormat.time(record.mainSeconds), label: RunLanguage.text("训练用时")) }
                RunWalkReviewMetrics(record: record)
                Divider().overlay(RunPalette.line)
                HStack {
                    Text(RunLanguage.text("查看分段"))
                    Spacer(); Image(systemName: "chevron.right")
                }.font(.caption).foregroundStyle(Theme.teal)
            }
        }.foregroundStyle(Theme.ink)
    }
}
