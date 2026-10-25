import Foundation
import CryptoKit
import RunCore

struct OfflineVoicePack: Sendable {
    static let shared = OfflineVoicePack()
    private struct Manifest: Decodable {
        let voice: String
        let clips: [String: Clip]
    }
    private struct Clip: Decodable {
        let text: String
        let sha256: String
    }
    private let clips: [String: Data]
    private let numberClips: [String: Data]
    var count: Int { clips.count }
    var numberCount: Int { numberClips.count }

    init(bundle: Bundle = .main) {
        var validated: [String: Data] = [:]
        if let manifestURL = bundle.url(forResource: "manifest", withExtension: "json", subdirectory: "VoicePack"),
           let data = try? Data(contentsOf: manifestURL),
           let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
           manifest.voice == "zh-CN-XiaoxiaoNeural" {
            for cue in FixedVoiceCue.allCases {
                guard let clip = manifest.clips[cue.rawValue], clip.text == cue.speech,
                      let url = bundle.url(forResource: cue.rawValue, withExtension: "mp3", subdirectory: "VoicePack"),
                      let audio = try? Data(contentsOf: url), !audio.isEmpty,
                      SHA256.hash(data: audio).map({ String(format: "%02x", $0) }).joined() == clip.sha256 else { continue }
                validated[cue.rawValue] = audio
            }
        }
        clips = validated
        var numbers: [String: Data] = [:]
        if let url = bundle.url(forResource: "manifest", withExtension: "json", subdirectory: "VoicePack/numbers"),
           let data = try? Data(contentsOf: url),
           let manifest = try? JSONDecoder().decode(Manifest.self, from: data), manifest.voice == "zh-CN-XiaoxiaoNeural" {
            for (id, text) in NumberVoiceScript.texts {
                guard let clip = manifest.clips[id], clip.text == text,
                      let url = bundle.url(forResource: id, withExtension: "wav", subdirectory: "VoicePack/numbers"),
                      let audio = try? Data(contentsOf: url),
                      SHA256.hash(data: audio).map({ String(format: "%02x", $0) }).joined() == clip.sha256,
                      (try? PCMVoiceComposer.samples(from: audio)) != nil else { continue }
                numbers[id] = audio
            }
        }
        numberClips = numbers
    }

    func audio(for cue: FixedVoiceCue) -> Data? { clips[cue.rawValue] }
    func audio(for event: WorkoutEvent) -> Data? {
        if let cue = event.fixedVoiceCue { return audio(for: cue) }
        guard let ids = NumberVoiceScript.fragments(for: event) else { return nil }
        let audio = ids.compactMap { numberClips[$0] }
        guard audio.count == ids.count else { return nil }
        return try? PCMVoiceComposer.compose(audio, pauses: NumberVoiceScript.pauses(after: ids))
    }
}
