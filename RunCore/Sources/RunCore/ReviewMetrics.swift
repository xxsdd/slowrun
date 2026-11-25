import Foundation

public struct ReviewInterval: Identifiable, Sendable {
    public let id: Int
    public let kind: StageKind
    public var seconds: Double
    public var meters: Double?
    public let plannedSeconds: Double?
    public var isComplete: Bool { plannedSeconds.map { seconds >= $0 - 0.5 } ?? false }
    public var pace: Double? { meters.flatMap { $0 >= 20 && seconds >= 20 ? seconds / $0 * 1000 : nil } }
}

/// New records use the same accepted GPS increments as the training engine.
/// Legacy routes are used only if their reconstruction reconciles with the saved
/// main distance. Never prorate distance by run/walk time or bridge GPS breaks.
public struct ReviewMetrics {
    public let intervals: [ReviewInterval]
    public let reconstructed: Bool
    public init(_ record: WorkoutRecord) {
        let spans = record.activitySpans ?? []
        var values = spans.map(\.meters)
        var recovered = false
        if !spans.isEmpty && spans.contains(where: { $0.kind.isMain && $0.meters == nil }) {
            var sums = Array(repeating: 0.0, count: spans.count)
            for (a, b) in zip(record.track, record.track.dropFirst()) {
                let seconds = b.timestamp.timeIntervalSince(a.timestamp), meters = a.distance(to: b)
                guard a.segment == b.segment, seconds > 0, seconds <= 20,
                      a.accuracy >= 0, a.accuracy <= 35, b.accuracy >= 0, b.accuracy <= 35,
                      meters >= 2, meters / seconds <= 10, b.speed.map({ $0 >= 0.5 }) ?? true,
                      let index = spans.firstIndex(where: { a.timestamp >= $0.start && b.timestamp <= $0.end }) else { continue }
                sums[index] += meters
            }
            let main = spans.indices.filter { spans[$0].kind.isMain }.reduce(0) { $0 + sums[$1] }
            if record.mainMeters >= 20 && abs(main - record.mainMeters) <= max(3, record.mainMeters * 0.005) {
                values = sums.map { Optional($0) }; recovered = true
            }
        }
        var result: [ReviewInterval] = []
        for (i, span) in spans.enumerated() where span.kind.isMain && span.seconds > 0 {
            let stages = record.stages.filter { $0.kind == span.kind }
            let ordinal = result.filter { $0.kind == span.kind }.count
            let planned = stages.isEmpty ? nil : stages[record.plan == .freeRun ? 0 : min(ordinal, stages.count - 1)].seconds
            // Pausing a run is not a new run interval.
            if let last = result.last, last.kind == span.kind {
                result[result.count - 1].seconds += span.seconds
                result[result.count - 1].meters = last.meters.flatMap { a in values[i].map { a + $0 } }
            } else {
                result.append(ReviewInterval(id: result.count, kind: span.kind, seconds: span.seconds, meters: values[i], plannedSeconds: planned))
            }
        }
        intervals = result; reconstructed = recovered
    }
    public func meters(_ kind: StageKind) -> Double? {
        let matching = intervals.filter { $0.kind == kind }
        guard !intervals.isEmpty, matching.allSatisfy({ $0.meters != nil }) else { return nil }
        return matching.reduce(0) { $0 + ($1.meters ?? 0) }
    }
    public func seconds(_ kind: StageKind) -> Double { intervals.filter { $0.kind == kind }.reduce(0) { $0 + $1.seconds } }
    public var completeRuns: [ReviewInterval] { intervals.filter { $0.kind == .run && $0.isComplete && $0.meters != nil } }
    public var paceChange: Double? {
        let runs = completeRuns
        guard runs.count >= 6 else { return nil }
        func pace(_ values: ArraySlice<ReviewInterval>) -> Double? {
            let meters = values.reduce(0) { $0 + ($1.meters ?? 0) }
            return meters >= 60 ? values.reduce(0) { $0 + $1.seconds } / meters * 1000 : nil
        }
        guard let first = pace(runs.prefix(3)), let last = pace(runs.suffix(3)) else { return nil }
        return last - first
    }
}

public struct DailyReview: Codable, Sendable {
    public let day: String
    public let text: String
    public let generatedAt: Date
    public let sources: [String: String]
    public init(day: String, text: String, generatedAt: Date = Date(), sources: [String: String]) {
        self.day = day; self.text = text; self.generatedAt = generatedAt; self.sources = sources
    }
    public func isCurrent(_ current: [String: String]) -> Bool { sources == current }
    public func addedCount(_ current: [String: String]) -> Int { current.keys.filter { sources[$0] == nil }.count }
}

extension WorkoutStorage {
    public func dailyReviews() throws -> [DailyReview] {
        let folder = directory.appendingPathComponent("DailyReviews", isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try JSONDecoder().decode(DailyReview.self, from: Data(contentsOf: $0)) }
    }
    public func saveDailyReview(_ value: DailyReview) throws {
        guard value.day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let folder = directory.appendingPathComponent("DailyReviews", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: folder.appendingPathComponent(value.day + ".json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
