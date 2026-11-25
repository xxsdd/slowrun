import Foundation
import Combine
import RunCore

enum VoiceMode: String, CaseIterable, Identifiable {
    case microsoft, system, silent
    var id: String { rawValue }
    var title: String { switch self { case .microsoft: return RunLanguage.text("微软语音"); case .system: return RunLanguage.text("系统语音（离线备用）"); case .silent: return RunLanguage.text("关闭语音") } }
}
@MainActor final class AppSettings: ObservableObject {
    @Published var voiceMode: VoiceMode { didSet { defaults.set(voiceMode.rawValue, forKey: "voiceMode") } }
    @Published var fallbackToSystem: Bool { didSet { defaults.set(fallbackToSystem, forKey: "fallbackToSystem") } }
    @Published var coachingTips: Bool { didSet { defaults.set(coachingTips, forKey: "coachingTips") } }
    @Published var paceReportEnabled: Bool { didSet { defaults.set(paceReportEnabled, forKey: "paceReportEnabled") } }
    @Published var deviationAlerts: Bool { didSet { defaults.set(deviationAlerts, forKey: "paceDeviationAlerts") } }
    @Published var paceReportInterval: Int { didSet { defaults.set(paceReportInterval, forKey: "paceReportInterval") } }
    static let paceReportIntervals = Array(stride(from: 30, through: 300, by: 15))
    @Published var weightText: String { didSet { defaults.set(weightText, forKey: "weightText") } }
    @Published var targetPaceText: String { didSet { defaults.set(targetPaceText, forKey: "targetPaceText") } }
    @Published var heightText: String { didSet { defaults.set(heightText, forKey: "heightText") } }
    @Published var freeRunSeconds: Int { didSet { defaults.set(freeRunSeconds, forKey: "freeRunSeconds") } }
    @Published var freeWalkSeconds: Int { didSet { defaults.set(freeWalkSeconds, forKey: "freeWalkSeconds") } }
    @Published var distanceGoalEnabled: Bool { didSet { defaults.set(distanceGoalEnabled, forKey: "distanceGoalEnabled") } }
    @Published var distanceGoalMeters: Int { didSet { defaults.set(distanceGoalMeters, forKey: "distanceGoalMeters") } }
    var selectedDistanceGoal: Double? { distanceGoalEnabled ? Double(distanceGoalMeters) : nil }
    @Published var lastPlan: WorkoutPlan { didSet { defaults.set(lastPlan.rawValue, forKey: "lastPlan") } }
    @Published var courseProgress: CourseProgress { didSet {
        if let data = try? JSONEncoder().encode(courseProgress) { defaults.set(data, forKey: "courseProgressV2") }
    } }
    var progressInitialized: Bool { defaults.data(forKey: "courseProgressV2") != nil }
    private let defaults = UserDefaults.standard
    init() {
        let saved = UserDefaults.standard
        distanceGoalEnabled = saved.bool(forKey: "distanceGoalEnabled")
        let goal = saved.object(forKey: "distanceGoalMeters") as? Int ?? 3000
        distanceGoalMeters = min(20000, max(1000, goal / 500 * 500))
        heightText = saved.string(forKey: "heightText") ?? ""
        let run = saved.object(forKey: "freeRunSeconds") as? Int ?? 180
        let walk = saved.object(forKey: "freeWalkSeconds") as? Int ?? 120
        freeRunSeconds = min(3600, max(15, run / 15 * 15))
        freeWalkSeconds = min(3600, max(0, walk / 15 * 15))
        lastPlan = WorkoutPlan(rawValue: saved.string(forKey: "lastPlan") ?? "beginner") ?? .beginner
        courseProgress = saved.data(forKey: "courseProgressV2").flatMap { try? JSONDecoder().decode(CourseProgress.self, from: $0) } ?? CourseProgress()

        voiceMode = VoiceMode(rawValue: UserDefaults.standard.string(forKey: "voiceMode") ?? "microsoft") ?? .microsoft
        fallbackToSystem = UserDefaults.standard.object(forKey: "fallbackToSystem") as? Bool ?? true
        coachingTips = UserDefaults.standard.object(forKey: "coachingTips") as? Bool ?? true
        paceReportEnabled = UserDefaults.standard.object(forKey: "paceReportEnabled") as? Bool ?? true
        deviationAlerts = saved.bool(forKey: "paceDeviationAlerts")
        let savedInterval = UserDefaults.standard.integer(forKey: "paceReportInterval")
        paceReportInterval = Self.paceReportIntervals.contains(savedInterval) ? savedInterval : 30
        weightText = UserDefaults.standard.string(forKey: "weightText") ?? ""
        targetPaceText = UserDefaults.standard.string(forKey: "targetPaceText") ?? ""

    }
    var weightKg: Double? { guard let value = Double(weightText), (25...300).contains(value) else { return nil }; return value }
    var targetPace: Double? {
        let parts = targetPaceText.split(separator: ":")
        guard parts.count == 2, let min = Double(parts[0]), let sec = Double(parts[1]), min >= 2, min <= 20, sec >= 0, sec < 60 else { return nil }
        return min * 60 + sec
    }
    var voiceDescription: String {
        switch voiceMode {
        case .silent: return RunLanguage.text("语音已关闭")
        case .system: return RunLanguage.text("当前使用系统语音（离线）")
        case .microsoft: return RunLanguage.text("微软离线提示 %1$@/%2$@，数字语音 %3$@/%4$@ 条已就绪。配速、公里用时也在手机本地组合播放，无需联网或连接电脑。", "\(OfflineVoicePack.shared.count)", "\(FixedVoiceCue.allCases.count)", "\(OfflineVoicePack.shared.numberCount)", "\(NumberVoiceScript.texts.count)")
        }
    }
}
