import ActivityKit
import SwiftUI
import WidgetKit

@main struct SlowRunWidgets: WidgetBundle {
    var body: some Widget { SlowRunLiveActivity() }
}
struct SlowRunLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            if context.state.navTitle != nil {
                navigationCard(context.state, stale: context.isStale)
                    .activityBackgroundTint(surface).activitySystemActionForegroundColor(ink).widgetURL(URL(string: "slowrun://run"))
            } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(context.state.stage + (context.state.paused ? (context.state.english == true ? " · Paused" : " · 暂停") : ""))
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(mint).lineLimit(1)
                    Spacer(minLength: 6)
                    HStack(spacing: 4) { Text((context.state.english == true ? "Time left" : "剩余")).font(.caption2); remaining(context.state).font(.system(size: 13, weight: .semibold)).monospacedDigit().frame(maxWidth: 95, alignment: .trailing) }.foregroundStyle(ink)
                }
                HStack(alignment: .top, spacing: 10) {
                    metric(context.state.distance, label: (context.state.phaseLabel ?? (context.state.english == true ? "Training" : "训练")) + (context.state.english == true ? " distance · km" : "距离 · 公里"))
                    metric(context.isStale ? "—" : context.state.pace, label: (context.state.english == true ? "Current pace" : "当前配速"), color: mint)
                    VStack(alignment: .leading, spacing: 6) {
                        Text((context.state.phaseLabel ?? (context.state.english == true ? "Training" : "训练")) + (context.state.english == true ? " time" : "用时")).font(.system(size: 10, weight: .medium)).foregroundStyle(caption).lineLimit(1)
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
            }
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label(context.state.distance + " km", systemImage: "figure.run").font(.headline).foregroundStyle(ink) }
                DynamicIslandExpandedRegion(.trailing) { Text(context.isStale ? "—" : context.state.pace).font(.headline).foregroundStyle(mint) }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        if let title = context.state.navTitle { Label(title, systemImage: context.state.navSymbol ?? "location").foregroundStyle(mint) }
                        HStack { Text(context.state.stage + (context.state.paused ? (context.state.english == true ? " · Paused" : " · 暂停") : (context.state.english == true ? " · Left" : " · 剩余"))); remaining(context.state); Spacer(); elapsed(context.state).monospacedDigit() }.foregroundStyle(ink)
                    }.font(.caption)
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
    private func navigationCard(_ state: RunActivityAttributes.ContentState, stale: Bool) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(state.stage + (state.paused ? (state.english == true ? " · Paused" : " · 暂停") : "")).font(.system(size: 10, weight: .semibold)).foregroundStyle(mint).lineLimit(1)
                Spacer(minLength: 5)
                HStack(spacing: 3) { Text((state.english == true ? "Time left" : "本段剩余")); remaining(state) }.font(.system(size: 10)).monospacedDigit().foregroundStyle(ink).frame(maxWidth: 115, alignment: .trailing)
            }.frame(height: 14)
            HStack(spacing: 12) {
                RunMiniRouteView(points: state.navRoute ?? [], position: stale ? nil : state.navPosition,
                                 turn: stale ? nil : state.navTurn, directionKnown: state.navDirectionKnown == true)
                    .frame(width: 148, height: 78).opacity(stale ? 0.35 : 1)
                VStack(alignment: .leading, spacing: 4) {
                    if !stale, !state.paused, let distance = state.navTurnDistance {
                        HStack(spacing: 7) {
                            Image(systemName: state.navSymbol ?? "map").font(.system(size: 25, weight: .semibold)).foregroundStyle(mint)
                            Text(distance).font(.system(size: 29, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.65)
                        }
                        Text(state.navTurnLabel ?? (state.english == true ? "Follow the route" : "沿路线继续")).font(.system(size: 13, weight: .semibold)).foregroundStyle(ink).lineLimit(1)
                    } else {
                        Text(state.paused ? (state.english == true ? "Workout paused" : "训练已暂停") : stale ? (state.english == true ? "Waiting for GPS" : "等待定位更新") : state.navTitle ?? (state.english == true ? "Follow the route" : "沿路线继续"))
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(ink).lineLimit(2).minimumScaleFactor(0.8)
                    }
                    Text(state.navRemaining ?? (state.english == true ? "Locating…" : "定位更新中")).font(.system(size: 11, weight: .medium)).foregroundStyle(caption).lineLimit(1).minimumScaleFactor(0.8)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Rectangle().fill(RunPalette.line).frame(height: 0.5)
            HStack(alignment: .top, spacing: 8) {
                navMetric(state.distance, label: (state.phaseLabel ?? (state.english == true ? "Training" : "训练")) + (state.english == true ? " distance · km" : "距离 · 公里"))
                navMetric(stale ? "—" : state.pace, label: (state.english == true ? "Current pace" : "当前配速"), accent: true)
                VStack(alignment: .leading, spacing: 2) {
                    elapsed(state).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.6)
                    Text((state.phaseLabel ?? (state.english == true ? "Training" : "训练")) + (state.english == true ? " time" : "用时")).font(.system(size: 9)).foregroundStyle(caption)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 37)
        }.padding(.horizontal, 12).frame(height: 160).background(surface)
    }
    private func navMetric(_ value: String, label: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(accent ? mint : ink).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 9)).foregroundStyle(caption).lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
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
