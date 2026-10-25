import XCTest
@testable import RunCore

final class CoachingTipTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    func readyEngine() -> WorkoutEngine {
        var engine = WorkoutEngine(plan: .threeK, at: start)
        _ = engine.skipPreparation(at: start)
        return engine
    }
    func tick(_ engine: inout WorkoutEngine, through seconds: Int, enabled: Bool = true, audioIdle: Bool = true) -> [WorkoutEvent] {
        var tips: [WorkoutEvent] = []
        for second in 1...seconds {
            let events = engine.advance(to: start.addingTimeInterval(Double(second)))
            if !events.isEmpty { engine.notePriorityCue() }
            if let tip = engine.takeCoachingTip(enabled: enabled, audioIdle: audioIdle) { tips.append(tip) }
        }
        return tips
    }
    func testAllThreeActionsRepeatEveryThreeMainMinutes() {
        var engine = readyEngine()
        XCTAssertTrue(tick(&engine, through: 179).isEmpty)
        var deliveredAt: [Int] = []
        for second in 180...1_000 {
            _ = engine.advance(to: start.addingTimeInterval(Double(second)))
            if let tip = engine.takeCoachingTip(enabled: true, audioIdle: true) {
                deliveredAt.append(second)
                for action in CoachingTip.allCases { XCTAssertTrue(tip.speech.contains(action.speech)) }
                XCTAssertLessThanOrEqual(tip.speech.count, 300)
            }
        }
        XCTAssertEqual(deliveredAt, [180, 360, 540, 720, 900])
    }
    func testDisabledOrBusyAudioDoesNotConsumeTheTip() {
        var engine = readyEngine()
        XCTAssertTrue(tick(&engine, through: 300, enabled: false).isEmpty)
        _ = engine.advance(to: start.addingTimeInterval(301))
        XCTAssertNil(engine.takeCoachingTip(enabled: true, audioIdle: false))
        _ = engine.advance(to: start.addingTimeInterval(302))
        XCTAssertNotNil(engine.takeCoachingTip(enabled: true, audioIdle: true))
    }
    func testPriorityCueLeavesTwentyQuietSeconds() {
        var engine = readyEngine()
        _ = tick(&engine, through: 300, enabled: false)
        engine.notePriorityCue()
        for second in 301...319 {
            _ = engine.advance(to: start.addingTimeInterval(Double(second)))
            XCTAssertNil(engine.takeCoachingTip(enabled: true, audioIdle: true))
        }
        _ = engine.advance(to: start.addingTimeInterval(320))
        XCTAssertNotNil(engine.takeCoachingTip(enabled: true, audioIdle: true))
    }
    func testDelayedTickDoesNotBurstIntoCatchUpSpeech() {
        var engine = readyEngine()
        _ = tick(&engine, through: 299)
        _ = engine.advance(to: start.addingTimeInterval(600))
        XCTAssertNil(engine.takeCoachingTip(enabled: true, audioIdle: true))
        _ = engine.advance(to: start.addingTimeInterval(610))
        XCTAssertNil(engine.takeCoachingTip(enabled: true, audioIdle: true))
        _ = engine.advance(to: start.addingTimeInterval(620))
        XCTAssertNotNil(engine.takeCoachingTip(enabled: true, audioIdle: true))
    }
    func testSavingAndRecoveringPreservesThreeMinuteInterval() throws {
        var engine = readyEngine()
        XCTAssertEqual(tick(&engine, through: 200).count, 1)
        var restored = try JSONDecoder().decode(WorkoutEngine.self, from: JSONEncoder().encode(engine))
        restored.recoverPaused(at: start.addingTimeInterval(900))
        restored.resume(at: start.addingTimeInterval(900))
        for second in 1...159 {
            _ = restored.advance(to: start.addingTimeInterval(Double(900 + second)))
            XCTAssertNil(restored.takeCoachingTip(enabled: true, audioIdle: true))
        }
        _ = restored.advance(to: start.addingTimeInterval(1_060))
        XCTAssertNotNil(restored.takeCoachingTip(enabled: true, audioIdle: true))
    }
    func testOlderSnapshotWithoutCoachingFieldStillDecodes() throws {
        let data = try JSONEncoder().encode(readyEngine())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "coachingProgress")
        var restored = try JSONDecoder().decode(WorkoutEngine.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(tick(&restored, through: 301).count, 1)
    }
    func testBeginnerOnlyGetsTipDuringRunAwayFromStageBoundary() {
        var engine = WorkoutEngine(plan: .beginner, at: start)
        _ = engine.skipPreparation(at: start)
        var count = 0
        for second in 1...1_100 {
            let events = engine.advance(to: start.addingTimeInterval(Double(second)))
            if !events.isEmpty { engine.notePriorityCue() }
            if engine.takeCoachingTip(enabled: true, audioIdle: true) != nil {
                count += 1
                XCTAssertEqual(engine.record.stage.kind, .run)
                XCTAssertGreaterThanOrEqual(engine.record.stageSeconds, 20)
                XCTAssertGreaterThanOrEqual((engine.record.stage.seconds ?? 0) - engine.record.stageSeconds, 20)
            }
        }
        XCTAssertEqual(count, 2)
    }
    func testPausedAndCooldownDoNotGiveTips() {
        var engine = readyEngine()
        _ = tick(&engine, through: 300, enabled: false)
        _ = engine.pause(at: start.addingTimeInterval(300))
        XCTAssertNil(engine.takeCoachingTip(enabled: true, audioIdle: true))
        engine.resume(at: start.addingTimeInterval(400))
        _ = engine.finish(at: start.addingTimeInterval(401))
        XCTAssertNil(engine.takeCoachingTip(enabled: true, audioIdle: true))
        var cooldown = engine.record
        cooldown.status = .active; cooldown.stageIndex = 2
        cooldown.stageSeconds = 100; cooldown.mainSeconds = 600
        var progress = CoachingProgress()
        XCTAssertFalse(progress.takeTip(record: cooldown, enabled: true, audioIdle: true))
    }
}
