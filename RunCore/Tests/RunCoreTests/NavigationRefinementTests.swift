import XCTest
@testable import RunCore

final class NavigationRefinementTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    func coordinate(_ x: Double, _ y: Double = 0) -> NavigationCoordinate { .init(latitude: y / 111_194.9266, longitude: x / 111_194.9266) }
    func point(_ meters: Double, _ seconds: Double) -> TrackPoint {
        TrackPoint(latitude: 0, longitude: meters / 111_194.9266, timestamp: start.addingTimeInterval(seconds), accuracy: 5, speed: 2)
    }
    func testWarmupCountsTowardGoalWithoutCountingAsFormalTraining() {
        var e = WorkoutEngine(plan: .freeRun, at: start, distanceGoalMeters: 1000)
        for i in 0...20 { _ = e.ingest(point(Double(i) * 20, Double(i) * 10)) }
        XCTAssertEqual(e.record.goalProgressMeters, 400, accuracy: 0.1)
        XCTAssertEqual(e.record.mainMeters, 0)
        _ = e.skipPreparation(at: start.addingTimeInterval(200))
        var events: [WorkoutEvent] = []
        for i in 21...53 { events += e.ingest(point(Double(i) * 20, Double(i) * 10)) }
        XCTAssertEqual(events.filter { $0 == .distanceGoalReached }.count, 1)
        XCTAssertEqual(e.record.stage.kind, .cooldown)
        XCTAssertLessThan(e.record.mainMeters, 650)
        XCTAssertTrue(e.record.splits.isEmpty)
        let progress = e.record.goalProgressMeters
        for i in 54...57 { _ = e.ingest(point(Double(i) * 20, Double(i) * 10)) }
        XCTAssertEqual(e.record.goalProgressMeters, progress, accuracy: 0.1)
        _ = e.continueAfterGoal(at: start.addingTimeInterval(570))
        XCTAssertEqual(e.record.stage.kind, .run)
        var more: [WorkoutEvent] = []
        for i in 58...75 { more += e.ingest(point(Double(i) * 20, Double(i) * 10)) }
        XCTAssertFalse(more.contains(.distanceGoalReached))
        XCTAssertEqual(e.record.stage.kind, .run)
        XCTAssertTrue(e.record.goalContinued == true)
    }
    func testDestinationGoalOnlyNotifiesAndNeverStartsCooldown() {
        var e = WorkoutEngine(plan: .freeRun, at: start, distanceGoalMeters: 1000, destinationWorkout: true)
        _ = e.skipPreparation(at: start)
        var events: [WorkoutEvent] = []
        for i in 0...65 { events += e.ingest(point(Double(i) * 20, Double(i) * 10)) }
        XCTAssertEqual(events.filter { $0 == .distanceGoalReached }.count, 1)
        XCTAssertEqual(e.record.stage.kind, .run)
        XCTAssertEqual(e.record.status, .active)
        XCTAssertEqual(e.record.splits.count, 1)
    }
    func testPausedAndInvalidFixesDoNotReachGoalAndRecoveryKeepsIt() throws {
        var e = WorkoutEngine(plan: .freeRun, at: start, distanceGoalMeters: 1000)
        _ = e.ingest(point(0, 0)); _ = e.pause(at: start)
        XCTAssertFalse(e.ingest(point(1100, 10)).contains(.distanceGoalReached))
        XCTAssertEqual(e.record.totalMeters, 0)
        e.resume(at: start.addingTimeInterval(10))
        _ = e.ingest(point(0, 10))
        _ = e.ingest(point(1100, 11))
        XCTAssertEqual(e.record.totalMeters, 0)
        let restored = try JSONDecoder().decode(WorkoutEngine.self, from: JSONEncoder().encode(e))
        XCTAssertEqual(restored.record.distanceGoalMeters, 1000)
        XCTAssertEqual(restored.record.startTimeZone, e.record.startTimeZone)
    }
    func testGoalOffAndLegacyDistancePlanRemainIndependent() {
        var e = WorkoutEngine(plan: .freeRun, at: start)
        _ = e.skipPreparation(at: start)
        for i in 0...65 { _ = e.ingest(point(Double(i) * 20, Double(i) * 10)) }
        XCTAssertNil(e.record.distanceGoalMeters)
        XCTAssertEqual(e.record.stage.kind, .run)
        XCTAssertNil(WorkoutEngine(plan: .threeK, distanceGoalMeters: 1000).record.distanceGoalMeters)
    }
    func testOldRecordsWithoutNewFieldsStillDecode() throws {
        let record = WorkoutEngine(plan: .freeRun, at: start).record
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        for key in ["distanceGoalMeters", "goalReached", "goalContinued", "destinationWorkout", "startTimeZone", "startDayKey"] { json.removeValue(forKey: key) }
        let decoded = try JSONDecoder().decode(WorkoutRecord.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.id, record.id)
        XCTAssertNil(decoded.distanceGoalMeters); XCTAssertNil(decoded.startTimeZone)
    }
    func testHeadingWrapAndMotionPriorityAndPoorAccuracy() throws {
        var orientation = NavigationOrientation()
        orientation.heading(359, accuracy: 5, timestamp: start, at: start)
        orientation.heading(1, accuracy: 5, timestamp: start.addingTimeInterval(1), at: start.addingTimeInterval(1))
        XCTAssertLessThan(abs(NavigationOrientation.delta(from: try XCTUnwrap(orientation.bearing), to: 0)), 2)
        var fix = point(0, 2); fix.course = 90; fix.courseAccuracy = 5
        orientation.motion(fix, at: fix.timestamp)
        let moving = orientation.bearing
        orientation.heading(270, accuracy: 5, timestamp: start.addingTimeInterval(3), at: start.addingTimeInterval(3))
        XCTAssertEqual(orientation.bearing, moving)
        fix = point(0, 4); fix.course = 270; fix.courseAccuracy = -1
        orientation.motion(fix, at: fix.timestamp)
        XCTAssertEqual(orientation.bearing, moving)
        orientation.heading(270, accuracy: 5, timestamp: start.addingTimeInterval(6), at: start.addingTimeInterval(6))
        XCTAssertNotEqual(orientation.bearing, moving)
    }
    func testStaleHeadingCannotCreateDirection() {
        var o = NavigationOrientation()
        o.heading(90, accuracy: 5, timestamp: start, at: start.addingTimeInterval(20))
        var fix = point(0, 0); fix.course = 90; fix.courseAccuracy = 5
        o.motion(fix, at: start.addingTimeInterval(20))
        XCTAssertNil(o.bearing)
    }
    func testForwardUpMapShowsLeftTurnWithoutDistortingGeometry() throws {
        let route = NavigationRoute(points: [coordinate(0), coordinate(100), coordinate(100, 100), coordinate(4000, 100)], maneuvers: [])
        let map = try XCTUnwrap(NavigationLocalMap(route: route, progress: 50, position: coordinate(50), bearing: 90, turnProgress: 100))
        let turn = try XCTUnwrap(map.turn)
        XCTAssertLessThan(turn.y, map.position.y)
        XCTAssertEqual(turn.x, map.position.x, accuracy: 0.01)
        XCTAssertLessThan(try XCTUnwrap(map.points.last).x, turn.x)
        let ahead = (map.position.y - turn.y) * 62
        let left = (turn.x - map.points.last!.x) * 132
        XCTAssertEqual(left / ahead, 0.8, accuracy: 0.04) // 40m after corner / 50m before
        XCTAssertLessThanOrEqual(map.points.count, 28)
        XCTAssertTrue(map.points.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
    }
    func testCalendarKeepsMidnightSessionOnOriginalLocalStartDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Vancouver")!
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 23, minute: 55)))
        var e = WorkoutEngine(plan: .freeRun, at: date, weightKg: 60, timeZone: TimeZone(identifier: "America/Vancouver")!)
        _ = e.finish(at: date.addingTimeInterval(900))
        XCTAssertEqual(WorkoutDay.key(for: e.record, fallback: TimeZone(secondsFromGMT: 0)!), "2026-11-08")
        var next = WorkoutEngine(plan: .freeRun, at: date.addingTimeInterval(100), timeZone: TimeZone(identifier: "America/Vancouver")!)
        _ = next.finish(at: date.addingTimeInterval(200))
        let groups = WorkoutDay.groups([e.record, next.record])
        XCTAssertEqual(groups.count, 1)
        let summary = DailyWorkoutSummary(try XCTUnwrap(groups["2026-11-08"]))
        XCTAssertEqual(summary.records.count, 2)
        XCTAssertEqual(summary.seconds, 1000)
        XCTAssertTrue(summary.hasPartialCalories)
        XCTAssertNotNil(summary.calories)
        XCTAssertEqual(WorkoutDay.groups([e.record])["2026-11-08"]?.count, 1)
    }
    func testMissingCaloriesStayMissingAndDailyDistanceIncludesAllPhases() {
        var e = WorkoutEngine(plan: .freeRun, at: start)
        _ = e.ingest(point(0, 0)); _ = e.ingest(point(20, 10))
        _ = e.skipPreparation(at: start.addingTimeInterval(10))
        _ = e.ingest(point(20, 11)); _ = e.ingest(point(40, 21))
        _ = e.beginCooldown(at: start.addingTimeInterval(21))
        _ = e.ingest(point(40, 22)); _ = e.ingest(point(60, 32)); _ = e.finish(at: start.addingTimeInterval(32))
        let summary = DailyWorkoutSummary([e.record])
        XCTAssertNil(summary.calories)
        XCTAssertEqual(summary.meters, 60, accuracy: 0.1)
        XCTAssertEqual(summary.mainMeters, 20, accuracy: 0.1)
    }
}
