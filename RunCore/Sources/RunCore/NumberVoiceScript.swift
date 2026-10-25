import Foundation

/// IDs refer only to pre-recorded Microsoft audio, never text synthesized online.
public enum NumberVoiceScript {
    public static let texts: [String: String] = {
        var result = [
            "pace": "当前配速每公里", "target": "目标每公里",
            "good": "刚刚好。", "fast": "有点快了。",
            "slow": "有点慢了。",
            "remaining": "本段跑步还剩", "complete": "已完成",
            "lap": "这一公里用时", "total": "累计主要训练用时", "zero": "零秒。"
        ]
        for (prefix, unit, maximum) in [("minute", "分", 59), ("second", "秒", 59), ("hour", "小时", 12), ("km", "公里", 50)] {
            for n in 1...maximum { result["\(prefix)_\(n)"] = chinese(n) + unit }
        }
        return result
    }()

    private static func chinese(_ n: Int) -> String {
        let digits = Array("零一二三四五六七八九").map(String.init)
        if n < 10 { return digits[n] }
        return (n >= 20 ? digits[n / 10] : "") + "十" + (n % 10 == 0 ? "" : digits[n % 10])
    }

    public static func duration(_ seconds: Double) -> [String]? {
        guard seconds.isFinite, seconds >= 0, seconds.rounded() < 46_800 else { return nil }
        let value = Int(seconds.rounded())
        if value == 0 { return ["zero"] }
        var ids: [String] = []
        if value / 3_600 > 0 { ids.append("hour_\(value / 3_600)") }
        if value / 60 % 60 > 0 { ids.append("minute_\(value / 60 % 60)") }
        if value % 60 > 0 { ids.append("second_\(value % 60)") }
        return ids
    }

    public static func fragments(for event: WorkoutEvent) -> [String]? {
        switch event {
        case .pace(let pace, let target, _):
            guard pace > 0, let current = duration(pace) else { return nil }
            var ids = ["pace"] + current
            if let target {
                guard target.isFinite, target > 0 else { return nil }
                ids.append(abs(pace - target) <= 60 ? "good" : pace < target ? "fast" : "slow")
            }
            return ids
        case .kilometer(let km, let lap, let total):
            guard (1...50).contains(km), let lapTime = duration(lap), let totalTime = duration(total) else { return nil }
            return ["complete", "km_\(km)", "lap"] + lapTime + ["total"] + totalTime
        default: return nil
        }
    }

    public static func pauses(after fragments: [String]) -> [Int] {
        let phrases: Set<String> = ["target", "good", "fast", "slow", "remaining", "lap", "total"]
        return fragments.indices.map { index in
            if index == fragments.count - 1 { return 60 }
            return phrases.contains(fragments[index + 1]) ? 180 : 25
        }
    }
}

/// Canonical PCM WAVs avoid separate player starts between words. All clips
/// are validated before a single WAV is handed to AVAudioPlayer.
public enum PCMVoiceComposer {
    public enum InvalidAudio: Error { case format, size }

    public static func samples(from wav: Data) throws -> Data {
        let bytes = [UInt8](wav.prefix(44))
        guard wav.count >= 44 else { throw InvalidAudio.format }
        func word(_ offset: Int, _ count: Int) -> UInt32 {
            (0..<count).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << ($1 * 8) }
        }
        guard String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
              String(bytes: bytes[8..<16], encoding: .ascii) == "WAVEfmt ",
              String(bytes: bytes[36..<40], encoding: .ascii) == "data",
              word(4, 4) == UInt32(wav.count - 8), word(16, 4) == 16,
              word(20, 2) == 1, word(22, 2) == 1, word(24, 4) == 24_000,
              word(28, 4) == 48_000, word(32, 2) == 2, word(34, 2) == 16,
              word(40, 4) == UInt32(wav.count - 44), wav.count > 44, wav.count % 2 == 0,
              wav.count < 6_000_000 else { throw InvalidAudio.format }
        return wav.subdata(in: 44..<wav.count)
    }

    public static func compose(_ clips: [Data], pauses: [Int]) throws -> Data {
        guard !clips.isEmpty, clips.count == pauses.count, clips.count <= 40 else { throw InvalidAudio.size }
        var pcm = Data()
        for (audio, pause) in zip(clips, pauses) {
            guard (0...1_000).contains(pause) else { throw InvalidAudio.size }
            pcm.append(try samples(from: audio))
            pcm.append(Data(repeating: 0, count: pause * 48))
            guard pcm.count <= 12_000_000 else { throw InvalidAudio.size }
        }
        var result = Data("RIFF".utf8)
        func append(_ value: UInt32, bytes: Int = 4) {
            for shift in 0..<bytes { result.append(UInt8((value >> (shift * 8)) & 255)) }
        }
        append(UInt32(pcm.count + 36)); result.append(Data("WAVEfmt ".utf8))
        append(16); append(1, bytes: 2); append(1, bytes: 2)
        append(24_000); append(48_000); append(2, bytes: 2); append(16, bytes: 2)
        result.append(Data("data".utf8)); append(UInt32(pcm.count)); result.append(pcm)
        return result
    }
}
