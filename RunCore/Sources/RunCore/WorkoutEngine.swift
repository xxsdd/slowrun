import Foundation

public struct WorkoutEngine: Codable, Sendable {
    public private(set) var record: WorkoutRecord
    private var lastClock: Date
    private var previousPoint: TrackPoint?
    private var previousMainSeconds: Double = 0
    private var segment = 0
    private var speedWindow: [SpeedReading] = []
    private var coachingProgress: CoachingProgress?
    private var lastPaceReportMainSeconds: Double?
    private var lastMotionAt: Date?
    private struct SpeedReading: Codable, Sendable { let at: Date; let meters: Double; let seconds: Double }

    public init(plan: WorkoutPlan, at: Date = Date(), weightKg: Double? = nil, targetPace: Double? = nil, session: Int = 1, freeRunSeconds: Double? = nil, freeWalkSeconds: Double? = nil) {
        lastClock = at
        record = WorkoutRecord(id: UUID(), plan: plan, startedAt: at, endedAt: nil, status: .active, stageIndex: 0, stageSeconds: 0, elapsedSeconds: 0, mainSeconds: 0, totalMeters: 0, mainMeters: 0, mainSteps: 0, cadence: nil, currentPace: nil, lastGPSAt: nil, calories: weightKg == nil ? nil : 0, weightKg: weightKg, targetPace: targetPace, track: [], splits: [], paceSamples: [], effort: nil, completedPlan: false, aiReview: nil)
        record.statisticsVersion = 2
        record.phaseStatistics = PhaseStatistics(); record.activitySpans = []; record.runSeconds = 0
        record.freeRunSeconds = freeRunSeconds.map { $0.isFinite ? min(3600, max(15, $0)) : 180 }
        record.freeWalkSeconds = freeWalkSeconds.map { $0.isFinite ? min(3600, max(0, $0)) : 120 }
        record.session = plan.isBeginner ? min(3, max(1, session)) : nil
    }

    public mutating func advance(to now: Date) -> [WorkoutEvent] {
        guard now >= lastClock else { return [] }
        var remaining = now.timeIntervalSince(lastClock)
        lastClock = now
        guard record.status == .active else { return [] }
        var events: [WorkoutEvent] = []
        while remaining > 0, record.status == .active {
            let stage = record.stage
            let untilEnd = stage.seconds.map { max(0, $0 - record.stageSeconds) } ?? remaining
            let used = min(remaining, untilEnd)
            let spanStart = now.addingTimeInterval(-remaining)
            let spanEnd = spanStart.addingTimeInterval(used)
            if used > 0, record.activitySpans != nil {
                if let last = record.activitySpans?.last, last.kind == stage.kind, abs(last.end.timeIntervalSince(spanStart)) < 0.001 {
                    record.activitySpans![record.activitySpans!.count - 1].end = spanEnd
                } else { record.activitySpans?.append(ActivitySpan(start: spanStart, end: spanEnd, kind: stage.kind)) }
            }
            record.elapsedSeconds += used; record.stageSeconds += used
            record.phaseStatistics?[stage.kind.phase].seconds += used
            if stage.kind == .run { record.runSeconds = (record.runSeconds ?? 0) + used }
            if stage.kind.isMain { record.mainSeconds += used }
            if let weight = record.weightKg {
                // Broad activity estimate, not a measured calorie count. Subtract resting MET.
                let recentPace = record.lastGPSAt.flatMap { spanStart.timeIntervalSince($0) <= 15 ? record.currentPace : nil }
                let met = ActivityEnergy.met(kind: stage.kind, pace: recentPace)
                let amount = (met - 1) * 3.5 * weight / 200 * used / 60
                record.calories = (record.calories ?? 0) + amount
                if record.phaseStatistics != nil {
                    let previous = record.phaseStatistics![stage.kind.phase].calories ?? 0
                    record.phaseStatistics![stage.kind.phase].calories = previous + amount
                }
            }
            remaining -= used
            if let duration = stage.seconds, record.stageSeconds >= duration {
                events += nextStage(at: now.addingTimeInterval(-remaining))
            } else { break }
        }
        if let last = record.lastGPSAt, now.timeIntervalSince(last) > 15 { record.currentPace = nil }
        if let lastMotionAt, now.timeIntervalSince(lastMotionAt) > 15 { record.cadence = nil }
        return events
    }

    public mutating func pause(at now: Date) -> [WorkoutEvent] {
        let events = advance(to: now)
        guard record.status == .active else { return events }
        record.status = .paused; record.currentPace = nil; record.cadence = nil; breakTrack()
        return events
    }
    public mutating func resume(at now: Date) {
        guard record.status == .paused else { return }
        lastClock = now; record.status = .active; breakTrack()
        lastPaceReportMainSeconds = record.mainSeconds
    }
    public mutating func recoverPaused(at now: Date) {
        guard record.status != .finished else { return }
        record.status = .paused; record.currentPace = nil; record.cadence = nil
        lastClock = now; breakTrack()
        notePriorityCue()
        lastPaceReportMainSeconds = record.mainSeconds
    }
    public mutating func notePriorityCue() {
        if coachingProgress == nil { coachingProgress = CoachingProgress() }
        coachingProgress?.lastPriorityElapsed = record.elapsedSeconds
    }
    public mutating func takeCoachingTip(enabled: Bool, audioIdle: Bool) -> WorkoutEvent? {
        if coachingProgress == nil { coachingProgress = CoachingProgress() }
        guard coachingProgress?.takeTip(record: record, enabled: enabled, audioIdle: audioIdle) == true else { return nil }
        return .coaching
    }
    public mutating func takePaceReport(audioIdle: Bool, interval: Double = 30, enabled: Bool = true) -> WorkoutEvent? {
        guard enabled else { lastPaceReportMainSeconds = record.mainSeconds; return nil }
        let safeInterval = interval.isFinite ? min(300, max(30, interval)) : 30
        guard record.status == .active, record.stage.kind == .run,
              record.stageSeconds >= 20,
              record.stageRemainingSeconds.map({ $0 >= 15 }) ?? true,
              record.mainSeconds - (lastPaceReportMainSeconds ?? 0) >= safeInterval,
              let lastGPS = record.lastGPSAt, lastClock.timeIntervalSince(lastGPS) <= 15,
              let pace = record.currentPace, pace.isFinite, pace > 0,
              audioIdle else { return nil }
        // One live snapshot, never catch-up bursts after a delayed callback.
        lastPaceReportMainSeconds = record.mainSeconds
        return .paceReport(pace: pace, target: record.targetPace, remaining: record.stageRemainingSeconds)
    }
    public mutating func finish(at now: Date) -> [WorkoutEvent] {
        var events = advance(to: now)
        guard record.status != .finished else { return events }
        record.status = .finished; record.endedAt = now; record.currentPace = nil; record.cadence = nil
        if record.plan == .freeRun { record.completedPlan = record.mainSeconds > 0 || record.mainMeters > 0 }
        breakTrack(); events.append(.finished); return events
    }
    public mutating func skipPreparation(at now: Date) -> [WorkoutEvent] {
        var events = advance(to: now)
        guard record.status == .active, [.warmup, .cooldown].contains(record.stage.kind) else { return events }
        events += nextStage(at: now); return events
    }
    public mutating func beginCooldown(at now: Date) -> [WorkoutEvent] {
        var events = advance(to: now)
        guard record.status != .finished, record.stage.kind != .cooldown else { return events }
        if record.plan == .freeRun { record.completedPlan = record.mainSeconds > 0 || record.mainMeters > 0 }
        record.stageIndex = record.stages.count - 1; record.stageSeconds = 0
        record.status = .active; lastClock = now; breakTrack(); record.currentPace = nil
        events.append(.stage(.cooldown)); return events
    }
    public mutating func recordMotion(steps: Int, cadence: Double?, from start: Date? = nil, to end: Date? = nil) {
        guard record.status == .active else { return }
        lastMotionAt = end ?? lastClock
        let count = max(0, steps)
        if let start, let end, end > start, let spans = record.activitySpans {
            let overlaps = WorkoutPhase.allCases.map { phase in
                spans.filter { $0.kind.phase == phase }.reduce(0.0) { $0 + max(0, min(end, $1.end).timeIntervalSince(max(start, $1.start))) }
            }
            let total = overlaps.reduce(0, +)
            if total > 0 {
                var assigned = 0
                let last = overlaps.lastIndex(where: { $0 > 0 })!
                for (index, phase) in WorkoutPhase.allCases.enumerated() where overlaps[index] > 0 {
                    let portion = index == last ? count - assigned : Int((Double(count) * overlaps[index] / total).rounded(.down))
                    addSteps(portion, phase: phase); assigned += portion
                }
            }
        } else { addSteps(count, phase: record.currentPhase) }
        record.cadence = cadence.flatMap { $0 > 0 && $0 < 300 ? $0 : nil }
    }
    private mutating func addSteps(_ steps: Int, phase: WorkoutPhase) {
        if phase == .main { record.mainSteps += steps }
        if record.phaseStatistics != nil { record.phaseStatistics![phase].steps = (record.phaseStatistics![phase].steps ?? 0) + steps }
    }
    public mutating func finalizeSteps(_ values: [WorkoutPhase: Int?]) {
        guard record.phaseStatistics != nil else { return }
        for phase in WorkoutPhase.allCases { record.phaseStatistics![phase].steps = values[phase] ?? nil }
        record.mainSteps = record.phaseStatistics!.main.steps ?? 0
        record.stepsFinalized = true
    }

    public mutating func ingest(_ point: TrackPoint, receivedAt now: Date? = nil) -> [WorkoutEvent] {
        let received = now ?? point.timestamp
        var events = advance(to: received)
        guard record.status == .active,
              point.accuracy >= 0, point.accuracy <= 35,
              abs(point.latitude) <= 90, abs(point.longitude) <= 180,
              received.timeIntervalSince(point.timestamp) <= 15,
              point.timestamp.timeIntervalSince(received) <= 3 else { return events }
        if let latest = record.lastGPSAt, point.timestamp <= latest { return events }
        guard let previous = previousPoint else { anchor(point); return events }
        let seconds = point.timestamp.timeIntervalSince(previous.timestamp)
        guard seconds > 0 else { return events }
        let meters = previous.distance(to: point)
        guard seconds <= 20 else { breakTrack(); anchor(point); return events }
        guard meters / seconds <= 10 else { record.currentPace = nil; breakTrack(); return events }
        if let speed = point.speed, speed >= 0, speed < 0.5 {
            previousPoint = point; previousMainSeconds = record.mainSeconds
            record.lastGPSAt = point.timestamp; record.currentPace = nil; speedWindow.removeAll(); return events
        }
        guard meters >= 2 else { return events }
        record.totalMeters += meters
        let measuredPhase = record.currentPhase
        record.phaseStatistics?[measuredPhase].meters += meters
        if record.stage.kind.isMain {
            let before = record.mainMeters
            let after = before + meters
            let currentMainSeconds = record.mainSeconds
            let countedAfter = after
            record.mainMeters = countedAfter
            while Double(record.splits.count + 1) * 1_000 <= countedAfter {
                let kilometer = record.splits.count + 1
                let fraction = (Double(kilometer) * 1_000 - before) / meters
                let crossedAt = previousMainSeconds + (currentMainSeconds - previousMainSeconds) * fraction
                let lap = crossedAt - (record.splits.last?.cumulativeSeconds ?? 0)
                record.splits.append(KilometerSplit(kilometer: kilometer, seconds: lap, cumulativeSeconds: crossedAt))
                events.append(.kilometer(kilometer, lap, crossedAt))
            }
        }
        speedWindow.append(SpeedReading(at: point.timestamp, meters: meters, seconds: seconds))
        speedWindow.removeAll { point.timestamp.timeIntervalSince($0.at) > 20 }
        let windowMeters = speedWindow.reduce(0) { $0 + $1.meters }
        let windowSeconds = speedWindow.reduce(0) { $0 + $1.seconds }
        record.currentPace = windowMeters >= 5 ? windowSeconds / windowMeters * 1_000 : nil
        if let pace = record.currentPace, record.stage.kind.isMain,
           record.paceSamples.last.map({ record.mainSeconds - $0.elapsedSeconds >= 5 }) ?? true {
            record.paceSamples.append(PaceSample(elapsedSeconds: record.mainSeconds, secondsPerKilometer: pace))
        }
        anchor(point)
        // Periodic pace reports are scheduled by takePaceReport, not by GPS
        // callback count. This replaces the old sustained-deviation warnings.
        if let target = record.plan.targetMeters, record.mainMeters >= target, record.stage.kind == .run {
            events += nextStage(at: received)
        }
        return events
    }

    private mutating func anchor(_ point: TrackPoint) {
        var value = point; value.segment = segment
        previousPoint = value; previousMainSeconds = record.mainSeconds; record.lastGPSAt = point.timestamp
        record.track.append(value)
    }
    private mutating func breakTrack() {
        previousPoint = nil; segment += 1; speedWindow.removeAll()
    }
    private mutating func nextStage(at now: Date) -> [WorkoutEvent] {
        breakTrack(); record.currentPace = nil
        if record.plan == .freeRun, record.stage.kind == .walk, (record.freeWalkSeconds ?? 0) > 0 {
            record.stageIndex = 1; record.stageSeconds = 0
            lastPaceReportMainSeconds = record.mainSeconds
            return [.stage(.run)]
        }
        guard record.stageIndex + 1 < record.stages.count else {
            record.status = .finished; record.endedAt = now
            return [.finished]
        }
        let previousKind = record.stage.kind
        record.stageIndex += 1; record.stageSeconds = 0
        if record.stage.kind == .cooldown && previousKind.isMain { record.completedPlan = true }
        lastPaceReportMainSeconds = record.mainSeconds
        return record.plan == .freeRun && previousKind == .warmup ? [.freeRunStarted] : [.stage(record.stage.kind)]
    }
}
