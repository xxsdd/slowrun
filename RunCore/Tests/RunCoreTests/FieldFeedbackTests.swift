import XCTest
@testable import RunCore

final class FieldFeedbackTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    func point(_ meters: Double, _ second: Double) -> TrackPoint {
        TrackPoint(latitude: 0, longitude: meters / 111_194.9266, timestamp: start.addingTimeInterval(second), accuracy: 5)
    }
    func testAllTwentySevenNHSWorkoutsAndFinishBoundaries() {
        let expected: [[Double]] = [[1110,1110,1110],[1140,1140,1140],[900,900,900],[1290,1290,1290],
            [1260,1260,1200],[1440,1380,1500],[1500,1500,1500],[1680,1680,1680],[1800,1800,1800]]
        XCTAssertEqual(WorkoutPlan.beginnerWeeks.count,9)
        for (index,plan) in WorkoutPlan.beginnerWeeks.enumerated() {
            for session in 1...3 {
                let main=expected[index][session-1]
                var engine=WorkoutEngine(plan:plan,at:start,session:session)
                XCTAssertEqual(engine.record.stageRemainingSeconds,300)
                _ = engine.advance(to:start.addingTimeInterval(main+600))
                XCTAssertEqual(engine.record.mainSeconds,main,"\(plan) day \(session)")
                XCTAssertEqual(engine.record.status,.finished)
                XCTAssertTrue(engine.record.completedPlan)
                XCTAssertEqual(engine.record.elapsedSeconds,main+600)
            }
        }
    }
    func testWeekFiveAndSixDayVariantsAreRetainedAcrossStorage() throws {
        var engine=WorkoutEngine(plan:.week5,at:start,session:2)
        _ = engine.advance(to:start.addingTimeInterval(310))
        let restored=try JSONDecoder().decode(WorkoutEngine.self,from:JSONEncoder().encode(engine))
        XCTAssertEqual(restored.record.stage.seconds,480)
        XCTAssertEqual(restored.record.session,2)
        XCTAssertEqual(WorkoutPlan.week6.stages(session:3)[1].seconds,1500)
        var object=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(engine.record)) as? [String:Any])
        object["plan"]="beginner"; object.removeValue(forKey:"session")
        let old=try JSONDecoder().decode(WorkoutRecord.self,from:JSONSerialization.data(withJSONObject:object))
        XCTAssertNil(old.session)
        XCTAssertEqual(old.stages,WorkoutPlan.beginner.stages)
    }
    func testCountdownPausesAndContinuesForTheChosenStage() {
        var engine=WorkoutEngine(plan:.week2,at:start)
        _ = engine.skipPreparation(at:start)
        _ = engine.advance(to:start.addingTimeInterval(30))
        XCTAssertEqual(engine.record.stageRemainingSeconds,60)
        _ = engine.pause(at:start.addingTimeInterval(30))
        _ = engine.advance(to:start.addingTimeInterval(100))
        XCTAssertEqual(engine.record.stageRemainingSeconds,60)
        engine.resume(at:start.addingTimeInterval(100))
        _ = engine.advance(to:start.addingTimeInterval(160))
        XCTAssertEqual(engine.record.stage.kind,.walk)
        XCTAssertEqual(engine.record.stageRemainingSeconds,120)
    }
    func testFreeRunTotalIncludesWarmupAndFinishedRecordKeepsBothDistances() {
        var engine=WorkoutEngine(plan:.freeRun,at:start)
        _ = engine.ingest(point(0,0)); _ = engine.ingest(point(30,10))
        XCTAssertEqual(engine.record.totalMeters,30,accuracy:0.02)
        XCTAssertEqual(engine.record.mainMeters,0)
        _ = engine.skipPreparation(at:start.addingTimeInterval(10))
        _ = engine.ingest(point(30,11)); _ = engine.ingest(point(60,21))
        _ = engine.finish(at:start.addingTimeInterval(21))
        XCTAssertEqual(engine.record.totalMeters,60,accuracy:0.02)
        XCTAssertEqual(engine.record.mainMeters,30,accuracy:0.02)
        XCTAssertTrue(engine.record.completedPlan)
    }
    func testThirtySecondReportsUseCurrentPaceNotCallbackCountAndStayOffline() {
        var engine=WorkoutEngine(plan:.freeRun,at:start,targetPace:350)
        _ = engine.skipPreparation(at:start)
        _ = engine.ingest(point(0,0))
        var reportTimes:[Int]=[]
        for second in 1...120 {
            _ = engine.ingest(point(Double(second)*3,Double(second)))
            if let report=engine.takePaceReport(audioIdle:true) {
                reportTimes.append(second)
                XCTAssertTrue(report.speech.contains("当前配速每公里5分33秒"))
                XCTAssertTrue(report.speech.contains("刚刚好"))
                XCTAssertNil(report.fixedVoiceCue)
            }
        }
        XCTAssertEqual(reportTimes,[30,60,90,120])
    }
    func testInclusiveOneMinuteToleranceAndNoInventedTarget() {
        for pace in [390.0,450.0,510.0] { XCTAssertTrue(PaceReminder.periodicSpeech(pace:pace,target:450).contains("刚刚好")) }
        XCTAssertTrue(PaceReminder.periodicSpeech(pace:389,target:450).contains("有点快了"))
        XCTAssertTrue(PaceReminder.periodicSpeech(pace:511,target:450).contains("有点慢了"))
        XCTAssertFalse(PaceReminder.periodicSpeech(pace:511,target:nil).contains("目标"))
        XCTAssertFalse(PaceReminder.periodicSpeech(pace:511,target:nil).contains("加快"))
    }
    func testNoPaceWithoutGPSOrDuringWalkAndNoBurstAfterResume() throws {
        var engine=WorkoutEngine(plan:.beginner,at:start)
        _ = engine.skipPreparation(at:start)
        _ = engine.advance(to:start.addingTimeInterval(30))
        XCTAssertNil(engine.takePaceReport(audioIdle:true))
        _ = engine.ingest(point(0,30))
        _ = engine.ingest(point(30,40))
        XCTAssertNil(engine.takePaceReport(audioIdle:false))
        XCTAssertNotNil(engine.takePaceReport(audioIdle:true))
        XCTAssertNil(engine.takePaceReport(audioIdle:true))
        _ = engine.advance(to:start.addingTimeInterval(80))
        XCTAssertEqual(engine.record.stage.kind,.walk)
        XCTAssertNil(engine.takePaceReport(audioIdle:true))
        _ = engine.pause(at:start.addingTimeInterval(80))
        engine.resume(at:start.addingTimeInterval(200))
        XCTAssertNil(engine.takePaceReport(audioIdle:true))
    }
    func testSelectedOneMinuteIntervalAndDisabledTimerDoNotCatchUp() {
        var engine=WorkoutEngine(plan:.freeRun,at:start)
        _ = engine.skipPreparation(at:start)
        _ = engine.ingest(point(0,0))
        var times:[Int]=[]
        for second in 1...180 {
            _ = engine.ingest(point(Double(second)*3,Double(second)))
            if engine.takePaceReport(audioIdle:true,interval:60,enabled:true) != nil { times.append(second) }
        }
        XCTAssertEqual(times,[60,120,180])
        for second in 181...300 {
            _ = engine.ingest(point(Double(second)*3,Double(second)))
            XCTAssertNil(engine.takePaceReport(audioIdle:true,interval:60,enabled:false))
        }
        for second in 301...359 {
            _ = engine.ingest(point(Double(second)*3,Double(second)))
            XCTAssertNil(engine.takePaceReport(audioIdle:true,interval:60,enabled:true))
        }
        _ = engine.ingest(point(1080,360))
        XCTAssertNotNil(engine.takePaceReport(audioIdle:true,interval:60,enabled:true))
    }
    func testChangingReportIntervalDuringWorkoutUsesNewInterval() {
        var engine=WorkoutEngine(plan:.freeRun,at:start)
        _ = engine.skipPreparation(at:start)
        _ = engine.ingest(point(0,0))
        var times:[Int]=[]
        for second in 1...120 {
            _ = engine.ingest(point(Double(second)*3,Double(second)))
            if engine.takePaceReport(audioIdle:true,interval:second <= 30 ? 30 : 60) != nil { times.append(second) }
        }
        XCTAssertEqual(times,[30,90])
    }
}
