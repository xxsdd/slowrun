import ActivityKit
import Foundation
import RunCore

@MainActor final class LiveActivityCoordinator {
    private var activity: Activity<RunActivityAttributes>?
    private var lastUpdate = Date.distantPast
    private var updateTask: Task<Void, Never>?
    private(set) var message: String?
    func sync(_ record: WorkoutRecord, force: Bool = false) {
        if record.status == .finished { end(); return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { message = "系统未开启实时活动，跑步记录不受影响"; return }
        guard force || Date().timeIntervalSince(lastUpdate) >= 5 else { return }
        lastUpdate = Date()
        let isRunning = record.status == .active
        var state = RunActivityAttributes.ContentState(distance: record.currentPhaseMeters.map { String(format: "%.2f", $0 / 1_000) } ?? "—", pace: RunFormat.pace(record.currentPace), elapsed: RunFormat.time(record.currentPhaseSeconds), timerStart: Date().addingTimeInterval(-record.currentPhaseSeconds), timerRunning: isRunning, stage: record.stage.kind.title, paused: record.status == .paused, includesWalking: record.plan.isBeginner)
        state.stageRemainingSeconds = record.stageRemainingSeconds
        state.stageEndsAt = record.status == .active ? record.stageRemainingSeconds.map { Date().addingTimeInterval($0) } : nil
        state.remainingDistance = record.stage.kind == .run ? record.plan.targetMeters.map { String(format: "剩余 %.2f 公里", max(0, $0 - record.mainMeters) / 1_000) } : nil
        state.phaseLabel = record.currentPhase.metricTitle
        state.stageSymbol = record.stage.kind == .run ? "figure.run" : "figure.walk"
        let stale = (record.lastGPSAt ?? Date()).addingTimeInterval(15)
        let content = ActivityContent(state: state, staleDate: stale)
        if activity == nil { activity = Activity<RunActivityAttributes>.activities.first { $0.attributes.workoutID == record.id.uuidString } }
        if let activity {
            updateTask?.cancel()
            updateTask = Task { await activity.update(content) }
        } else {
            do { activity = try Activity.request(attributes: RunActivityAttributes(workoutID: record.id.uuidString, title: record.title), content: content, pushType: nil); message = nil }
            catch { message = "锁屏卡片暂时无法开启，跑步记录继续" }
        }
    }
    func end() {
        updateTask?.cancel(); updateTask = nil
        let activities = Activity<RunActivityAttributes>.activities
        activity = nil
        Task { for item in activities { await item.end(nil, dismissalPolicy: .immediate) } }
    }
}
