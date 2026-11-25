import Foundation
import CryptoKit
import RunCore

struct OfflineVoicePack: Sendable {
    private static let chinesePack = OfflineVoicePack(english: false)
    private static let englishPack = OfflineVoicePack(english: true)
    static var shared: OfflineVoicePack { RunLanguage.isEnglish ? englishPack : chinesePack }
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
    private let navigationClips: [String: Data]
    var count: Int { clips.count }
    var numberCount: Int { numberClips.count }
    var navigationCount: Int { navigationClips.count }

    init(bundle: Bundle = .main, english: Bool = false) {
        let folder = english ? "VoicePack/en" : "VoicePack"
        let voice = english ? "en-CA-ClaraNeural" : "zh-CN-XiaoxiaoNeural"
        var validated: [String: Data] = [:]
        if let manifestURL = bundle.url(forResource: "manifest", withExtension: "json", subdirectory: folder),
           let data = try? Data(contentsOf: manifestURL),
           let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
           manifest.voice == voice {
            for cue in FixedVoiceCue.allCases {
                guard let clip = manifest.clips[cue.rawValue], clip.text == (english ? RunLanguage.english(cue.speech) : cue.speech),
                      let url = bundle.url(forResource: cue.rawValue, withExtension: "mp3", subdirectory: folder),
                      let audio = try? Data(contentsOf: url), !audio.isEmpty,
                      SHA256.hash(data: audio).map({ String(format: "%02x", $0) }).joined() == clip.sha256 else { continue }
                validated[cue.rawValue] = audio
            }
        }
        clips = validated
        var numbers: [String: Data] = [:]
        if let url = bundle.url(forResource: "manifest", withExtension: "json", subdirectory: folder + "/numbers"),
           let data = try? Data(contentsOf: url),
           let manifest = try? JSONDecoder().decode(Manifest.self, from: data), manifest.voice == voice {
            for (id, text) in NumberVoiceScript.texts {
                guard let clip = manifest.clips[id], clip.text == (english ? RunLanguage.english(text) : text),
                      let url = bundle.url(forResource: id, withExtension: "wav", subdirectory: folder + "/numbers"),
                      let audio = try? Data(contentsOf: url),
                      SHA256.hash(data: audio).map({ String(format: "%02x", $0) }).joined() == clip.sha256,
                      (try? PCMVoiceComposer.samples(from: audio)) != nil else { continue }
                numbers[id] = audio
            }
        }
        numberClips = numbers
        var navigation: [String: Data] = [:]
        if let url = bundle.url(forResource: "manifest", withExtension: "json", subdirectory: folder + "/navigation"),
           let data = try? Data(contentsOf: url), let manifest = try? JSONDecoder().decode(Manifest.self, from: data), manifest.voice == voice {
            for cue in NavigationVoice.allCases {
                guard let clip = manifest.clips[cue.rawValue], clip.text == (english ? RunLanguage.english(cue.speech) : cue.speech),
                      let url = bundle.url(forResource: cue.rawValue, withExtension: "mp3", subdirectory: folder + "/navigation"),
                      let audio = try? Data(contentsOf: url), !audio.isEmpty,
                      SHA256.hash(data: audio).map({ String(format: "%02x", $0) }).joined() == clip.sha256 else { continue }
                navigation[cue.rawValue] = audio
            }
        }
        navigationClips = navigation
    }

    func audio(for cue: FixedVoiceCue) -> Data? { clips[cue.rawValue] }
    func audio(for cue: NavigationVoice) -> Data? { navigationClips[cue.rawValue] }
    func audio(for event: WorkoutEvent) -> Data? {
        if let cue = event.fixedVoiceCue { return audio(for: cue) }
        guard let ids = NumberVoiceScript.fragments(for: event) else { return nil }
        let audio = ids.compactMap { numberClips[$0] }
        guard audio.count == ids.count else { return nil }
        return try? PCMVoiceComposer.compose(audio, pauses: NumberVoiceScript.pauses(after: ids))
    }
}
