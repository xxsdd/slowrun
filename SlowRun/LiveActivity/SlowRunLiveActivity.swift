import ActivityKit
import SwiftUI
import WidgetKit

@main struct SlowRunWidgets: WidgetBundle {
    var body: some Widget { SlowRunLiveActivity() }
}
struct SlowRunLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(context.state.stage + (context.state.paused ? " · 暂停" : ""))
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(mint).lineLimit(1)
                    Spacer(minLength: 6)
                    HStack(spacing: 4) { Text("剩余").font(.caption2); remaining(context.state).font(.system(size: 13, weight: .semibold)).monospacedDigit().frame(maxWidth: 95, alignment: .trailing) }.foregroundStyle(ink)
                }
                HStack(alignment: .top, spacing: 10) {
                    metric(context.state.distance, label: (context.state.phaseLabel ?? "训练") + "距离 · 公里")
                    metric(context.isStale ? "—" : context.state.pace, label: "当前配速", color: mint)
                    VStack(alignment: .leading, spacing: 6) {
                        Text((context.state.phaseLabel ?? "训练") + "用时").font(.system(size: 10, weight: .medium)).foregroundStyle(caption).lineLimit(1)
                        elapsed(context.state).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(ink).minimumScaleFactor(0.5).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            // Explicit colors on an opaque surface: Lock Screen dark mode must
            // never turn semantic .primary text white on a fixed pale background.
            .background(surface)
            .activityBackgroundTint(surface)
            .activitySystemActionForegroundColor(ink)
            .widgetURL(URL(string: "slowrun://run"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label(context.state.distance + " km", systemImage: "figure.run").font(.headline).foregroundStyle(ink) }
                DynamicIslandExpandedRegion(.trailing) { Text(context.isStale ? "—" : context.state.pace).font(.headline).foregroundStyle(mint) }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack { Text(context.state.stage + (context.state.paused ? " · 暂停" : " · 剩余")); remaining(context.state); Spacer(); elapsed(context.state).monospacedDigit() }.font(.caption).foregroundStyle(ink)
                }
            } compactLeading: {
                Image(systemName: context.state.stageSymbol ?? "figure.run").foregroundStyle(mint)
            } compactTrailing: {
                remaining(context.state).font(.caption.monospacedDigit()).frame(maxWidth: 64).foregroundStyle(ink)
            } minimal: {
                Image(systemName: context.state.stageSymbol ?? "figure.run").foregroundStyle(mint)
            }
            .widgetURL(URL(string: "slowrun://run"))
            .keylineTint(mint)
        }
    }
    private var surface: Color { RunPalette.surface }
    private var ink: Color { RunPalette.text }
    private var caption: Color { RunPalette.secondary }
    private var mint: Color { RunPalette.mint }
    private func metric(_ value: String, label: String, color: Color = RunPalette.text) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(caption).lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.5)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private func remaining(_ state: RunActivityAttributes.ContentState) -> some View {
        if let end = state.stageEndsAt {
            if end > Date() { Text(timerInterval: Date()...end, countsDown: true, showsHours: false) }
            else { Text("00:00") }
        } else if let seconds = state.stageRemainingSeconds {
            Text(String(format: "%02d:%02d", max(0, Int(seconds.rounded(.up))) / 60, max(0, Int(seconds.rounded(.up))) % 60))
        } else { Text(state.remainingDistance ?? "∞").font(.caption).lineLimit(1).minimumScaleFactor(0.6) }
    }
    @ViewBuilder private func elapsed(_ state: RunActivityAttributes.ContentState) -> some View {
        if state.timerRunning { Text(timerInterval: state.timerStart...Date.distantFuture, countsDown: false) }
        else { Text(state.elapsed) }
    }
}
