import ActivityKit
import Foundation
import RunCore

@MainActor final class LiveActivityCoordinator {
    private var activity: Activity<RunActivityAttributes>?
    private var lastUpdate = Date.distantPast
    private var updateTask: Task<Void, Never>?
    private(set) var message: String?
    func sync(_ record: WorkoutRecord, navigation: NavigationCoordinator? = nil, force: Bool = false) {
        if record.status == .finished { end(); return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { message = RunLanguage.text("系统未开启实时活动，跑步记录不受影响"); return }
        guard force || Date().timeIntervalSince(lastUpdate) >= 5 else { return }
        lastUpdate = Date()
        let isRunning = record.status == .active
        var state = RunActivityAttributes.ContentState(distance: record.currentPhaseMeters.map { String(format: "%.2f", $0 / 1_000) } ?? "—", pace: RunFormat.pace(record.currentPace), elapsed: RunFormat.time(record.currentPhaseSeconds), timerStart: Date().addingTimeInterval(-record.currentPhaseSeconds), timerRunning: isRunning, stage: record.stage.kind.title, paused: record.status == .paused, includesWalking: record.plan.isBeginner)
        state.english = RunLanguage.isEnglish
        state.stageRemainingSeconds = record.stageRemainingSeconds
        state.stageEndsAt = record.status == .active ? record.stageRemainingSeconds.map { Date().addingTimeInterval($0) } : nil
        state.remainingDistance = record.stage.kind == .run ? record.plan.targetMeters.map { String(format: RunLanguage.text("剩余 %.2f 公里"), max(0, $0 - record.mainMeters) / 1_000) } : nil
        state.phaseLabel = record.currentPhase.metricTitle
        state.stageSymbol = record.stage.kind == .run ? "figure.run" : "figure.walk"
        if let navigation, navigation.showsNavigation {
            state.navTitle = String(navigation.instructionTitle.prefix(40))
            state.navDetail = String(navigation.instructionDetail.prefix(70))
            state.navSymbol = navigation.nextSymbol
            if navigation.state == .arrived { state.navRemaining = RunLanguage.text("导航结束 · 训练继续") }
            else if navigation.state == .rerouting || navigation.state == .waiting || navigation.state == .failed { state.navRemaining = RunLanguage.text("路线更新中") }
            else { state.navRemaining = navigation.remainingMeters.map { String(format: RunLanguage.text("距目的地 %.2f 公里"), $0 / 1000) } }
            if let engine = navigation.engine, let position = engine.position, navigation.locationReliable,
               navigation.state == .navigating,
               let map = NavigationLocalMap(route: engine.route, progress: engine.progress, position: position,
                                            bearing: navigation.bearing ?? 0, turnProgress: engine.nextManeuver?.metersFromStart) {
                state.navRoute = map.points.map { RunMiniPoint(x: $0.x, y: $0.y) }
                state.navPosition = RunMiniPoint(x: map.position.x, y: map.position.y)
                state.navTurn = map.turn.map { RunMiniPoint(x: $0.x, y: $0.y) }
                state.navDirectionKnown = navigation.bearing != nil
                if let step = engine.nextManeuver, let meters = engine.maneuverRemaining {
                    state.navTurnDistance = meters <= 15 ? RunLanguage.text("路口") : meters < 1000 ? RunLanguage.text("%1$@米", "\(max(10, Int((meters / 10).rounded()) * 10))") : String(format: RunLanguage.text("%.1f公里"), meters / 1000)
                    switch step.turn {
                    case .left: state.navTurnLabel = RunLanguage.text("前方左转")
                    case .right: state.navTurnLabel = RunLanguage.text("前方右转")
                    case .uTurn: state.navTurnLabel = RunLanguage.text("前方掉头")
                    case .straight: state.navTurnLabel = RunLanguage.text("沿路直行")
                    case .unknown: state.navTurnLabel = RunLanguage.text("查看路口指引")
                    }
                }
            }
        }
        if ((try? JSONEncoder().encode(state).count) ?? 4097) > 3800 { state.navRoute = nil; state.navPosition = nil; state.navDetail = nil }
        guard ((try? JSONEncoder().encode(state).count) ?? 4097) < 4096 else { message = RunLanguage.text("锁屏信息过多，地图导航与记录继续"); return }
        let stale = (record.lastGPSAt ?? Date()).addingTimeInterval(15)
        let content = ActivityContent(state: state, staleDate: stale)
        if activity == nil { activity = Activity<RunActivityAttributes>.activities.first { $0.attributes.workoutID == record.id.uuidString } }
        if let activity {
            updateTask?.cancel()
            updateTask = Task { await activity.update(content) }
        } else {
            do { activity = try Activity.request(attributes: RunActivityAttributes(workoutID: record.id.uuidString, title: record.title), content: content, pushType: nil); message = nil }
            catch { message = RunLanguage.text("锁屏卡片暂时无法开启，跑步记录继续") }
        }
    }
    func end() {
        updateTask?.cancel(); updateTask = nil
        let activities = Activity<RunActivityAttributes>.activities
        activity = nil
        Task { for item in activities { await item.end(nil, dismissalPolicy: .immediate) } }
    }
}
