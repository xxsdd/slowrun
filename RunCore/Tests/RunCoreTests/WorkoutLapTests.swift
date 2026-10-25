import XCTest
@testable import RunCore

final class WorkoutLapTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    func record(meters: Double, seconds: Double, splits: [KilometerSplit] = []) -> WorkoutRecord {
        var value = WorkoutEngine(plan: .fiveK, at: start).record
        value.mainMeters = meters; value.mainSeconds = seconds; value.splits = splits
        // Warmup/cooldown totals must never leak into a lap.
        value.elapsedSeconds = seconds + 600; value.totalMeters = meters + 700
        return value
    }
    func testTwoFullKilometersAndFinalFewHundredMeters() {
        let value = record(meters: 2_350, seconds: 930, splits: [
            KilometerSplit(kilometer: 1, seconds: 390, cumulativeSeconds: 390),
            KilometerSplit(kilometer: 2, seconds: 400, cumulativeSeconds: 790)
        ])
        XCTAssertEqual(value.laps.map(\.title), ["第 1 公里", "第 2 公里", "最后 350 米"])
        XCTAssertEqual(value.laps.map(\.seconds), [390, 400, 140])
        XCTAssertEqual(value.laps.map(\.meters), [1_000, 1_000, 350])
        XCTAssertEqual(value.laps.reduce(0) { $0 + $1.seconds }, value.mainSeconds)
    }
    func testLessThanOneKilometerIsStillARealLap() {
        let value = record(meters: 430, seconds: 180)
        XCTAssertEqual(value.laps.count, 1)
        XCTAssertEqual(value.laps.first?.title, "最后 430 米")
        XCTAssertEqual(value.laps.first?.seconds, 180)
    }
    func testExactKilometerDoesNotAppendPhantomRemainder() {
        let value = record(meters: 1_000.000001, seconds: 390, splits: [KilometerSplit(kilometer: 1, seconds: 390, cumulativeSeconds: 390)])
        XCTAssertEqual(value.laps.count, 1)
        XCTAssertFalse(value.laps[0].isPartial)
        XCTAssertTrue(record(meters: 0, seconds: 20).laps.isEmpty)
    }
    func testPausedTimeIsNotAddedToFinalLap() {
        var engine = WorkoutEngine(plan: .fiveK, at: start)
        _ = engine.skipPreparation(at: start)
        _ = engine.ingest(TrackPoint(latitude: 0, longitude: 0, timestamp: start, accuracy: 5))
        _ = engine.ingest(TrackPoint(latitude: 0, longitude: 30 / 111_194.9266, timestamp: start.addingTimeInterval(10), accuracy: 5))
        _ = engine.pause(at: start.addingTimeInterval(10))
        engine.resume(at: start.addingTimeInterval(100))
        _ = engine.finish(at: start.addingTimeInterval(110))
        XCTAssertEqual(engine.record.laps.count, 1)
        XCTAssertEqual(engine.record.laps[0].seconds, 20)
    }
}
