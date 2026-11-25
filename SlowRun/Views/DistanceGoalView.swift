import SwiftUI
import RunCore

struct DistanceGoalPicker: View {
    @EnvironmentObject private var settings: AppSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(RunLanguage.text("距离目标"), isOn: $settings.distanceGoalEnabled)
            if settings.distanceGoalEnabled {
                HStack(spacing: 8) {
                    ForEach([3000, 5000, 10000], id: \.self) { meters in
                        Button { settings.distanceGoalMeters = meters } label: {
                            Text(RunLanguage.text("%1$@ 公里", "\(meters / 1000)")).font(.subheadline).frame(maxWidth: .infinity, minHeight: 40)
                                .foregroundStyle(settings.distanceGoalMeters == meters ? Theme.teal : Theme.ink)
                                .background(RunPalette.raised, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain)
                    }
                }
                Picker(RunLanguage.text("目标公里数"), selection: $settings.distanceGoalMeters) {
                    ForEach(Array(stride(from: 1000, through: 20000, by: 500)), id: \.self) { meters in
                        Text(String(format: RunLanguage.text("%.1f 公里"), Double(meters) / 1000)).tag(meters)
                    }
                }.pickerStyle(.wheel).frame(height: 100).clipped()
                Text(RunLanguage.text("热身与正式训练计入目标。自由跑达标进入放松；有目的地时只提醒，继续带路。")).font(.caption).foregroundStyle(Theme.secondary)
            } else {
                Text(RunLanguage.text("不设置就无限循环跑走，准备好时手动结束。")).font(.caption).foregroundStyle(Theme.secondary)
            }
        }
    }
}

struct DistanceGoalProgressView: View {
    let record: WorkoutRecord
    @EnvironmentObject private var store: RunStore
    var body: some View {
        if let target = record.distanceGoalMeters {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(record.goalReached == true ? RunLanguage.text("距离目标已完成") : RunLanguage.text("距离目标")).foregroundStyle(Theme.teal)
                    Spacer()
                    Text(String(format: RunLanguage.text("%.2f / %.1f 公里"), record.goalProgressMeters / 1000, target / 1000)).monospacedDigit()
                }.font(.caption.weight(.medium))
                ProgressView(value: min(target, record.goalProgressMeters), total: target).tint(Theme.teal)
                HStack {
                    Text(RunLanguage.text("含热身，不含放松"))
                    Spacer()
                    if record.goalReached != true { Text(String(format: RunLanguage.text("还剩 %.2f 公里"), (record.goalRemainingMeters ?? 0) / 1000)) }
                    else if record.destinationWorkout == true { Text(RunLanguage.text("导航与训练继续")) }
                }.font(.caption2).foregroundStyle(Theme.secondary)
                if record.goalReached == true, record.goalContinued != true, record.destinationWorkout != true, record.stage.kind == .cooldown, record.status != .finished {
                    HStack(spacing: 10) {
                        Button(RunLanguage.text("继续训练")) { store.continueAfterGoal() }.buttonStyle(.bordered)
                        Button(RunLanguage.text("立即结束并保存")) { store.finish() }.buttonStyle(.bordered)
                    }.font(.caption).frame(maxWidth: .infinity)
                }
            }.padding(14).background(RunPalette.raised, in: RoundedRectangle(cornerRadius: 13))
        }
    }
}
