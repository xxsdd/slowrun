import Foundation
import Combine
import Security
import RunCore

enum VoiceMode: String, CaseIterable, Identifiable {
    case microsoft, system, silent
    var id: String { rawValue }
    var title: String { switch self { case .microsoft: return "微软语音"; case .system: return "系统语音（离线备用）"; case .silent: return "关闭语音" } }
}
@MainActor final class AppSettings: ObservableObject {
    @Published var voiceMode: VoiceMode { didSet { defaults.set(voiceMode.rawValue, forKey: "voiceMode") } }
    @Published var fallbackToSystem: Bool { didSet { defaults.set(fallbackToSystem, forKey: "fallbackToSystem") } }
    @Published var coachingTips: Bool { didSet { defaults.set(coachingTips, forKey: "coachingTips") } }
    @Published var paceReportEnabled: Bool { didSet { defaults.set(paceReportEnabled, forKey: "paceReportEnabled") } }
    @Published var paceReportInterval: Int { didSet { defaults.set(paceReportInterval, forKey: "paceReportInterval") } }
    static let paceReportIntervals = Array(stride(from: 30, through: 300, by: 15))
    @Published var serviceURL: String { didSet { defaults.set(serviceURL, forKey: "serviceURL") } }
    @Published var serviceToken: String { didSet { KeychainToken.save(serviceToken) } }
    @Published var weightText: String { didSet { defaults.set(weightText, forKey: "weightText") } }
    @Published var targetPaceText: String { didSet { defaults.set(targetPaceText, forKey: "targetPaceText") } }
    @Published var heightText: String { didSet { defaults.set(heightText, forKey: "heightText") } }
    @Published var freeRunSeconds: Int { didSet { defaults.set(freeRunSeconds, forKey: "freeRunSeconds") } }
    @Published var freeWalkSeconds: Int { didSet { defaults.set(freeWalkSeconds, forKey: "freeWalkSeconds") } }
    @Published var lastPlan: WorkoutPlan { didSet { defaults.set(lastPlan.rawValue, forKey: "lastPlan") } }
    @Published var courseProgress: CourseProgress { didSet {
        if let data = try? JSONEncoder().encode(courseProgress) { defaults.set(data, forKey: "courseProgressV2") }
    } }
    var progressInitialized: Bool { defaults.data(forKey: "courseProgressV2") != nil }
    private let defaults = UserDefaults.standard
    init() {
        let saved = UserDefaults.standard
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
        let savedInterval = UserDefaults.standard.integer(forKey: "paceReportInterval")
        paceReportInterval = Self.paceReportIntervals.contains(savedInterval) ? savedInterval : 30
        serviceURL = UserDefaults.standard.string(forKey: "serviceURL") ?? ""
        serviceToken = KeychainToken.load()
        weightText = UserDefaults.standard.string(forKey: "weightText") ?? ""
        targetPaceText = UserDefaults.standard.string(forKey: "targetPaceText") ?? ""
    }
    var weightKg: Double? { guard let value = Double(weightText), (25...300).contains(value) else { return nil }; return value }
    var targetPace: Double? {
        let parts = targetPaceText.split(separator: ":")
        guard parts.count == 2, let min = Double(parts[0]), let sec = Double(parts[1]), min >= 2, min <= 20, sec >= 0, sec < 60 else { return nil }
        return min * 60 + sec
    }
    var endpoint: URL? {
        guard let url = URL(string: serviceURL.trimmingCharacters(in: .whitespacesAndNewlines)), let host = url.host, !host.isEmpty, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        if url.scheme == "https" { return url }
        #if DEBUG
        // Local development only; release requires HTTPS.
        let bytes = host.split(separator: ".").compactMap { Int($0) }
        let privateIPv4 = bytes.count == 4 && bytes.allSatisfy { (0...255).contains($0) } && (bytes[0] == 10 || (bytes[0] == 192 && bytes[1] == 168) || (bytes[0] == 172 && (16...31).contains(bytes[1])))
        if url.scheme == "http", host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local") || privateIPv4 { return url }
        #endif
        return nil
    }
    var serviceConfigured: Bool { endpoint != nil && !serviceToken.isEmpty }
    var voiceDescription: String {
        switch voiceMode {
        case .silent: return "语音已关闭"
        case .system: return "当前使用系统语音（离线）"
        case .microsoft: return "微软离线提示 \(OfflineVoicePack.shared.count)/\(FixedVoiceCue.allCases.count)，数字语音 \(OfflineVoicePack.shared.numberCount)/\(NumberVoiceScript.texts.count) 条已就绪。配速、公里用时也在手机本地组合播放，无需联网或连接电脑。"
        }
    }
}
enum KeychainToken {
    private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "SlowRun.personal-service", kSecAttrAccount as String: "access-token"] }
    static func load() -> String {
        var request = query; request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ value: String) {
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var request = query; request[kSecValueData as String] = Data(value.utf8)
        request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(request as CFDictionary, nil)
    }
}
