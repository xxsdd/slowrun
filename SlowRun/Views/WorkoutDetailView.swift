import SwiftUI
import Charts
import RunCore

struct WorkoutDetailView: View {
    let initialRecord: WorkoutRecord
    @EnvironmentObject private var store: RunStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmingDelete = false
    @State private var memoDraft = ""
    @State private var editingMemo = false
    private var record: WorkoutRecord { store.history.first { $0.id == initialRecord.id } ?? initialRecord }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(record.completionTitle).font(.caption.weight(.semibold)).foregroundStyle(record.isCompleted ? Theme.teal : Theme.secondary)
                Text(record.title).font(.system(size: 27, weight: .semibold))
                Text(record.startedAt, format: .dateTime.year().month().day().hour().minute()).font(.caption).foregroundStyle(Theme.secondary)
                if let awards = store.achievements.awards[record.id] {
                    WorkoutAwardsView(awards: awards, record: record)
                }
                HStack {
                    Metric(value: String(format: "%.2f", record.mainMeters / 1000), label: RunLanguage.text("正式训练 · 公里"), size: 38)
                    Metric(value: RunFormat.time(record.mainSeconds), label: RunLanguage.text("正式训练用时"), size: 32)
                }.padding(.vertical, 6)
                SurfaceCard { VStack(alignment: .leading, spacing: 20) { SecondaryMetrics(record: record); PhaseBreakdown(record: record) } }
                WorkoutIntervalsView(record: record)
                RouteMap(points: record.track).frame(height: 220)
                VStack(alignment: .leading, spacing: 12) {
                    Text(RunLanguage.text("配速变化")).font(.headline)
                    if record.paceSamples.count < 2 { Text(RunLanguage.text("有效定位数据不足，暂时没有配速曲线。")).font(.caption).foregroundStyle(.secondary) }
                    else {
                        Chart(record.paceSamples) { sample in
                            LineMark(x: .value(RunLanguage.text("训练分钟"), sample.elapsedSeconds / 60), y: .value(RunLanguage.text("分钟每公里"), sample.secondsPerKilometer / 60)).foregroundStyle(Theme.teal)
                        }.frame(height: 150).chartYAxisLabel(RunLanguage.text("分钟/公里")).chartXAxisLabel(RunLanguage.text("主要训练分钟"))
                    }
                    if record.plan.isBeginner { Text(RunLanguage.text("计划内步行会使配速变慢，属于训练内容。")).font(.caption).foregroundStyle(.secondary) }
                }
                if !record.laps.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(RunLanguage.text("分段用时")).font(.headline)
                        ForEach(record.laps) { lap in
                            HStack {
                                Text(lap.title)
                                Spacer()
                                Text(RunFormat.spokenTime(lap.seconds)).monospacedDigit()
                            }.font(.subheadline)
                        }
                        Text(RunLanguage.text("每行是该段实际用时；总用时见顶部。热身与放松另计。")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text(RunLanguage.text("今天跑下来怎么样？")).font(.headline)
                    HStack {
                        ForEach(Effort.allCases) { effort in
                            Button { store.saveEffort(effort, for: record.id) } label: {
                                Text(effort.title).font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 13).contentShape(Rectangle())
                            }.buttonStyle(.plain).background(record.effort == effort ? Theme.pale : Theme.background, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(record.effort == effort ? Theme.teal : .secondary)
                        }
                    }
                }
                DisclosureGroup(RunLanguage.text("补写一段简记"), isExpanded: $editingMemo) {
                    VStack(alignment: .leading, spacing: 12) {
                        TextEditor(text: $memoDraft).frame(minHeight: 100).scrollContentBackground(.hidden).padding(10).background(RunPalette.raised, in: RoundedRectangle(cornerRadius: 12))
                        Button(RunLanguage.text("保存简记")) { store.saveMemo(memoDraft, for: record.id); editingMemo = false }.buttonStyle(.bordered)
                        Text(RunLanguage.text("简记保存在这台手机上。")).font(.caption).foregroundStyle(Theme.secondary)
                    }.padding(.top, 12)
                }.tint(Theme.secondary)
                Divider().overlay(RunPalette.line)
                Text(RunLanguage.text("热量按体重和粗略活动强度估算，误差可能较大；不是实测值。"))
                    .font(.caption2).foregroundStyle(.secondary)
                Button(RunLanguage.text("删除这条训练记录"), role: .destructive) { confirmingDelete = true }
                    .buttonStyle(.bordered)
            }.padding(22)
        }.background(Theme.background).onAppear { memoDraft = record.memo ?? "" }.navigationTitle(RunLanguage.text("训练详情")).navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(RunLanguage.text("删除这条训练记录？"), isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button(RunLanguage.text("删除记录"), role: .destructive) { if store.deleteWorkout(record.id) { dismiss() } }
                Button(RunLanguage.text("取消"), role: .cancel) { }
            } message: { Text(RunLanguage.text("本次路线与数据会一并删除，无法撤销。")) }
    }
}
