import XCTest
import CryptoKit
import AVFoundation
@testable import RunCore

final class NumberVoiceTests: XCTestCase {
    private func pack() -> URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        return root.appendingPathComponent("SlowRun/Resources/VoicePack/numbers")
    }

    func testRoundedTimeCarriesAndUnsupportedValuesDoNotProduceWrongNumbers() {
        XCTAssertEqual(NumberVoiceScript.duration(479.6), ["minute_8"])
        XCTAssertEqual(NumberVoiceScript.duration(3_599.6), ["hour_1"])
        XCTAssertEqual(NumberVoiceScript.duration(0), ["zero"])
        XCTAssertEqual(NumberVoiceScript.duration(7_230), ["hour_2", "second_30"])
        for value in [-1.0, .nan, .infinity, 46_799.6] { XCTAssertNil(NumberVoiceScript.duration(value)) }
        XCTAssertNil(NumberVoiceScript.fragments(for: .kilometer(51, 450, 450)))
        XCTAssertNil(NumberVoiceScript.fragments(for: .paceReport(pace: .nan, target: nil)))
    }

    func testComparisonUsesSameInclusiveToleranceAndFactsAsDisplaySpeech() {
        let event = WorkoutEvent.paceReport(pace: 450, target: 450, remaining: 90)
        XCTAssertEqual(NumberVoiceScript.fragments(for: event),
            ["pace", "minute_7", "second_30", "good"])
        for pace in [390.0, 450, 510] {
            XCTAssertTrue(NumberVoiceScript.fragments(for: .paceReport(pace: pace, target: 450))!.contains("good"))
        }
        XCTAssertTrue(NumberVoiceScript.fragments(for: .paceReport(pace: 389, target: 450))!.contains("fast"))
        XCTAssertTrue(NumberVoiceScript.fragments(for: .paceReport(pace: 511, target: 450))!.contains("slow"))
        XCTAssertEqual(NumberVoiceScript.fragments(for: .paceReport(pace: 450, target: nil)), ["pace", "minute_7", "second_30"])
        XCTAssertEqual(NumberVoiceScript.fragments(for: .kilometer(2, 430, 880)),
            ["complete", "km_2", "lap", "minute_7", "second_10", "total", "minute_14", "second_40"])
    }

    func testEveryNumberRecordingHasMatchingTextHashAndDecodablePCM() throws {
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: pack().appendingPathComponent("manifest.json"))) as? [String: Any])
        XCTAssertEqual(manifest["voice"] as? String, "zh-CN-XiaoxiaoNeural")
        let clips = try XCTUnwrap(manifest["clips"] as? [String: [String: String]])
        XCTAssertEqual(Set(clips.keys), Set(NumberVoiceScript.texts.keys))
        for (id, text) in NumberVoiceScript.texts {
            let audio = try Data(contentsOf: pack().appendingPathComponent(id + ".wav"))
            XCTAssertEqual(clips[id]?["text"], text)
            XCTAssertEqual(clips[id]?["sha256"], SHA256.hash(data: audio).map { String(format: "%02x", $0) }.joined())
            XCTAssertGreaterThan(try PCMVoiceComposer.samples(from: audio).count, 2_400)
            XCTAssertGreaterThan(try AVAudioPlayer(data: audio).duration, 0.05)
        }
    }

    func testComposedAudioContainsExactSamplesAndGapsAndPlaysAsOneFile() throws {
        let ids = try XCTUnwrap(NumberVoiceScript.fragments(for: .paceReport(pace: 450, target: 450, remaining: 90)))
        let clips = try ids.map { try Data(contentsOf: pack().appendingPathComponent($0 + ".wav")) }
        let pauses = NumberVoiceScript.pauses(after: ids)
        let audio = try PCMVoiceComposer.compose(clips, pauses: pauses)
        var expected = Data()
        for (clip, pause) in zip(clips, pauses) {
            expected.append(try PCMVoiceComposer.samples(from: clip))
            expected.append(Data(repeating: 0, count: pause * 48))
        }
        XCTAssertEqual(try PCMVoiceComposer.samples(from: audio), expected)
        let player = try AVAudioPlayer(data: audio)
        XCTAssertEqual(player.numberOfChannels, 1)
        XCTAssertEqual(player.duration, Double(expected.count) / 48_000, accuracy: 0.001)
        XCTAssertThrowsError(try PCMVoiceComposer.compose([], pauses: []))
        XCTAssertThrowsError(try PCMVoiceComposer.compose(clips, pauses: []))
        XCTAssertThrowsError(try PCMVoiceComposer.samples(from: Data(audio.prefix(30))))
        var badRate = clips[0]; badRate[24] = 0
        XCTAssertThrowsError(try PCMVoiceComposer.samples(from: badRate))
        XCTAssertThrowsError(try PCMVoiceComposer.samples(from: Data(clips[0].dropLast())))
    }
}
