import Foundation

public enum WorkoutPhase: String, Codable, CaseIterable, Identifiable, Sendable {
    case warmup, main, cooldown
    public var id: String { rawValue }
    public var title: String { switch self { case .warmup: return "热身"; case .main: return "正式训练"; case .cooldown: return "放松" } }
    public var metricTitle: String { self == .main ? "训练" : title }
}
extension StageKind {
    public var phase: WorkoutPhase { switch self { case .warmup: return .warmup; case .cooldown: return .cooldown; default: return .main } }
}
public struct PhaseTotal: Codable, Sendable {
    public var seconds: Double = 0
    public var meters: Double = 0
    public var steps: Int? = nil
    public var calories: Double? = nil
    public init() {}
}
public struct PhaseStatistics: Codable, Sendable {
    public var warmup = PhaseTotal()
    public var main = PhaseTotal()
    public var cooldown = PhaseTotal()
    public init() {}
    public subscript(_ phase: WorkoutPhase) -> PhaseTotal {
        get { switch phase { case .warmup: return warmup; case .main: return main; case .cooldown: return cooldown } }
        set { switch phase { case .warmup: warmup = newValue; case .main: main = newValue; case .cooldown: cooldown = newValue } }
    }
    public var totalSteps: Int? {
        let values = WorkoutPhase.allCases.map { self[$0] }
        guard values.filter({ $0.seconds > 0 }).allSatisfy({ $0.steps != nil }), values.contains(where: { $0.steps != nil }) else { return nil }
        return values.reduce(0) { $0 + ($1.steps ?? 0) }
    }
}
public struct ActivitySpan: Codable, Sendable {
    public var start: Date
    public var end: Date
    public var kind: StageKind
    public var seconds: Double { max(0, end.timeIntervalSince(start)) }
    public init(start: Date, end: Date, kind: StageKind) { self.start = start; self.end = end; self.kind = kind }
}

/// Independent progress survives removal of individual training records.
public struct CourseProgress: Codable, Sendable {
    public private(set) var completed: Set<Int> = []
    public init(records: [WorkoutRecord] = []) { for record in records { register(record) } }
    public var nextIndex: Int { (0..<27).first { !completed.contains($0) } ?? 27 }
    public var finished: Bool { nextIndex == 27 }
    public var plan: WorkoutPlan { WorkoutPlan.beginnerWeeks[min(nextIndex, 26) / 3] }
    public var session: Int { min(nextIndex, 26) % 3 + 1 }
    public mutating func register(_ record: WorkoutRecord) {
        guard record.status == .finished, record.isCompleted, let week = record.plan.week else { return }
        completed.insert((week - 1) * 3 + min(3, max(1, record.session ?? 1)) - 1)
    }
}

extension WorkoutRecord {
    public var currentPhase: WorkoutPhase { stage.kind.phase }
    public var currentPhaseSeconds: Double { phaseStatistics?[currentPhase].seconds ?? (currentPhase == .main ? mainSeconds : stageSeconds) }
    public var currentPhaseMeters: Double? { phaseStatistics?[currentPhase].meters ?? (currentPhase == .main ? mainMeters : nil) }
    public var totalSteps: Int? { phaseStatistics?.totalSteps }
    public var isCompleted: Bool {
        if statisticsVersion != nil { return completedPlan }
        guard mainSeconds > 0 || mainMeters > 0 else { return false }
        if plan == .freeRun { return true }
        if let target = plan.targetMeters { return mainMeters >= target || (stage.kind == .cooldown && mainSeconds > 0) }
        let required = stages.filter { $0.kind.isMain }.reduce(0) { $0 + ($1.seconds ?? 0) }
        return completedPlan || (required > 0 && mainSeconds >= required)
    }
    public var completionTitle: String { mainSeconds == 0 && mainMeters == 0 ? "仅热身" : isCompleted ? "已完成" : "提前结束" }
    public var runningSeconds: Double { runSeconds ?? (plan.isBeginner ? 0 : mainSeconds) }
}
