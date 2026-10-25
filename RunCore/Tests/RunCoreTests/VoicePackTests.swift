import XCTest
import CryptoKit
import AVFoundation
@testable import RunCore

final class VoicePackTests: XCTestCase {
    func testEveryFixedWorkoutCueHasAuthenticDecodableOfflineAudio() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let pack = root.appendingPathComponent("SlowRun/Resources/VoicePack")
        let data = try Data(contentsOf: pack.appendingPathComponent("manifest.json"))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(manifest["voice"] as? String, "zh-CN-XiaoxiaoNeural")
        let clips = try XCTUnwrap(manifest["clips"] as? [String: [String: String]])
        let events: [WorkoutEvent] = [.stage(.warmup), .stage(.run), .stage(.walk), .stage(.cooldown),
            .adjustment(FixedVoiceCue.tooFast.speech), .adjustment(FixedVoiceCue.slowing.speech), .coaching, .finished, .freeRunStarted]
        for event in events {
            let cue = try XCTUnwrap(event.fixedVoiceCue)
            let clip = try XCTUnwrap(clips[cue.rawValue])
            XCTAssertEqual(clip["text"], event.speech, "Stale recording for \(cue.rawValue)")
            let audio = try Data(contentsOf: pack.appendingPathComponent(cue.rawValue + ".mp3"))
            XCTAssertEqual(clip["sha256"], SHA256.hash(data: audio).map { String(format: "%02x", $0) }.joined())
            let player = try AVAudioPlayer(data: audio)
            XCTAssertGreaterThan(player.duration, 0)
            XCTAssertGreaterThan(player.numberOfChannels, 0)
        }
        XCTAssertEqual(clips.count, FixedVoiceCue.allCases.count)
        // Variable numbers must not accidentally select a fixed, stale recording.
        XCTAssertNil(WorkoutEvent.kilometer(2, 400, 790).fixedVoiceCue)
        XCTAssertNil(WorkoutEvent.adjustment("a future custom cue").fixedVoiceCue)
    }
}
