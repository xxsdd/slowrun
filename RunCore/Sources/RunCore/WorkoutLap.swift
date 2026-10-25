import Foundation

public struct WorkoutLap: Identifiable, Equatable, Sendable {
    public let id: Int
    public let meters: Double
    public let seconds: Double
    public let isPartial: Bool
    public var title: String { isPartial ? "最后 \(Int(meters)) 米" : "第 \(id) 公里" }
}

extension WorkoutRecord {
    /// Full kilometre boundary times are already interpolated by the engine.
    /// Only main-training time/distance enters the final partial lap.
    public var laps: [WorkoutLap] {
        var result = splits.map { WorkoutLap(id: $0.kilometer, meters: 1_000, seconds: $0.seconds, isPartial: false) }
        let lastKilometer = splits.last?.kilometer ?? 0
        let remainder = mainMeters - Double(lastKilometer) * 1_000
        let seconds = mainSeconds - (splits.last?.cumulativeSeconds ?? 0)
        if remainder >= 1, seconds > 0 {
            result.append(WorkoutLap(id: lastKilometer + 1, meters: remainder, seconds: seconds, isPartial: true))
        }
        return result
    }
}
