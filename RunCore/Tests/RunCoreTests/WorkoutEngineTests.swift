import XCTest
@testable import RunCore

final class WorkoutEngineTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    func point(_ meters: Double, at seconds: Double, accuracy: Double = 5) -> TrackPoint {
        TrackPoint(latitude: 0, longitude: meters / 111_194.9266, timestamp: start.addingTimeInterval(seconds), accuracy: accuracy)
    }
    func testBeginnerHasExactWarmupMainAndCooldown() {
        var engine = WorkoutEngine(plan: .beginner, at: start)
        let events = engine.advance(to: start.addingTimeInterval(1_710))
        XCTAssertEqual(engine.record.status, .finished)
        XCTAssertEqual(engine.record.mainSeconds, 1_110, accuracy: 0.001)
        XCTAssertEqual(engine.record.elapsedSeconds, 1_710, accuracy: 0.001)
        XCTAssertTrue(engine.record.completedPlan)
        XCTAssertEqual(events.last, .finished)
    }
    func testPauseExcludesWallClockTime() {
        var engine = WorkoutEngine(plan: .threeK, at: start)
        _ = engine.skipPreparation(at: start)
        _ = engine.pause(at: start.addingTimeInterval(20))
        _ = engine.advance(to: start.addingTimeInterval(200))
        engine.resume(at: start.addingTimeInterval(200))
        _ = engine.advance(to: start.addingTimeInterval(210))
        XCTAssertEqual(engine.record.mainSeconds, 30)
    }
    func testWarmupDoesNotCountAsMainTraining() {
        var engine = WorkoutEngine(plan: .threeK, at: start)
        _ = engine.ingest(point(0, at: 0))
        _ = engine.ingest(point(10, at: 10))
        XCTAssertEqual(engine.record.totalMeters, 10, accuracy: 0.02)
        XCTAssertEqual(engine.record.mainMeters, 0)
        XCTAssertEqual(engine.record.mainSeconds, 0)
    }
    func testLongLocationGapBreaksTrackWithoutInventingDistance() {
        var engine = WorkoutEngine(plan: .threeK, at: start)
        _ = engine.skipPreparation(at: start)
        _ = engine.ingest(point(0, at: 0))
        _ = engine.ingest(point(1_000, at: 60))
        XCTAssertEqual(engine.record.mainMeters, 0)
        XCTAssertEqual(Set(engine.record.track.map(\.segment)).count, 2)
    }
    func testPoorAccuracyAndTeleportRejected() {
        var engine = WorkoutEngine(plan: .threeK, at: start)
        _ = engine.skipPreparation(at: start)
        _ = engine.ingest(point(0, at: 0))
        _ = engine.ingest(point(20, at: 5, accuracy: 100))
        _ = engine.ingest(point(1_000, at: 10))
        XCTAssertEqual(engine.record.mainMeters, 0)
        XCTAssertNil(engine.record.currentPace)
    }
    func testStaleGPSCannotBeAccepted() {
        var engine = WorkoutEngine(plan: .threeK, at: start)
        _ = engine.ingest(point(0, at: 0), receivedAt: start.addingTimeInterval(30))
        XCTAssertTrue(engine.record.track.isEmpty)
    }
    func testKilometerTimeIsInterpolatedAndDistanceTargetStartsCooldown() {
        var engine = WorkoutEngine(plan: .threeK, at: start)
        _ = engine.skipPreparation(at: start)
        var events: [WorkoutEvent] = []
        for i in 0...101 { events += engine.ingest(point(Double(i) * 30, at: Double(i) * 10)) }
        XCTAssertEqual(engine.record.mainMeters, 3_000, accuracy: 0.01)
        XCTAssertEqual(engine.record.stage.kind, .cooldown)
        XCTAssertEqual(engine.record.splits.count, 3)
        XCTAssertEqual(engine.record.splits[0].seconds, 333.333, accuracy: 0.1)
        XCTAssertTrue(events.contains { if case .kilometer(1, _, _) = $0 { return true }; return false })
    }
    func testCurrentPaceExpires() {
        var engine = WorkoutEngine(plan: .threeK, at: start)
        _ = engine.skipPreparation(at: start)
        _ = engine.ingest(point(0, at: 0))
        _ = engine.ingest(point(30, at: 10))
        XCTAssertNotNil(engine.record.currentPace)
        _ = engine.advance(to: start.addingTimeInterval(26))
        XCTAssertNil(engine.record.currentPace)
    }
    func testFinishedEarlyDoesNotFabricateGoalDistance() {
        var engine = WorkoutEngine(plan: .fiveK, at: start)
        _ = engine.skipPreparation(at: start)
        _ = engine.ingest(point(0, at: 0))
        _ = engine.ingest(point(30, at: 10))
        _ = engine.finish(at: start.addingTimeInterval(12))
        XCTAssertEqual(engine.record.mainMeters, 30, accuracy: 0.02)
        XCTAssertFalse(engine.record.completedPlan)
    }
    func testJSONRecoveryDoesNotCountInterruption() throws {
        var engine = WorkoutEngine(plan: .threeK, at: start)
        _ = engine.skipPreparation(at: start)
        _ = engine.advance(to: start.addingTimeInterval(10))
        var restored = try JSONDecoder().decode(WorkoutEngine.self, from: JSONEncoder().encode(engine))
        restored.recoverPaused(at: start.addingTimeInterval(500))
        XCTAssertEqual(restored.record.mainSeconds, 10)
        XCTAssertEqual(restored.record.status, .paused)
    }
    func testNoCalorieClaimWithoutWeight() {
        var engine = WorkoutEngine(plan: .beginner, at: start)
        _ = engine.advance(to: start.addingTimeInterval(60))
        XCTAssertNil(engine.record.calories)
    }
    func testResumeDoesNotConnectAcrossPausedMovement() {
        var engine = WorkoutEngine(plan: .threeK, at: start)
        _ = engine.skipPreparation(at: start)
        _ = engine.ingest(point(0, at: 0))
        _ = engine.pause(at: start.addingTimeInterval(10))
        engine.resume(at: start.addingTimeInterval(20))
        _ = engine.ingest(point(100, at: 20))
        _ = engine.ingest(point(130, at: 30))
        XCTAssertEqual(engine.record.mainMeters, 30, accuracy: 0.02)
    }
    func testSecondKilometerSpeechUsesLapTimeAndCumulativeMainTime() {
        var engine = WorkoutEngine(plan: .threeK, at: start)
        _ = engine.skipPreparation(at: start)
        var events: [WorkoutEvent] = []
        for i in 0...30 { events += engine.ingest(point(Double(i) * 1_000 / 30, at: Double(i) * 10)) }
        for i in 1...40 { events += engine.ingest(point(1_000 + Double(i) * 25, at: 300 + Double(i) * 10)) }
        let split = engine.record.splits[1]
        XCTAssertEqual(split.seconds, 400, accuracy: 0.01)
        XCTAssertEqual(split.cumulativeSeconds, 700, accuracy: 0.01)
        XCTAssertTrue(events.contains { event in
            if case .kilometer(2, _, _) = event {
                return event.speech.contains("6分40秒") && event.speech.contains("11分40秒")
            }
            return false
        })
    }

}
