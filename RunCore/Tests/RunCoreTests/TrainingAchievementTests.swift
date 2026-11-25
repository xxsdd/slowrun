import XCTest
@testable import RunCore

final class TrainingAchievementTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private func workout(_ day: Int, hour: Int = 12, meters: Double = 1100) -> WorkoutRecord {
        let start = Date(timeIntervalSince1970: Double(day * 86400 + hour * 3600))
        var engine = WorkoutEngine(plan: .freeRun, at: start, timeZone: utc)
        _ = engine.skipPreparation(at: start)
        _ = engine.finish(at: start.addingTimeInterval(900))
        var record = engine.record
        record.mainMeters = meters
        record.totalMeters = meters
        return record
    }

    func testFiveSeparateDaysAtSameDestinationAndDeletion() {
        let place = SavedDestination(name: "Library", coordinate: NavigationCoordinate(latitude: 49, longitude: -123))
        var visits = (0..<5).map { day -> WorkoutRecord in
            var r = workout(day)
            r.reachedDestinations = [SavedDestination(name: place.name, coordinate: place.coordinate)]
            return r
        }
        var repeated = workout(0, hour: 17)
        repeated.reachedDestinations = [place]
        visits.append(repeated)
        let results = TrainingAchievements(Array(visits.reversed()))
        XCTAssertTrue(results.unlocked.isSuperset(of: [.familiar, .twice, .evening, .lunch]))
        visits.remove(at: 2)
        XCTAssertFalse(TrainingAchievements(visits).unlocked.contains(.familiar))
        var legacy = workout(15)
        legacy.destinationWorkout = true
        XCTAssertFalse(TrainingAchievements(visits + [legacy]).unlocked.contains(.familiar))
    }

    func testSeasonWeekdayAndRouteBoundaries() {
        let history = (0..<7).map { workout($0) } + [workout(90), workout(180), workout(270)]
        XCTAssertTrue(TrainingAchievements(history).unlocked.isSuperset(of: [.seasons, .weekdays]))
        var run = workout(0, hour: 5, meters: 3000)
        let start = TrackPoint(latitude: 0, longitude: 0, timestamp: run.startedAt, accuracy: 5)
        let endDate = run.endedAt!
        let loopEnd = TrackPoint(latitude: 0, longitude: 0, timestamp: endDate, accuracy: 5)
        run.track = [start, loopEnd]
        XCTAssertTrue(TrainingAchievements([run]).unlocked.isSuperset(of: [.loop, .early, .untethered]))
        run.distanceGoalMeters = 3000
        let directEnd = TrackPoint(latitude: 0, longitude: 0.025, timestamp: endDate, accuracy: 5)
        run.track = [start, directEnd]
        let direct = TrainingAchievements([run]).unlocked
        XCTAssertTrue(direct.contains(.direct))
        XCTAssertFalse(direct.contains(.loop))
        XCTAssertFalse(direct.contains(.untethered))
    }

    func testMapStampsCountDistinctArrivalsAndAwardOnlyOnce() {
        var runs = [0, 0, 1, 2, 3, 4, 4].enumerated().map { day, index in
            var run = workout(day)
            run.reachedDestinations = [SavedDestination(name: "Park \(index)", coordinate:
                NavigationCoordinate(latitude: 49 + Double(index) / 100, longitude: -123))]
            return run
        }
        XCTAssertEqual(TrainingAchievements(Array(runs.prefix(2))).challengeProgress[.mapCollector], 1)
        let result = TrainingAchievements(Array(runs.reversed()))
        XCTAssertEqual(result.challengeProgress[.mapCollector], 5)
        let winners = runs.filter { record in
            result.awards[record.id]?.contains { if case .challenge(.mapCollector) = $0 { return true }; return false } == true
        }
        XCTAssertEqual(winners.map(\.id), [runs[5].id])
        runs.remove(at: 3)
        XCTAssertEqual(TrainingAchievements(runs).challengeProgress[.mapCollector], 4)
    }

    func testMondayWeeksAcrossNewYearAndGap() {
        // Day zero is Thursday, 1970-01-01. Day 3 is Sunday, day 4 is Monday.
        let days = [-10, -3, 3, 4, 11, 18]
        let runs = days.map { workout($0) }
        let result = TrainingAchievements(Array(runs.reversed()))
        XCTAssertEqual(result.challengeProgress[.weeklyRegular], 4)
        let winners = runs.filter { record in
            result.awards[record.id]?.contains { if case .challenge(.weeklyRegular) = $0 { return true }; return false } == true
        }
        XCTAssertEqual(winners.map(\.id), [runs[4].id])
        let gap = [-10, -3, 11, 18].map { workout($0) }
        XCTAssertEqual(TrainingAchievements(gap).challengeProgress[.weeklyRegular], 2)
    }

    func testEachMonthlyBadgeIsEarnedSeparatelyAndRepeatsNextMonth() {
        for year in [2023, 2024] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = utc
            let feb = calendar.date(from: DateComponents(year: year, month: 2, day: 1))!
            let start = Int(feb.timeIntervalSince1970 / 86400)
            let length = year == 2024 ? 29 : 28
            let runs = (0..<(length + 8)).map { workout(start + $0) }
            let duplicate = workout(start + 7, hour: 17)
            let results = TrainingAchievements(Array(([duplicate] + runs).reversed()))
            let month = TrainingMonth(date: feb, timeZone: utc)
            XCTAssertEqual(results.monthlyDays[month]?.count, length)
            let awards = runs.flatMap { record in
                (results.awards[record.id] ?? []).compactMap { award -> MonthlyBadge? in
                    guard case let .monthly(period, badge) = award else { return nil }
                    if period == month {
                        XCTAssertEqual(record.id, runs[badge.target(in: month) - 1].id)
                    }
                    return badge
                }
            }
            XCTAssertEqual(awards, MonthlyBadge.allCases + [.cover])
            XCTAssertFalse((results.awards[duplicate.id] ?? []).contains { if case .monthly = $0 { return true }; return false })
            XCTAssertTrue((results.awards[runs[length].id] ?? []).contains { if case .badge(.pageTurn) = $0 { return true }; return false })
            let gap = TrainingAchievements([runs[length - 2], runs[length]])
            XCTAssertFalse(gap.unlocked.contains(.pageTurn))
        }
    }

    func testMatchingSplitUsesConsecutiveCompleteKilometresInTheSameWorkout() {
        func split(_ km: Int, _ seconds: Double) -> KilometerSplit {
            KilometerSplit(kilometer: km, seconds: seconds, cumulativeSeconds: 0)
        }
        var run = workout(0)
        run.splits = [split(1, 452.1), split(2, 452.49)]
        XCTAssertTrue(TrainingAchievements([run]).unlocked.contains(.splitMatch))
        for pair in [[split(1, 452.49), split(2, 452.51)], [split(1, 452), split(3, 452)], [split(1, 452)]] {
            run.splits = pair
            XCTAssertFalse(TrainingAchievements([run]).unlocked.contains(.splitMatch))
        }
    }

    func testTotalsSourcesAndPersonalRecords() {
        var first = workout(0, meters: 4000)
        first.totalMeters = 6500
        first.phaseStatistics?.warmup.steps = 1000
        first.phaseStatistics?.main.steps = 3000
        first.splits = [KilometerSplit(kilometer: 1, seconds: 420, cumulativeSeconds: 420)]
        var second = workout(1, meters: 6000)
        second.splits = [KilometerSplit(kilometer: 1, seconds: 415, cumulativeSeconds: 415)]
        let result = TrainingAchievements([second, first])
        XCTAssertEqual(result.totals[.distance], 10)
        XCTAssertEqual(result.totals[.steps], 4000)
        XCTAssertEqual(result.totals[.hours], 0.5)
        XCTAssertEqual(result.longestRunSeconds, 900)
        XCTAssertEqual(result.fastestSplit, 415)
        XCTAssertTrue(result.unlocked.contains(.doubleBest))
        XCTAssertTrue(result.awards[second.id]?.contains { if case .milestone(.distance, 10) = $0 { return true }; return false } == true)
        XCTAssertEqual(TrainingMilestone.steps.thresholds.first, 100000)
    }

    func testBriefReturnToTargetDoesNotClearWindowOrRepeatAlert() {
        var window = PaceDeviationWindow()
        let start = Date(timeIntervalSince1970: 0)
        func feed(_ second: Int, _ pace: Double) -> String? {
            let now = start.addingTimeInterval(Double(second))
            window.observe(at: now, pace: pace, target: 450)
            return window.take(at: now)
        }
        for t in 0..<21 { XCTAssertNil(feed(t, t == 12 ? 450 : 439)) }
        XCTAssertEqual(feed(21, 439), "有点快了。")
        for t in 22...40 { XCTAssertNil(feed(t, 430)) }
        for t in 41...52 { XCTAssertNil(feed(t, 440)) }
        for t in 53..<73 { XCTAssertNil(feed(t, 461)) }
        XCTAssertEqual(feed(73, 461), "有点慢了。")
        XCTAssertNil(feed(160, 461))
        XCTAssertEqual(NumberVoiceScript.fragments(for: .adjustment("有点慢了。")), ["slow"])
    }
}
