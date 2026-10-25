import XCTest
@testable import RunCore

final class RefreshTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    func point(_ meters: Double, _ seconds: Double) -> TrackPoint {
        TrackPoint(latitude: 0, longitude: meters / 111_194.9266, timestamp: start.addingTimeInterval(seconds), accuracy: 5)
    }
    func testFormalCompletionDoesNotRequireCooldownOrSpecificFinishButton() {
        for plan in WorkoutPlan.beginnerWeeks {
            for session in 1...3 {
                var engine = WorkoutEngine(plan: plan, at: start, session: session)
                _ = engine.skipPreparation(at: start)
                let duration = engine.record.stages.filter { $0.kind.isMain }.reduce(0) { $0 + ($1.seconds ?? 0) }
                _ = engine.advance(to: start.addingTimeInterval(duration))
                XCTAssertEqual(engine.record.stage.kind, .cooldown)
                XCTAssertTrue(engine.record.isCompleted)
                var other = engine
                _ = engine.finish(at: start.addingTimeInterval(duration + 15))
                _ = other.skipPreparation(at: start.addingTimeInterval(duration + 15))
                XCTAssertEqual(engine.record.completedPlan, other.record.completedPlan)
                XCTAssertTrue(engine.record.isCompleted)
            }
        }
    }
    func testEarlyCooldownDoesNotTurnIncompleteCourseIntoCompleted() {
        var engine = WorkoutEngine(plan: .beginner, at: start)
        _ = engine.skipPreparation(at: start)
        _ = engine.beginCooldown(at: start.addingTimeInterval(20))
        _ = engine.advance(to: start.addingTimeInterval(320))
        XCTAssertEqual(engine.record.status, .finished)
        XCTAssertFalse(engine.record.isCompleted)
    }
    func testFreeIntervalsLoopPauseAndSaveConfiguration() throws {
        var engine = WorkoutEngine(plan: .freeRun, at: start, freeRunSeconds: 30, freeWalkSeconds: 15)
        _ = engine.skipPreparation(at: start)
        _ = engine.advance(to: start.addingTimeInterval(100))
        XCTAssertEqual(engine.record.stage.kind, .run)
        XCTAssertEqual(engine.record.stageSeconds, 10)
        XCTAssertEqual(engine.record.runningSeconds, 70)
        XCTAssertEqual(engine.record.mainSeconds, 100)
        _ = engine.pause(at: start.addingTimeInterval(100))
        var restored = try JSONDecoder().decode(WorkoutEngine.self, from: JSONEncoder().encode(engine))
        restored.resume(at: start.addingTimeInterval(1000))
        _ = restored.advance(to: start.addingTimeInterval(1010))
        XCTAssertEqual(restored.record.mainSeconds, 110)
        XCTAssertEqual(restored.record.stageRemainingSeconds, 10)
        _ = restored.beginCooldown(at: start.addingTimeInterval(1010))
        _ = restored.finish(at: start.addingTimeInterval(1020))
        XCTAssertTrue(restored.record.isCompleted)
        XCTAssertEqual(restored.record.phaseStatistics?.cooldown.seconds, 10)
    }
    func testContinuousFreeRunAndWarmupOnly() {
        var engine = WorkoutEngine(plan: .freeRun, at: start, freeRunSeconds: 30, freeWalkSeconds: 0)
        _ = engine.finish(at: start.addingTimeInterval(30))
        XCTAssertFalse(engine.record.isCompleted)
        XCTAssertEqual(engine.record.completionTitle, "仅热身")
        var continuous = WorkoutEngine(plan: .freeRun, at: start, freeRunSeconds: 30, freeWalkSeconds: 0)
        _ = continuous.skipPreparation(at: start)
        _ = continuous.advance(to: start.addingTimeInterval(10000))
        XCTAssertEqual(continuous.record.stage.kind, .run)
        XCTAssertNil(continuous.record.stageRemainingSeconds)
    }
    func testPhaseTotalsMatchWholeAndPauseCreatesNoActiveSpan() throws {
        var engine = WorkoutEngine(plan: .freeRun, at: start, weightKg: 70)
        _ = engine.ingest(point(0,0)); _ = engine.ingest(point(10,10))
        _ = engine.skipPreparation(at: start.addingTimeInterval(10))
        _ = engine.ingest(point(10,11)); _ = engine.ingest(point(40,21))
        _ = engine.pause(at: start.addingTimeInterval(21))
        engine.resume(at: start.addingTimeInterval(121))
        _ = engine.beginCooldown(at: start.addingTimeInterval(131))
        _ = engine.ingest(point(40,132)); _ = engine.ingest(point(50,142))
        _ = engine.finish(at: start.addingTimeInterval(142))
        let totals = try XCTUnwrap(engine.record.phaseStatistics)
        XCTAssertEqual(totals.warmup.meters,10,accuracy:0.02)
        XCTAssertEqual(totals.main.meters,30,accuracy:0.02)
        XCTAssertEqual(totals.cooldown.meters,10,accuracy:0.02)
        XCTAssertEqual(WorkoutPhase.allCases.reduce(0) { $0 + totals[$1].meters },engine.record.totalMeters,accuracy:0.001)
        XCTAssertEqual(WorkoutPhase.allCases.reduce(0) { $0 + totals[$1].seconds },engine.record.elapsedSeconds)
        XCTAssertEqual(WorkoutPhase.allCases.reduce(0) { $0 + (totals[$1].calories ?? 0) },try XCTUnwrap(engine.record.calories),accuracy:0.001)
        XCTAssertEqual(engine.record.activitySpans!.reduce(0) { $0 + $1.seconds },42)
        XCTAssertNil(engine.record.totalSteps)
        engine.finalizeSteps([.warmup:100,.main:200,.cooldown:50])
        XCTAssertEqual(engine.record.totalSteps,350)
        XCTAssertEqual(engine.record.mainSteps,200)
        engine.finalizeSteps([.warmup:100,.main:nil,.cooldown:50])
        XCTAssertNil(engine.record.totalSteps)
    }
    func testStepCallbackAcrossStageBoundaryIsNotAllAssignedToNewStage() {
        var engine = WorkoutEngine(plan: .freeRun, at: start)
        _ = engine.skipPreparation(at: start.addingTimeInterval(10))
        _ = engine.advance(to: start.addingTimeInterval(20))
        engine.recordMotion(steps: 40,cadence:120,from:start,to:start.addingTimeInterval(20))
        XCTAssertEqual(engine.record.phaseStatistics?.warmup.steps,20)
        XCTAssertEqual(engine.record.phaseStatistics?.main.steps,20)
        XCTAssertEqual(engine.record.totalSteps,40)
    }
    func testWalkingDoesNotEarnCoachingTime() {
        var engine = WorkoutEngine(plan: .freeRun, at: start, freeRunSeconds:60,freeWalkSeconds:600)
        _ = engine.skipPreparation(at:start)
        var count = 0
        for second in 1...1000 {
            let events = engine.advance(to:start.addingTimeInterval(Double(second)))
            if !events.isEmpty { engine.notePriorityCue() }
            if engine.takeCoachingTip(enabled:true,audioIdle:true) != nil { count += 1 }
        }
        XCTAssertEqual(count,0)
        XCTAssertEqual(engine.record.runningSeconds,120)
    }
    func testProgressRollsWeekPersistsAndDoesNotSkipMissingCourses() throws {
        var progress = CourseProgress()
        for session in 1...3 {
            var engine = WorkoutEngine(plan:.beginner,at:start,session:session)
            _ = engine.advance(to:start.addingTimeInterval(1710))
            progress.register(engine.record); progress.register(engine.record)
        }
        XCTAssertEqual(progress.plan,.week2);XCTAssertEqual(progress.session,1)
        var later = WorkoutEngine(plan:.week4,at:start)
        _ = later.advance(to:start.addingTimeInterval(1890));progress.register(later.record)
        XCTAssertEqual(progress.plan,.week2)
        let restored = try JSONDecoder().decode(CourseProgress.self,from:JSONEncoder().encode(progress))
        XCTAssertEqual(restored.nextIndex,3)
    }
    func testOldJSONRemainsReadableAndCorrectsVerifiedFinishOnly() throws {
        var engine = WorkoutEngine(plan:.beginner,at:start)
        _ = engine.advance(to:start.addingTimeInterval(1410))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(engine.record)) as? [String:Any])
        for key in ["statisticsVersion","phaseStatistics","activitySpans","runSeconds","freeRunSeconds","freeWalkSeconds","memo","stepsFinalized"] { object.removeValue(forKey:key) }
        object["completedPlan"] = false
        var old = try JSONDecoder().decode(WorkoutRecord.self,from:JSONSerialization.data(withJSONObject:object))
        XCTAssertNil(old.phaseStatistics);XCTAssertNil(old.totalSteps);XCTAssertTrue(old.isCompleted)
        old.mainSeconds = 100
        XCTAssertFalse(old.isCompleted)
    }
}
