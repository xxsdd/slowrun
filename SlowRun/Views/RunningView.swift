import SwiftUI
import RunCore

struct RunningView: View {
    @EnvironmentObject private var store: RunStore
    @State private var confirmFinish = false
    var body: some View {
        ScrollView {
            if let record = store.record {
                VStack(alignment: .leading, spacing: 22) {
                    if store.recoveryNotice { NoteBox(title: "已找回训练", text: "目前暂停，中断期间没有补算距离和时间。") }
                    HStack {
                        ForEach(WorkoutPhase.allCases) { phase in
                            Text(phase.title).font(.caption.weight(phase == record.currentPhase ? .semibold : .regular))
                                .foregroundStyle(phase == record.currentPhase ? Theme.teal : Theme.secondary)
                            if phase != .cooldown { Spacer() }
                        }
                    }.padding(.top, 6)
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(record.title).font(.caption).foregroundStyle(Theme.secondary)
                            Text(record.status == .paused ? "已暂停" : record.stage.kind.title).font(.title2.weight(.semibold))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 5) {
                            Text(record.stageRemainingSeconds.map { RunFormat.time($0) } ?? "∞").font(.title2.weight(.medium)).monospacedDigit()
                            Text(record.status == .paused ? "倒计时已暂停" : "本段剩余").font(.caption2).foregroundStyle(Theme.secondary)
                        }
                    }
                    TrainingMetrics(distance: record.currentPhaseMeters.map { String(format: "%.2f", $0 / 1000) } ?? "—", pace: RunFormat.pace(record.currentPace), elapsed: RunFormat.time(record.currentPhaseSeconds), phase: record.currentPhase.metricTitle)
                    HStack {
                        Text("当前步频").font(.subheadline).foregroundStyle(Theme.secondary)
                        Spacer()
                        Text(record.cadence.map { String(format: "%.0f", $0) } ?? "—").font(.title2.weight(.semibold)).monospacedDigit()
                        Text("步 / 分").font(.caption).foregroundStyle(Theme.secondary)
                    }
                    RouteMap(points: record.track).frame(height: 170)
                    Text(store.locationMessage).font(.caption).foregroundStyle(Theme.secondary)
                    if !store.lastCue.isEmpty { Label(store.lastCue, systemImage: "waveform").font(.subheadline).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) }
                    HStack(spacing: 12) {
                        PrimaryButton(title: record.status == .paused ? "继续" : "暂停", symbol: record.status == .paused ? "play.fill" : "pause.fill") { store.togglePause() }
                        Button { confirmFinish = true } label: {
                            Text("结束训练").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 54).foregroundStyle(Theme.ink).background(RunPalette.raised, in: RoundedRectangle(cornerRadius: 17)).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    if record.status == .active && [.warmup, .cooldown].contains(record.stage.kind) {
                        Button(record.stage.kind == .warmup ? "跳过热身" : "结束放松，保存训练") { store.skipPreparation() }
                            .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    SurfaceCard { VStack(alignment: .leading, spacing: 18) { SecondaryMetrics(record: record); PhaseBreakdown(record: record) } }
                    if let live = store.liveMessage { Text(live).font(.caption).foregroundStyle(Theme.secondary) }
                }.padding(22)
            }
        }.background(Theme.background).navigationTitle("训练中").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("结束本次训练", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("立即结束并保存") { store.finish() }
            if store.record?.stage.kind != .cooldown { Button("步行放松 5 分钟") { store.beginCooldown() } }
            Button("继续训练", role: .cancel) { }
        }
    }
}
struct SecondaryMetrics: View {
    let record: WorkoutRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DataRow(title: "全程距离 / 用时", value: String(format: "%.2f 公里 · ", record.totalMeters / 1000) + RunFormat.time(record.elapsedSeconds))
            HStack {
                Metric(value: record.calories.map { String(Int($0)) } ?? "—", label: "全程估算活动热量 · 千卡", size: 29)
                Metric(value: record.totalSteps.map { $0.formatted() } ?? "—", label: "全程总步数", size: 29)
            }
            if record.totalSteps == nil { Text(record.phaseStatistics == nil ? "旧版未记录全程步数" : "步数尚未获取；请允许运动与健身权限").font(.caption).foregroundStyle(Theme.secondary) }
            Text(record.calories == nil ? "填写体重后估算活动热量" : record.status == .finished ? "热量为粗略活动消耗估算。" : "热量为粗略活动消耗估算；步数将在结束时核对。").font(.caption).foregroundStyle(Theme.secondary)
        }
    }
}
