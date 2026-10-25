import SwiftUI
import Charts
import RunCore

struct WorkoutDetailView: View {
    let initialRecord: WorkoutRecord
    @EnvironmentObject private var store: RunStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var reviewing = false
    @State private var reviewError: String?
    @State private var memoDraft = ""
    @State private var editingMemo = false
    private var record: WorkoutRecord { store.history.first { $0.id == initialRecord.id } ?? initialRecord }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(record.completionTitle).font(.caption.weight(.semibold)).foregroundStyle(record.isCompleted ? Theme.teal : Theme.secondary)
                Text(record.title).font(.system(size: 27, weight: .semibold))
                Text(record.startedAt, format: .dateTime.year().month().day().hour().minute()).font(.caption).foregroundStyle(Theme.secondary)
                HStack {
                    Metric(value: String(format: "%.2f", record.mainMeters / 1000), label: "正式训练 · 公里", size: 38)
                    Metric(value: RunFormat.time(record.mainSeconds), label: "正式训练用时", size: 32)
                }.padding(.vertical, 6)
                SurfaceCard { VStack(alignment: .leading, spacing: 20) { SecondaryMetrics(record: record); PhaseBreakdown(record: record) } }
                RouteMap(points: record.track).frame(height: 220)
                VStack(alignment: .leading, spacing: 12) {
                    Text("配速变化").font(.headline)
                    if record.paceSamples.count < 2 { Text("有效定位数据不足，暂时没有配速曲线。").font(.caption).foregroundStyle(.secondary) }
                    else {
                        Chart(record.paceSamples) { sample in
                            LineMark(x: .value("训练分钟", sample.elapsedSeconds / 60), y: .value("分钟每公里", sample.secondsPerKilometer / 60)).foregroundStyle(Theme.teal)
                        }.frame(height: 150).chartYAxisLabel("分钟/公里").chartXAxisLabel("主要训练分钟")
                    }
                    if record.plan.isBeginner { Text("计划内步行会使配速变慢，属于训练内容。").font(.caption).foregroundStyle(.secondary) }
                }
                if !record.laps.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("分段用时").font(.headline)
                        ForEach(record.laps) { lap in
                            HStack {
                                Text(lap.title)
                                Spacer()
                                Text(RunFormat.spokenTime(lap.seconds)).monospacedDigit()
                            }.font(.subheadline)
                        }
                        Text("每行是该段实际用时；总用时见顶部。热身与放松另计。").font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("今天跑下来怎么样？").font(.headline)
                    HStack {
                        ForEach(Effort.allCases) { effort in
                            Button { store.saveEffort(effort, for: record.id) } label: {
                                Text(effort.title).font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 13).contentShape(Rectangle())
                            }.buttonStyle(.plain).background(record.effort == effort ? Theme.pale : Theme.background, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(record.effort == effort ? Theme.teal : .secondary)
                        }
                    }
                }
                DisclosureGroup("补写一段简记", isExpanded: $editingMemo) {
                    VStack(alignment: .leading, spacing: 12) {
                        TextEditor(text: $memoDraft).frame(minHeight: 100).scrollContentBackground(.hidden).padding(10).background(RunPalette.raised, in: RoundedRectangle(cornerRadius: 12))
                        Button("保存简记") { store.saveMemo(memoDraft, for: record.id); editingMemo = false }.buttonStyle(.bordered)
                        Text("可以休息后再写；简记保存在手机，不会自动发给 AI。").font(.caption).foregroundStyle(Theme.secondary)
                    }.padding(.top, 12)
                }.tint(Theme.secondary)
                DisclosureGroup("本地训练提示") { Text(record.localReview).font(.subheadline).foregroundStyle(Theme.secondary).padding(.top, 10) }.tint(Theme.secondary)
                if let review = record.aiReview { NoteBox(title: "AI 复盘", text: review) }
                if let reviewError { Text(reviewError).font(.caption).foregroundStyle(.orange) }
                Button { requestReview() } label: {
                    HStack { if reviewing { ProgressView() }; Text(reviewing ? "正在生成复盘…" : "生成 AI 复盘") }.frame(maxWidth: .infinity).padding(.vertical, 14)
                }.buttonStyle(.bordered).disabled(reviewing || !settings.serviceConfigured)
                Text(settings.serviceConfigured ? "点击后仅发送本次统计和体感，不发送 GPS 路线。AI 建议供训练参考。" : "AI 服务尚未配置，本地规则复盘可正常使用。可在设置中连接服务。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("热量按体重和粗略活动强度估算，误差可能较大；不是实测值。")
                    .font(.caption2).foregroundStyle(.secondary)
                Button("删除这条训练记录", role: .destructive) { confirmingDelete = true }
                    .buttonStyle(.bordered).disabled(reviewing)
            }.padding(22)
        }.background(Theme.background).onAppear { memoDraft = record.memo ?? "" }.navigationTitle("训练详情").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("删除这条训练记录？", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("删除记录", role: .destructive) { if store.deleteWorkout(record.id) { dismiss() } }
                Button("取消", role: .cancel) { }
            } message: { Text("本次路线、数据和复盘会一并删除，无法撤销。") }
    }
    private func requestReview() {
        guard let endpoint = settings.endpoint, settings.serviceConfigured else { return }
        reviewing = true; reviewError = nil
        let value = record
        Task {
            defer { reviewing = false }
            do { let text = try await ServiceClient(baseURL: endpoint, token: settings.serviceToken).review(value); store.saveAI(text, for: value.id) }
            catch { reviewError = "AI 复盘未完成：\(error.localizedDescription) 本地规则复盘已保留。" }
        }
    }
}
