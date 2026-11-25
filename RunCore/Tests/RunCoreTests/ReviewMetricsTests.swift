import XCTest
@testable import RunCore

final class ReviewMetricsTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    func point(_ meters: Double, _ t: Double, speed: Double? = nil) -> TrackPoint {
        TrackPoint(latitude: 0, longitude: meters / 111_194.9266, timestamp: start.addingTimeInterval(t), accuracy: 5, speed: speed)
    }
    func fixture() -> WorkoutRecord {
        var e = WorkoutEngine(plan: .freeRun, at: start, freeRunSeconds: 30, freeWalkSeconds: 30)
        _ = e.ingest(point(0, 0)); _ = e.ingest(point(10, 10))
        _ = e.skipPreparation(at: start.addingTimeInterval(10))
        _ = e.ingest(point(10, 11)); _ = e.ingest(point(40, 20)); _ = e.ingest(point(70, 30))
        _ = e.advance(to: start.addingTimeInterval(40))
        _ = e.ingest(point(70, 40)); _ = e.ingest(point(80, 50)); _ = e.ingest(point(90, 60))
        _ = e.finish(at: start.addingTimeInterval(65))
        return e.record
    }
    func testAcceptedDistancesAreSeparatedAndPersisted() throws {
        let record = fixture()
        let decoded = try JSONDecoder().decode(WorkoutRecord.self, from: JSONEncoder().encode(record))
        let m = ReviewMetrics(decoded)
        XCTAssertEqual(m.meters(.run)!, 60, accuracy: 0.02)
        XCTAssertEqual(m.meters(.walk)!, 20, accuracy: 0.02)
        XCTAssertEqual(m.seconds(.run), 30)
        XCTAssertEqual(m.seconds(.walk), 25)
        XCTAssertEqual(m.meters(.run)! + m.meters(.walk)!, record.mainMeters, accuracy: 0.001)
        XCTAssertEqual(record.totalMeters - record.mainMeters, 10, accuracy: 0.02)
        XCTAssertEqual(m.completeRuns.count, 1)
    }
    func testLegacyReconstructionMustReconcileAndDoesNotRewrite() {
        var record = fixture()
        for i in record.activitySpans!.indices { record.activitySpans![i].meters = nil }
        record.statisticsVersion = 2
        let m = ReviewMetrics(record)
        XCTAssertTrue(m.reconstructed)
        XCTAssertEqual(m.meters(.run)!, 60, accuracy: 0.02)
        XCTAssertNil(record.activitySpans![1].meters)
        record.mainMeters += 100
        XCTAssertNil(ReviewMetrics(record).meters(.run))
        XCTAssertFalse(ReviewMetrics(record).reconstructed)
    }
    func testPauseDoesNotCreateNewRunAndGapIsNotBridged() {
        var e = WorkoutEngine(plan: .threeK, at: start)
        _ = e.skipPreparation(at: start)
        _ = e.ingest(point(0,0)); _ = e.ingest(point(20,10))
        _ = e.pause(at: start.addingTimeInterval(15))
        e.resume(at: start.addingTimeInterval(200))
        _ = e.ingest(point(1000,200)); _ = e.ingest(point(1020,210))
        _ = e.finish(at: start.addingTimeInterval(215))
        let m = ReviewMetrics(e.record)
        XCTAssertEqual(m.intervals.count,1)
        XCTAssertEqual(m.seconds(.run),30)
        XCTAssertEqual(m.meters(.run)!,40,accuracy:0.02)
    }
    func testDailyReviewRevisionAndPersistence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = WorkoutStorage(directory: root)
        let value = DailyReview(day: "2026-11-12", text: "已有复盘", sources: ["a":"v1","b":"v1"])
        try storage.saveDailyReview(value)
        XCTAssertEqual(try storage.dailyReviews().first?.text,"已有复盘")
        XCTAssertTrue(value.isCurrent(["a":"v1","b":"v1"]))
        XCTAssertFalse(value.isCurrent(["a":"v2","b":"v1"]))
        XCTAssertFalse(value.isCurrent(["a":"v1"]))
        XCTAssertEqual(value.addedCount(["a":"v1","b":"v1","c":"v1"]),1)
        XCTAssertEqual(try storage.records().count,0)
    }
    func testMixedScheduledRunLengthsAndWeightedComparison() {
        var record = fixture()
        var spans: [ActivitySpan] = []
        for i in 0..<6 {
            var run = ActivitySpan(start:start.addingTimeInterval(Double(i*60)),end:start.addingTimeInterval(Double(i*60+30)),kind:.run)
            run.meters = i < 3 ? 60 : 50
            var walk = ActivitySpan(start:run.end,end:run.end.addingTimeInterval(30),kind:.walk)
            walk.meters=20
            spans += [run,walk]
        }
        record.activitySpans = spans
        XCTAssertEqual(ReviewMetrics(record).paceChange!,100,accuracy:0.01)
    }
}
