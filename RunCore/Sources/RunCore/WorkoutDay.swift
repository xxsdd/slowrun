import Foundation

/// Stable local-start date. New records carry their original time zone; legacy
/// records are grouped without mutating their saved JSON.
public enum WorkoutDay {
    public static func key(for record: WorkoutRecord, fallback: TimeZone = .current) -> String {
        if let key = record.startDayKey, !key.isEmpty { return key }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = record.startTimeZone.flatMap(TimeZone.init(identifier:)) ?? fallback
        let c = calendar.dateComponents([.year, .month, .day], from: record.startedAt)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    public static func key(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    public static func groups(_ records: [WorkoutRecord], fallback: TimeZone = .current) -> [String: [WorkoutRecord]] {
        Dictionary(grouping: records.filter { $0.status == .finished }, by: { key(for: $0, fallback: fallback) })
    }
}
public struct DailyWorkoutSummary {
    public let records: [WorkoutRecord]
    public init(_ records: [WorkoutRecord]) { self.records = records.sorted { $0.startedAt < $1.startedAt } }
    public var meters: Double { records.reduce(0) { $0 + $1.totalMeters } }
    public var seconds: Double { records.reduce(0) { $0 + $1.elapsedSeconds } }
    public var mainMeters: Double { records.reduce(0) { $0 + $1.mainMeters } }
    public var mainSeconds: Double { records.reduce(0) { $0 + $1.mainSeconds } }
    public var calorieRecordCount: Int { records.filter { $0.calories != nil }.count }
    public var calories: Double? { calorieRecordCount == 0 ? nil : records.reduce(0) { $0 + ($1.calories ?? 0) } }
    public var hasPartialCalories: Bool { calorieRecordCount > 0 && calorieRecordCount < records.count }
}
