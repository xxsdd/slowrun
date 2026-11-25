import XCTest
@testable import RunCore

final class NavigationTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    func coordinate(_ x: Double, _ y: Double = 0) -> NavigationCoordinate { NavigationCoordinate(latitude: y / 111_194.9266, longitude: x / 111_194.9266) }
    func fix(_ x: Double, _ time: Double, y: Double = 0, accuracy: Double = 5) -> TrackPoint {
        let p = coordinate(x, y)
        return TrackPoint(latitude: p.latitude, longitude: p.longitude, timestamp: start.addingTimeInterval(time), accuracy: accuracy)
    }
    func route() -> NavigationRoute { NavigationRoute(points: [coordinate(0), coordinate(100), coordinate(100, 100)], maneuvers: [.init(id: 0, metersFromStart: 100, turn: .left, instruction: "Turn left")]) }
    func cues(_ events: [NavigationEvent]) -> [NavigationVoice] { events.compactMap { if case .cue(let c) = $0 { return c.voice }; return nil } }
    func testAdvanceAndNearAreOnceEachDespiteThresholdJitter() {
        var engine = NavigationEngine(route: route())
        _ = engine.update(fix(40, 0), receivedAt: start)
        XCTAssertEqual(cues(engine.update(fix(49, 1), receivedAt: start.addingTimeInterval(1))), [.advanceLeft])
        for (i, x) in [48.0, 51, 49, 60].enumerated() { XCTAssertTrue(engine.update(fix(x, Double(i + 2)), receivedAt: start.addingTimeInterval(Double(i + 2))).isEmpty) }
        XCTAssertEqual(cues(engine.update(fix(90, 7), receivedAt: start.addingTimeInterval(7))), [.nearLeft])
        XCTAssertTrue(engine.update(fix(91, 8), receivedAt: start.addingTimeInterval(8)).isEmpty)
    }
    func testLateJumpDoesNotPlayObsoleteFiftyMetersCue() {
        var engine = NavigationEngine(route: route())
        _ = engine.update(fix(20, 0), receivedAt: start)
        XCTAssertEqual(cues(engine.update(fix(90, 1), receivedAt: start.addingTimeInterval(1))), [.nearLeft])
    }
    func testBadOldFutureAndUnorderedPositionsCannotTriggerTurn() {
        var engine = NavigationEngine(route: route())
        for point in [fix(50, 0, accuracy: -1), fix(50, 0, accuracy: 40), fix(50, -20), fix(50, 30), TrackPoint(latitude: .nan, longitude: 0, timestamp: start, accuracy: 2)] {
            XCTAssertTrue(engine.update(point, receivedAt: start).isEmpty)
        }
        _ = engine.update(fix(10, 1), receivedAt: start.addingTimeInterval(1))
        XCTAssertTrue(engine.update(fix(50, 0), receivedAt: start.addingTimeInterval(1)).isEmpty)
        XCTAssertLessThan(engine.progress, 11)
    }
    func testNearTurnRequiresBetterAccuracy() {
        var engine = NavigationEngine(route: route())
        _ = engine.update(fix(80, 0), receivedAt: start)
        XCTAssertTrue(engine.update(fix(90, 1, accuracy: 18), receivedAt: start.addingTimeInterval(1)).isEmpty)
        XCTAssertEqual(cues(engine.update(fix(91, 2), receivedAt: start.addingTimeInterval(2))), [.nearLeft])
    }
    func testOffRouteRequiresPersistenceAndEmitsOnlyOnce() {
        var engine = NavigationEngine(route: route())
        _ = engine.update(fix(10, 0), receivedAt: start)
        XCTAssertTrue(engine.update(fix(20, 1, y: -60), receivedAt: start.addingTimeInterval(1)).isEmpty)
        XCTAssertTrue(engine.update(fix(30, 3, y: -60), receivedAt: start.addingTimeInterval(3)).isEmpty)
        let events = engine.update(fix(40, 7, y: -60), receivedAt: start.addingTimeInterval(7))
        XCTAssertEqual(events.count, 1); XCTAssertTrue(engine.needsReroute)
        XCTAssertTrue(engine.update(fix(45, 8, y: -60), receivedAt: start.addingTimeInterval(8)).isEmpty)
    }
    func testArrivalStopsNavigationOnlyAndIsNotRepeated() {
        let path = NavigationRoute(points: [coordinate(0), coordinate(100)], maneuvers: [])
        var engine = NavigationEngine(route: path)
        _ = engine.update(fix(70, 0), receivedAt: start)
        XCTAssertEqual(cues(engine.update(fix(90, 1), receivedAt: start.addingTimeInterval(1))), [.arrived])
        XCTAssertTrue(engine.arrived)
        XCTAssertTrue(engine.update(fix(95, 2), receivedAt: start.addingTimeInterval(2)).isEmpty)
    }
    func testQueuedOldRouteAndExpiredCuesAreRejected() {
        var engine = NavigationEngine(route: route())
        _ = engine.update(fix(40, 0), receivedAt: start)
        let event = engine.update(fix(50, 1), receivedAt: start.addingTimeInterval(1))
        guard let first = event.first, case .cue(let cue) = first else { return XCTFail("Expected cue") }
        XCTAssertTrue(engine.canPlay(cue, at: start.addingTimeInterval(2)))
        XCTAssertFalse(engine.canPlay(cue, at: start.addingTimeInterval(20)))
        let replacement = NavigationEngine(route: route())
        XCTAssertFalse(replacement.canPlay(cue, at: start.addingTimeInterval(2)))
        _ = engine.update(fix(90, 3), receivedAt: start.addingTimeInterval(3))
        XCTAssertFalse(engine.canPlay(cue, at: start.addingTimeInterval(3)))
    }
    func testDistanceFollowsPolylineAndMatchingDoesNotJumpAcrossParallelLeg() {
        let path = NavigationRoute(points: [coordinate(0), coordinate(500), coordinate(500, 10), coordinate(0, 10)], maneuvers: [])
        var engine = NavigationEngine(route: path)
        _ = engine.update(fix(20, 0, y: 9), receivedAt: start)
        XCTAssertLessThan(engine.progress, 30)
        XCTAssertGreaterThan(engine.remainingMeters, 900)
        XCTAssertEqual(path.simplified(limit: 2).count, 2)
    }
    func testFavoritesPersistRenameAndDoNotDuplicateCoordinate() throws {
        var library = DestinationLibrary()
        let place = SavedDestination(name: "Park", coordinate: coordinate(50))
        library.toggle(place); library.rename(place.id, to: "  公园  "); library.select(place); library.select(place)
        let restored = try JSONDecoder().decode(DestinationLibrary.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(restored.favorites.first?.displayName, "公园"); XCTAssertEqual(restored.recent.count, 1)
        library.toggle(place); XCTAssertTrue(library.favorites.isEmpty)
    }
    func testDestinationResultsRankFromCurrentLocationAndKeepRelevanceWhenUnavailable() throws {
        let far = SavedDestination(name: "Far", coordinate: coordinate(1_500))
        let near = SavedDestination(name: "Near", coordinate: coordinate(300))
        let tied = SavedDestination(name: "Same distance", coordinate: coordinate(300))
        let invalid = SavedDestination(name: "Invalid", coordinate: .init(latitude: 91, longitude: 0))
        let matches = [far, near, invalid, tied]
        let ranked = DestinationSearchResult.ranked(matches, from: coordinate(0))
        XCTAssertEqual(ranked.map(\.id), [near.id, tied.id, far.id])
        XCTAssertEqual(try XCTUnwrap(ranked.first?.distanceMeters), 300, accuracy: 0.1)

        let afterMoving = DestinationSearchResult.ranked(matches, from: coordinate(1_400))
        XCTAssertEqual(afterMoving.first?.id, far.id)

        let withoutLocation = DestinationSearchResult.ranked(matches, from: nil)
        XCTAssertEqual(withoutLocation.map(\.id), [far.id, near.id, tied.id])
        XCTAssertTrue(withoutLocation.allSatisfy { $0.distanceMeters == nil })
    }
    func testTwoCloseTurnsKeepSeparateCueIdentity() {
        let path = NavigationRoute(points: [coordinate(0), coordinate(100), coordinate(100, 20), coordinate(200, 20)], maneuvers: [
            .init(id: 1, metersFromStart: 100, turn: .left, instruction: "Left"),
            .init(id: 2, metersFromStart: 120, turn: .right, instruction: "Right")
        ])
        var engine = NavigationEngine(route: path)
        _ = engine.update(fix(80, 0), receivedAt: start)
        XCTAssertEqual(cues(engine.update(fix(90, 1), receivedAt: start.addingTimeInterval(1))), [.nearLeft])
        XCTAssertEqual(cues(engine.update(fix(100, 4, y: 12), receivedAt: start.addingTimeInterval(4))), [.nearRight])
    }

    func testRouteRecommendationTradesFewExtraMetersForFewerTurnsWithinDetourLimit() {
        func route(_ distance: Double, _ turns: Int) -> WalkingRouteSummary {
            WalkingRouteSummary(distance: distance, turns: turns)
        }
        XCTAssertEqual(WalkingRouteSummary.recommendedIndex(in: [
            route(2_000, 9), route(2_080, 4), route(2_250, 0)
        ]), 1)
        XCTAssertEqual(WalkingRouteSummary.recommendedIndex(in: [
            route(700, 4), route(780, 0)
        ]), 0)
        XCTAssertEqual(WalkingRouteSummary.recommendedIndex(in: [
            route(2_000, 5), route(2_100, 4)
        ]), 0)
        XCTAssertEqual(WalkingRouteSummary.recommendedIndex(in: [route(1_100, 6)]), 0)
    }
    func testDirectionsRecognizeSupportedLanguagesAndDoNotInventRoundaboutTurn() {
        XCTAssertEqual(NavigationTurn.parse("Turn left onto Davie St"), .left)
        XCTAssertEqual(NavigationTurn.parse("向右转"), .right)
        XCTAssertEqual(NavigationTurn.parse("Take the first exit at the roundabout"), .unknown)
        XCTAssertEqual(NavigationTurn.parse("Continue on Wright St"), .straight)
        XCTAssertEqual(NavigationTurn.parse("Turn right onto Left Bank"), .right)
    }

    func testRightBendOverridesWrongLeftInstructionInMapAndBothVoiceCues() throws {
        let path = NavigationRoute(points: [coordinate(0), coordinate(0, 100), coordinate(100, 100)], maneuvers: [
            .init(id: 1, metersFromStart: 100, turn: .left, instruction: "Turn left")
        ]).resolvingTurnDirections()
        var engine = NavigationEngine(route: path)
        _ = engine.update(fix(0, 0, y: 45), receivedAt: start)
        XCTAssertEqual(cues(engine.update(fix(0, 1, y: 60), receivedAt: start.addingTimeInterval(1))), [.advanceRight])
        let turn = try XCTUnwrap(engine.nextManeuver)
        XCTAssertEqual(turn.turn.symbol, "arrow.turn.up.right")
        XCTAssertFalse(turn.instruction.contains("left"))
        let map = try XCTUnwrap(NavigationLocalMap(route: path, progress: engine.progress, position: coordinate(0, 60), bearing: 0, turnProgress: turn.metersFromStart))
        let marker = try XCTUnwrap(map.turn)
        XCTAssertGreaterThan(try XCTUnwrap(map.points.last).x, marker.x)
        XCTAssertEqual(cues(engine.update(fix(0, 2, y: 90), receivedAt: start.addingTimeInterval(2))), [.nearRight])
    }

    func testGeometryDistinguishesAdjacentTurnsAndIgnoresSpecialInstructions() {
        let path = NavigationRoute(points: [coordinate(0), coordinate(100), coordinate(100, 10), coordinate(200, 10)], maneuvers: [
            .init(id: 1, metersFromStart: 100, turn: .right, instruction: "Turn right"),
            .init(id: 2, metersFromStart: 110, turn: .left, instruction: "Turn left"),
            .init(id: 3, metersFromStart: 150, turn: .unknown, instruction: "Take the roundabout exit")
        ]).resolvingTurnDirections()
        XCTAssertEqual(path.maneuvers.map(\.turn), [.left, .right, .unknown])
        XCTAssertEqual(path.maneuvers.last?.instruction, "Take the roundabout exit")
    }

    func testStraightPathAtTurnMarkerDoesNotBorrowNextBendsDirection() {
        let path = NavigationRoute(points: [coordinate(0), coordinate(140), coordinate(140, -80)], maneuvers: [
            .init(id: 1, metersFromStart: 100, turn: .left, instruction: "Turn left"),
            .init(id: 2, metersFromStart: 140, turn: .right, instruction: "Turn right onto the trail")
        ]).resolvingTurnDirections()
        XCTAssertEqual(path.maneuvers.map(\.turn), [.unknown, .right])
        XCTAssertEqual(path.maneuvers.last?.instruction, "Turn right onto the trail")
    }
}
