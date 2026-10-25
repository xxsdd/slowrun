import Foundation

public enum WorkoutPlan: String, Codable, CaseIterable, Identifiable, Sendable {
    case beginner, week2, week3, week4, week5, week6, week7, week8, week9, freeRun, threeK, fiveK
    public var id: String { rawValue }
    public var week: Int? {
        switch self {
        case .beginner: return 1
        case .week2: return 2
        case .week3: return 3
        case .week4: return 4
        case .week5: return 5
        case .week6: return 6
        case .week7: return 7
        case .week8: return 8
        case .week9: return 9
        default: return nil
        }
    }
    public static var beginnerWeeks: [WorkoutPlan] { allCases.filter { $0.week != nil } }
    public var isBeginner: Bool { week != nil }
    public var title: String {
        if let week { return "新手渐进 · 第 \(week) 周" }
        switch self { case .threeK: return "3 公里轻松跑"; case .fiveK: return "5 公里轻松跑"; default: return "自由跑" }
    }
    public var shortTitle: String {
        if week != nil { return "新手计划" }
        switch self { case .threeK: return "3 公里"; case .fiveK: return "5 公里"; default: return "自由跑" }
    }
    public var note: String {
        isBeginner ? "参考 NHS 九周走跑计划，每周三次，两次训练之间安排休息日；可以重复当前周。" : "热身、跑步和放松的距离全部计入全程；目标配速可选。"
    }
    public var targetMeters: Double? {
        switch self { case .threeK: return 3_000; case .fiveK: return 5_000; default: return nil }
    }
    public var stages: [TrainingStage] { stages(session: 1) }
    public func stages(session: Int) -> [TrainingStage] {
        let warmup = TrainingStage(kind: .warmup, seconds: 300)
        let cooldown = TrainingStage(kind: .cooldown, seconds: 300)
        // Signed seconds encode only the public NHS interval durations:
        // positive=run, negative=walk. Written independently, no project code copied.
        let intervals: [Double]
        switch week {
        case 1: intervals = Array(repeating: [60.0, -90.0], count: 7).flatMap { $0 } + [60]
        case 2: intervals = Array(repeating: [90.0, -120.0], count: 5).flatMap { $0 } + [90]
        case 3: intervals = [90, -90, 180, -180, 90, -90, 180]
        case 4: intervals = [180, -90, 300, -150, 180, -90, 300]
        case 5:
            intervals = session == 1 ? [300, -180, 300, -180, 300] : session == 2 ? [480, -300, 480] : [1_200]
        case 6:
            intervals = session == 1 ? [300, -180, 480, -180, 300] : session == 2 ? [600, -180, 600] : [1_500]
        case 7: intervals = [1_500]
        case 8: intervals = [1_680]
        case 9: intervals = [1_800]
        default: return [warmup, TrainingStage(kind: .run, seconds: nil), cooldown]
        }
        return [warmup] + intervals.map { TrainingStage(kind: $0 > 0 ? .run : .walk, seconds: abs($0)) } + [cooldown]
    }
}

public enum StageKind: String, Codable, Sendable {
    case warmup, run, walk, cooldown
    public var isMain: Bool { self == .run || self == .walk }
    public var title: String {
        switch self { case .warmup: return "步行热身"; case .run: return "轻松跑"; case .walk: return "步行恢复"; case .cooldown: return "步行放松" }
    }
}
public struct TrainingStage: Codable, Equatable, Sendable {
    public let kind: StageKind
    public let seconds: Double?
    public init(kind: StageKind, seconds: Double?) { self.kind = kind; self.seconds = seconds }
}
public enum WorkoutStatus: String, Codable, Sendable { case active, paused, finished }
public enum Effort: String, Codable, CaseIterable, Identifiable, Sendable {
    case easy, right, hard
    public var id: String { rawValue }
    public var title: String { switch self { case .easy: return "轻松"; case .right: return "刚好"; case .hard: return "吃力" } }
}
public struct TrackPoint: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let timestamp: Date
    public let accuracy: Double
    public let speed: Double?
    public var segment: Int
    public init(latitude: Double, longitude: Double, timestamp: Date, accuracy: Double, speed: Double? = nil, segment: Int = 0) {
        self.latitude = latitude; self.longitude = longitude; self.timestamp = timestamp
        self.accuracy = accuracy; self.speed = speed; self.segment = segment
    }
    public func distance(to other: TrackPoint) -> Double {
        let r = Double.pi / 180
        let a = pow(sin((other.latitude - latitude) * r / 2), 2) + cos(latitude * r) * cos(other.latitude * r) * pow(sin((other.longitude - longitude) * r / 2), 2)
        return 6_371_000 * 2 * atan2(sqrt(min(1, a)), sqrt(max(0, 1 - a)))
    }
}
public struct KilometerSplit: Codable, Identifiable, Equatable, Sendable {
    public var id: Int { kilometer }
    public let kilometer: Int
    public let seconds: Double
    public let cumulativeSeconds: Double
}
public struct PaceSample: Codable, Identifiable, Sendable {
    public var id: Double { elapsedSeconds }
    public let elapsedSeconds: Double
    public let secondsPerKilometer: Double
}
public struct WorkoutRecord: Codable, Identifiable, Sendable {
    public let id: UUID
    public let plan: WorkoutPlan
    public let startedAt: Date
    public var endedAt: Date?
    public var status: WorkoutStatus
    public var stageIndex: Int
    public var stageSeconds: Double
    public var elapsedSeconds: Double
    public var mainSeconds: Double
    public var totalMeters: Double
    public var mainMeters: Double
    public var mainSteps: Int
    public var cadence: Double?
    public var currentPace: Double?
    public var lastGPSAt: Date?
    public var calories: Double?
    public var weightKg: Double?
    public var targetPace: Double?
    public var track: [TrackPoint]
    public var splits: [KilometerSplit]
    public var paceSamples: [PaceSample]
    public var effort: Effort?
    public var completedPlan: Bool
    public var aiReview: String?
    public var session: Int? = nil
    public var statisticsVersion: Int? = nil
    public var phaseStatistics: PhaseStatistics? = nil
    public var activitySpans: [ActivitySpan]? = nil
    public var runSeconds: Double? = nil
    public var freeRunSeconds: Double? = nil
    public var freeWalkSeconds: Double? = nil
    public var memo: String? = nil
    public var stepsFinalized: Bool? = nil
    public var stages: [TrainingStage] {
        guard plan == .freeRun, let run = freeRunSeconds, let walk = freeWalkSeconds, walk > 0 else { return plan.stages(session: session ?? 1) }
        return [TrainingStage(kind: .warmup, seconds: 300), TrainingStage(kind: .run, seconds: max(15, run)), TrainingStage(kind: .walk, seconds: max(15, walk)), TrainingStage(kind: .cooldown, seconds: 300)]
    }
    public var stage: TrainingStage { stages[min(stageIndex, stages.count - 1)] }
    public var stageRemainingSeconds: Double? { stage.seconds.map { max(0, $0 - stageSeconds) } }
    public var title: String { plan.isBeginner ? plan.title + " · 第 \(session ?? 1) 次" : plan.title }
    public var averagePace: Double? { mainMeters >= 20 ? mainSeconds / mainMeters * 1_000 : nil }
    public var speedKmh: Double? { currentPace.map { 3_600 / $0 } }
    public var distanceLabel: String { "训练距离" }
    public var timeLabel: String { "训练用时" }
    public var localReview: String {
        guard mainSeconds >= 30 else { return "这次主要训练时间较短，先熟悉开始、暂停和结束。准备好了再按舒服的节奏出发。" }
        if effort == .hard { return "这次感觉比较吃力。下一次可以重复当前阶段或缩短训练，允许步行恢复，先不增加距离。" }
        if plan.isBeginner { return "跑走交替的配速起伏属于计划内容。先关注能否从容完成；两次训练之间留出休息日。" }
        let spread = splits.map(\.seconds)
        if let fastest = spread.min(), let slowest = spread.max(), fastest > 0, slowest / fastest > 1.2 {
            return "各公里的节奏有一些变化，可能和路况、停顿或体感有关。下一次前段放稳，累了可以放慢或步行。"
        }
        return effort == .easy ? "这次感觉轻松。先重复同样的训练，看看能否继续稳定完成，不必急着加量。" : "先把今天的训练稳定下来。下一次继续舒服的节奏，安排休息后再跑。"
    }
}
public enum WorkoutEvent: Equatable, Sendable {
    case stage(StageKind)
    case freeRunStarted
    case kilometer(Int, Double, Double)
    case adjustment(String)
    case pace(Double, Double?, Double?)
    case coaching
    case finished
    public static func paceReport(pace: Double, target: Double?, remaining: Double? = nil) -> WorkoutEvent {
        .pace(pace, target, remaining)
    }
    public var speech: String {
        switch self {
        case .stage, .freeRunStarted: return fixedVoiceCue!.speech
        case .kilometer(let km, let pace, let total): return "已完成\(km)公里，这一公里用时\(RunFormat.spokenTime(pace))，累计主要训练用时\(RunFormat.spokenTime(total))。"
        case .adjustment(let message): return message
        case .pace(let pace, let target, _):
            return PaceReminder.periodicSpeech(pace: pace, target: target)
        case .coaching: return FixedVoiceCue.coaching.speech
        case .finished: return FixedVoiceCue.finished.speech
        }
    }
}
public enum RunFormat {
    public static func time(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        if value >= 3_600 { return String(format: "%d:%02d:%02d", value / 3_600, value / 60 % 60, value % 60) }
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
    public static func pace(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "—" }
        let value = Int(seconds.rounded())
        return String(format: "%d′%02d″", value / 60, value % 60)
    }
    public static func spokenTime(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.rounded()))
        return "\(value / 60)分\(value % 60)秒"
    }
}
