import Foundation

/// Counts time between fresh GPS readings rather than counting timer ticks.
struct PaceDeviationWindow: Codable, Sendable {
    enum Band: String, Codable { case fast, steady, slow }
    private struct Interval: Codable { let start: Date; let end: Date; let band: Band }
    private var intervals: [Interval] = []
    private var previousTime: Date?
    private var previousBand: Band?
    private var announced: Band?

    mutating func observe(at time: Date, pace: Double, target: Double) {
        let band: Band = pace < target - 10 ? .fast : pace > target + 10 ? .slow : .steady
        if let previousTime, let previousBand {
            let gap = time.timeIntervalSince(previousTime)
            guard gap > 0 else { return }
            if gap <= 6 {
                intervals.append(Interval(start: previousTime, end: time, band: previousBand))
            } else { self = Self() }
        }
        previousTime = time
        previousBand = band
        intervals.removeAll { time.timeIntervalSince($0.end) >= 30 }
        if announced != nil, band == .steady, duration(.steady, inLast: 10, at: time) >= 10 {
            announced = nil
            intervals.removeAll()
        }
    }

    mutating func take(at now: Date) -> String? {
        guard let time = previousTime, now.timeIntervalSince(time) <= 5,
              let band = previousBand, band != .steady, announced != band,
              duration(band, inLast: 30, at: time) >= 20 else { return nil }
        announced = band
        return band == .fast ? "有点快了。" : "有点慢了。"
    }

    private func duration(_ band: Band, inLast seconds: Double, at time: Date) -> Double {
        let start = time.addingTimeInterval(-seconds)
        return intervals.filter { $0.band == band }.reduce(0) { $0 + max(0, $1.end.timeIntervalSince(max(start, $1.start))) }
    }
}
