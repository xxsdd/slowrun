import SwiftUI
import Charts
import RunCore

private let reviewBlue = Color(red: 0.66, green: 0.79, blue: 0.94)
private let reviewAmber = Color(red: 0.93, green: 0.77, blue: 0.56)

/// Headings, paragraphs and inline emphasis stay distinct, including in old reports.
struct RunWalkReviewMetrics: View {
    let record: WorkoutRecord
    private var metrics: ReviewMetrics { ReviewMetrics(record) }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            column(.run, title: RunLanguage.text("跑步段"), tint: Theme.teal)
            column(.walk, title: RunLanguage.text("步行段"), tint: reviewBlue)
        }
    }
    private func column(_ kind: StageKind, title: String, tint: Color) -> some View {
        let meters = metrics.meters(kind)
        let seconds: Double? = metrics.intervals.isEmpty ? (kind == .run ? record.runSeconds : record.runSeconds.map { max(0, record.mainSeconds - $0) }) : metrics.seconds(kind)
        return VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: kind == .run ? "figure.run" : "figure.walk").font(.caption).foregroundStyle(tint)
            Text(meters.map { String(format: "%.2f", $0 / 1000) } ?? "—").font(.system(size: 29, weight: .semibold, design: .rounded)).foregroundStyle(tint).monospacedDigit()
            Text(RunLanguage.text("公里")).font(.caption2).foregroundStyle(Theme.secondary)
            Text(seconds.map { RunFormat.time($0) } ?? "—").font(.subheadline).monospacedDigit()
            if let meters, meters >= 20, let seconds, seconds >= 20 {
                Text(RunFormat.pace(seconds / meters * 1000) + RunLanguage.text(" / 公里")).font(.caption2).foregroundStyle(Theme.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(tint.opacity(0.16), lineWidth: 0.5))
    }
}

struct WorkoutIntervalsView: View {
    let record: WorkoutRecord
    private var metrics: ReviewMetrics { ReviewMetrics(record) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            RunWalkReviewMetrics(record: record)
            if let change = metrics.paceChange {
                VStack(alignment: .leading, spacing: 8) {
                    Text(RunLanguage.text("完整跑步段的前后变化")).font(.caption).foregroundStyle(Theme.secondary)
                    Text(abs(change) < 1 ? RunLanguage.text("前后 3 组配速接近") : RunLanguage.text("后 3 组每公里") + (change > 0 ? RunLanguage.text("慢了 ") : RunLanguage.text("快了 ")) + RunLanguage.text("%1$@ 秒", "\(Int(abs(change).rounded()))"))
                        .font(.title3.weight(.semibold)).foregroundStyle(reviewAmber)
                }
            }
            let runs = metrics.intervals.filter { $0.kind == .run && $0.meters != nil }
            if !runs.isEmpty {
                Text(RunLanguage.text("每组跑步距离")).font(.headline)
                Chart(runs) { span in
                    BarMark(x: .value(RunLanguage.text("分段"), String(span.id + 1)), y: .value(RunLanguage.text("米"), span.meters ?? 0))
                        .foregroundStyle(span.isComplete ? Theme.teal : reviewBlue)
                }.frame(height: 135).chartYAxisLabel(RunLanguage.text("米")).chartXAxis(.hidden)
            }
            if !metrics.intervals.isEmpty {
                DisclosureGroup(RunLanguage.text("查看跑走分段 · %1$@ 段", "\(metrics.intervals.count)")) {
                    VStack(spacing: 14) {
                        ForEach(metrics.intervals) { span in
                            HStack(alignment: .top) {
                                Text("\(span.id + 1) · " + (span.kind == .run ? RunLanguage.text("跑步") : RunLanguage.text("步行"))).foregroundStyle(span.kind == .run ? Theme.teal : reviewBlue)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(RunFormat.time(span.seconds) + " · " + (span.meters.map { String(format: RunLanguage.text("%.0f 米"), $0) } ?? RunLanguage.text("距离未保存")))
                                    if let pace = span.pace { Text(RunFormat.pace(pace) + RunLanguage.text(" / 公里")).font(.caption2).foregroundStyle(Theme.secondary) }
                                }
                            }.font(.caption).monospacedDigit()
                        }
                    }.padding(.top, 14)
                }.tint(Theme.secondary)
            }
            if metrics.reconstructed { Text(RunLanguage.text("旧记录的分段距离由已保存轨迹还原，并与训练总距离核对。")).font(.caption2).foregroundStyle(Theme.secondary) }
        }
    }
}
