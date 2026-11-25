import XCTest
@testable import RunCore

final class WorkoutSpeechQueueTests: XCTestCase {
    func testTurnPlaysNextWithoutRequeuingStartedAnnouncement() {
        var queue = WorkoutSpeechQueue()
        let kilometer = WorkoutEvent.kilometer(1, 450, 450)
        let turn = NavigationCue(voice: .nearRight, routeID: UUID(), maneuverID: 1)
        queue.enqueue([kilometer])
        XCTAssertEqual(queue.next { _ in true }, .workout(kilometer))

        // The kilometer is already playing. A turn displaces waiting optional
        // speech and plays ahead of the pending stage without replaying it.
        queue.enqueue([.stage(.walk), .pace(460, nil, nil)])
        queue.enqueueNavigation(turn)
        XCTAssertEqual(queue.next { _ in true }, .navigation(turn))
        XCTAssertEqual(queue.next { _ in true }, .workout(.stage(.walk)))
        XCTAssertNil(queue.next { _ in true })
    }

    func testExpiredTurnAndObsoleteStageAreSkipped() {
        var queue = WorkoutSpeechQueue()
        queue.enqueue([.stage(.walk)])
        queue.enqueue([.stage(.run)])
        queue.enqueueNavigation(.init(voice: .advanceLeft, routeID: UUID(), maneuverID: 1))
        XCTAssertEqual(queue.next { _ in false }, .workout(.stage(.run)))
        XCTAssertTrue(queue.isEmpty)
    }

    func testNearTurnReplacesAdvanceCueAndRouteChangeKeepsWorkoutCue() {
        var queue = WorkoutSpeechQueue()
        let routeID = UUID()
        let near = NavigationCue(voice: .nearLeft, routeID: routeID, maneuverID: 1)
        queue.enqueueNavigation(.init(voice: .advanceLeft, routeID: routeID, maneuverID: 1))
        queue.enqueueNavigation(near)
        XCTAssertEqual(queue.next { _ in true }, .navigation(near))
        XCTAssertTrue(queue.isEmpty)

        queue.enqueue([.stage(.walk)])
        queue.enqueueNavigation(.init(voice: .nearRight, routeID: routeID, maneuverID: 2))
        queue.cancelNavigation()
        XCTAssertEqual(queue.next { _ in true }, .workout(.stage(.walk)))
    }

    func testAudiobookOnlySpeaksRunWalkChanges() {
        var queue = WorkoutSpeechQueue()
        let changes: [WorkoutEvent] = [.freeRunStarted, .stage(.run), .stage(.walk), .stage(.cooldown)]
        for event in changes {
            queue.enqueue([event], audiobookMode: true)
            XCTAssertEqual(queue.next { _ in true }, .workout(event))
        }

        let muted: [WorkoutEvent] = [.stage(.warmup), .kilometer(1, 450, 450), .adjustment("偏快"),
                                     .pace(450, nil, nil), .coaching, .distanceGoalReached, .finished]
        for event in muted {
            queue.enqueue([event], audiobookMode: true)
            XCTAssertTrue(queue.isEmpty)
            queue.enqueue([event])
            XCTAssertEqual(queue.next { _ in true }, .workout(event))
        }
    }

    func testAudiobookFinishingDiscardsStalePhaseEvenThoughFinishIsSilent() {
        var queue = WorkoutSpeechQueue()
        queue.enqueue([.stage(.walk)], audiobookMode: true)
        queue.enqueue([.stage(.run), .finished], audiobookMode: true)
        XCTAssertNil(queue.next { _ in true })
    }

    func testAudiobookNavigationHasPriorityAndSilentRerouteDropsObsoleteTurn() {
        var queue = WorkoutSpeechQueue()
        let route = UUID()
        for voice in NavigationVoice.allCases where voice != .rerouting {
            let cue = NavigationCue(voice: voice, routeID: route)
            queue.enqueue([.stage(.run)], audiobookMode: true)
            queue.enqueueNavigation(cue, audiobookMode: true)
            XCTAssertEqual(queue.next { _ in true }, .navigation(cue))
            XCTAssertEqual(queue.next { _ in true }, .workout(.stage(.run)))
        }
        queue.enqueueNavigation(.init(voice: .nearRight, routeID: route), audiobookMode: true)
        queue.enqueueNavigation(.init(voice: .rerouting, routeID: route), audiobookMode: true)
        XCTAssertTrue(queue.isEmpty)
    }

    func testAudiobookChoiceSurvivesRecoveryAndLegacyRunsDefaultToNormal() throws {
        let engine = WorkoutEngine(plan: .freeRun, audiobookMode: true)
        let data = try JSONEncoder().encode(engine)
        var restored = try JSONDecoder().decode(WorkoutEngine.self, from: data)
        restored.recoverPaused(at: engine.record.startedAt)
        restored.resume(at: engine.record.startedAt)
        XCTAssertTrue(restored.record.isAudiobookMode)
        XCTAssertFalse(WorkoutEngine(plan: .freeRun).record.isAudiobookMode)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var legacyRecord = try XCTUnwrap(json["record"] as? [String: Any])
        legacyRecord.removeValue(forKey: "audiobookMode")
        json["record"] = legacyRecord
        let legacy = try JSONDecoder().decode(WorkoutEngine.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(legacy.record.isAudiobookMode)
    }

    func testAudiobookFreeRunStillComputesPaceAndSkipsPeriodicSpeech() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for audiobook in [true, false] {
            var engine = WorkoutEngine(plan: .freeRun, at: start, freeRunSeconds: 120, freeWalkSeconds: 0, audiobookMode: audiobook)
            XCTAssertEqual(engine.skipPreparation(at: start), [.freeRunStarted])
            for second in stride(from: 0, through: 180, by: 5) {
                let point = TrackPoint(latitude: Double(second) / 50_000, longitude: 0,
                                       timestamp: start.addingTimeInterval(Double(second)), accuracy: 5)
                XCTAssertTrue(engine.ingest(point).isEmpty)
            }
            XCTAssertEqual(engine.record.stage.kind, .run)
            XCTAssertNotNil(engine.record.currentPace)
            XCTAssertGreaterThan(engine.record.mainMeters, 300)
            XCTAssertEqual(engine.takePaceReport(audioIdle: true) != nil, !audiobook)
            XCTAssertEqual(engine.takeCoachingTip(enabled: true, audioIdle: true) != nil, !audiobook)
        }
    }
}
