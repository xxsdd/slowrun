import Foundation

public enum CoachingTip: String, CaseIterable, Codable, Sendable, Identifiable {
    case posture, breathing, effort
    public var id: String { rawValue }
    public var title: String {
        switch self { case .posture: return "手臂怎么摆"; case .breathing: return "气怎么吸吐"; case .effort: return "说一句话检查" }
    }
    public var speech: String {
        switch self {
        case .posture: return "手肘弯到大约直角，双手轻握，沿身体两侧前后摆，不要横着甩过胸前。"
        case .breathing: return "鼻子轻吸两次，嘴巴呼气一次，不要憋气。"
        case .effort: return "说一句，我现在跑得还算轻松。能顺畅说完就保持；说两三个字就要喘气，就降低速度，再试着把这句话说完整。"
        }
    }
    public var sourceTitle: String {
        switch self { case .posture: return "HSS：手臂摆动与跑姿"; case .breathing: return "康文署：一般呼吸说明"; case .effort: return "England Athletics：训练配速与体感" }
    }
    public var sourceURL: URL {
        switch self {
        case .posture: return URL(string: "https://www.hss.edu/health-library/move-better/proper-running-form")!
        case .breathing: return URL(string: "https://www.lcsd.gov.hk/tc/healthy/runningpractice.html")!
        case .effort: return URL(string: "https://www.englandathletics.org/news/simplifying-the-running-jargon-training-pace-2/")!
        }
    }
    public var demonstrationURL: URL? {
        self == .posture ? URL(string: "https://www.youtube.com/watch?v=XXYtfpqFo24") : nil
    }
}

// Persist the last delivery so reopening cannot repeat a recently spoken routine.
struct CoachingProgress: Codable, Sendable {
    // Retained for decoding snapshots made before repeating guidance existed.
    var delivered = false
    var lastDeliveredMainSeconds: Double?
    var lastDeliveredRunSeconds: Double?
    var lastPriorityElapsed: Double?
    var previousElapsed: Double?

    mutating func takeTip(record: WorkoutRecord, enabled: Bool, audioIdle: Bool) -> Bool {
        defer { previousElapsed = record.elapsedSeconds }
        if delivered && lastDeliveredRunSeconds == nil {
            lastDeliveredRunSeconds = record.runningSeconds
        }
        // Don't burst out with catch-up guidance on a delayed/background tick.
        if let previousElapsed, record.elapsedSeconds - previousElapsed > 15 {
            lastPriorityElapsed = record.elapsedSeconds
        }
        guard enabled, audioIdle, record.status == .active,
              record.stage.kind == .run, record.runningSeconds - (lastDeliveredRunSeconds ?? 0) >= 180,
              record.stageSeconds >= 20,
              record.stage.seconds.map({ $0 - record.stageSeconds >= 20 }) ?? true,
              lastPriorityElapsed.map({ record.elapsedSeconds - $0 >= 20 }) ?? true else { return false }
        delivered = true
        lastDeliveredRunSeconds = record.runningSeconds
        return true
    }
}
