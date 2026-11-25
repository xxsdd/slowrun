import Foundation

/// Circular smoothing avoids spinning through south when crossing 359/0 degrees.
public struct NavigationOrientation: Sendable {
    public private(set) var bearing: Double?
    private var lastCourseAt: Date?
    private var lastHeadingAt: Date?
    public init() {}
    public static func normalized(_ angle: Double) -> Double { (angle.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) }
    public static func delta(from: Double, to: Double) -> Double { normalized(to - from + 180) - 180 }
    public mutating func motion(_ point: TrackPoint, at now: Date) {
        guard point.accuracy >= 0, point.accuracy <= 20,
              now.timeIntervalSince(point.timestamp) >= -1, now.timeIntervalSince(point.timestamp) <= 5,
              (point.speed ?? -1) >= 0.8, let course = point.course, course.isFinite, (0..<360).contains(course),
              let accuracy = point.courseAccuracy, accuracy.isFinite, (0...35).contains(accuracy),
              lastCourseAt.map({ point.timestamp > $0 }) ?? true else { return }
        lastCourseAt = point.timestamp; smooth(course, fraction: 0.35)
    }
    public mutating func heading(_ degrees: Double, accuracy: Double, timestamp: Date, at now: Date) {
        guard degrees.isFinite, (0..<360).contains(degrees), accuracy.isFinite, (0...25).contains(accuracy),
              now.timeIntervalSince(timestamp) >= -1, now.timeIntervalSince(timestamp) <= 3,
              lastHeadingAt.map({ timestamp > $0 }) ?? true else { return }
        lastHeadingAt = timestamp
        guard lastCourseAt.map({ now.timeIntervalSince($0) > 3 }) ?? true else { return }
        smooth(degrees, fraction: 0.25)
    }
    private mutating func smooth(_ angle: Double, fraction: Double) {
        bearing = bearing.map { Self.normalized($0 + Self.delta(from: $0, to: angle) * fraction) } ?? angle
    }
}

public struct NavigationDisplayPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
}
public struct NavigationLocalMap: Sendable {
    public var points: [NavigationDisplayPoint]
    public var position: NavigationDisplayPoint
    public var turn: NavigationDisplayPoint?
    /// Fits a short, metrically correct portion into the 148 x 78 point card.
    public init?(route: NavigationRoute, progress: Double, position: NavigationCoordinate, bearing: Double, turnProgress: Double?) {
        guard position.isValid, bearing.isFinite, route.points.count >= 2 else { return nil }
        let total = route.totalMeters
        let lower = max(0, progress - 18)
        let upper = min(total, progress + min(220, max(90, (turnProgress ?? progress + 90) - progress + 30)))
        func at(_ distance: Double) -> NavigationCoordinate? {
            route.project(position, from: max(0, distance), through: max(0, distance))?.coordinate
        }
        guard let start = at(lower), let end = at(upper) else { return nil }
        var samples: [(Double, NavigationCoordinate)] = [(lower, start), (upper, end)]
        var cursor = 0.0
        for index in 1..<route.points.count {
            cursor += route.points[index - 1].distance(to: route.points[index])
            if cursor > lower && cursor < upper { samples.append((cursor, route.points[index])) }
        }
        let turnCoordinate = turnProgress.flatMap { $0 >= lower && $0 <= upper ? at($0) : nil }
        if let t = turnProgress, let c = turnCoordinate { samples.append((t, c)) }
        samples.sort { $0.0 < $1.0 }
        let radians = bearing * .pi / 180
        let longitudeScale = cos(position.latitude * .pi / 180) * 111_194.9266
        func rotate(_ c: NavigationCoordinate) -> NavigationDisplayPoint {
            let east = (c.longitude - position.longitude) * longitudeScale
            let north = (c.latitude - position.latitude) * 111_194.9266
            return .init(x: east * cos(radians) - north * sin(radians), y: -(east * sin(radians) + north * cos(radians)))
        }
        var path = samples.map { rotate($0.1) }
        // Remove the least significant vertices, protecting the turn anchor.
        let marker = turnCoordinate.map(rotate)
        while path.count > 28 {
            let candidates = (1..<(path.count - 1)).filter { marker != path[$0] }
            guard let index = candidates.min(by: { Self.deviation(path[$0], path[$0 - 1], path[$0 + 1]) < Self.deviation(path[$1], path[$1 - 1], path[$1 + 1]) }) else { break }
            path.remove(at: index)
        }
        let all = path + [.init(x: 0, y: 0)]
        let minX = all.map(\.x).min()!, maxX = all.map(\.x).max()!
        let minY = all.map(\.y).min()!, maxY = all.map(\.y).max()!
        let width = 132.0, height = 62.0
        let scale = max(max(25, maxX - minX) / width, max(25, maxY - minY) / height)
        let centerX = (minX + maxX) / 2, centerY = (minY + maxY) / 2
        func normalize(_ p: NavigationDisplayPoint) -> NavigationDisplayPoint {
            .init(x: ((0.5 + (p.x - centerX) / (scale * width)) * 1000).rounded() / 1000,
                  y: ((0.5 + (p.y - centerY) / (scale * height)) * 1000).rounded() / 1000)
        }
        points = path.map(normalize); self.position = normalize(.init(x: 0, y: 0)); turn = marker.map(normalize)
    }
    private static func deviation(_ p: NavigationDisplayPoint, _ a: NavigationDisplayPoint, _ b: NavigationDisplayPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / max(0.001, dx * dx + dy * dy)))
        return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
    }
}
