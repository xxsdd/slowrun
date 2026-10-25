import Foundation

enum PaceReminder {
    static func periodicSpeech(pace: Double, target: Double?) -> String {
        let recent = "当前配速每公里\(RunFormat.spokenTime(pace))"
        guard let target, target.isFinite, target > 0 else { return recent + "。" }
        if abs(pace - target) <= 60 { return recent + "，刚刚好。" }
        return recent + (pace < target ? "，有点快了。" : "，有点慢了。")
    }
}
