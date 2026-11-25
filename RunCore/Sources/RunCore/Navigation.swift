import Foundation

public struct NavigationCoordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double) { self.latitude = latitude; self.longitude = longitude }
    public var isValid: Bool { latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) }
    public func distance(to other: Self) -> Double {
        TrackPoint(latitude: latitude, longitude: longitude, timestamp: .distantPast, accuracy: 0)
            .distance(to: TrackPoint(latitude: other.latitude, longitude: other.longitude, timestamp: .distantPast, accuracy: 0))
    }
}

public struct SavedDestination: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var address: String
    public var coordinate: NavigationCoordinate
    public var nickname: String?
    public var displayName: String { nickname?.isEmpty == false ? nickname! : name }
    public init(id: UUID = UUID(), name: String, address: String = "", coordinate: NavigationCoordinate, nickname: String? = nil) {
        self.id = id; self.name = name; self.address = address; self.coordinate = coordinate; self.nickname = nickname
    }
}

public struct DestinationSearchResult: Identifiable, Sendable {
    public let place: SavedDestination
    public let distanceMeters: Double?
    public var id: UUID { place.id }

    public static func ranked(_ places: [SavedDestination], from origin: NavigationCoordinate?) -> [Self] {
        let results = places.filter { $0.coordinate.isValid }.map { place in
            Self(place: place, distanceMeters: origin.flatMap { coordinate in
                coordinate.isValid ? coordinate.distance(to: place.coordinate) : nil
            })
        }
        // Swift's stable sort retains relevance order for ties or missing location.
        return results.sorted { ($0.distanceMeters ?? .infinity) < ($1.distanceMeters ?? .infinity) }
    }
}

public enum NavigationTurn: String, Codable, Sendable {
    case left, right, uTurn, straight, unknown
    public var symbol: String {
        switch self { case .left: return "arrow.turn.up.left"; case .right: return "arrow.turn.up.right"; case .uTurn: return "arrow.uturn.down"; case .straight: return "arrow.up"; case .unknown: return "map" }
    }
    public static func parse(_ instruction: String) -> Self {
        let s = instruction.lowercased()
        if ["roundabout", "环岛", "圓環", "圆环", "出口", "exit", "fork", "岔"].contains(where: s.contains) { return .unknown }
        if ["u-turn", "u turn", "掉头", "掉頭"].contains(where: s.contains) { return .uTurn }
        if ["左转", "左轉", "向左"].contains(where: s.contains) { return .left }
        if ["右转", "右轉", "向右"].contains(where: s.contains) { return .right }
        let words = s.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        if let action = words.firstIndex(where: { ["turn", "keep", "bear", "make"].contains($0) }) {
            if let direction = words.dropFirst(action + 1).prefix(4).first(where: { $0 == "left" || $0 == "right" }) { return direction == "left" ? .left : .right }
        } else if words.first == "left" || words.first == "right" { return words.first == "left" ? .left : .right }
        if ["straight", "continue", "head ", "直行", "继续", "繼續"].contains(where: s.contains) { return .straight }
        return .unknown
    }
}

public struct NavigationManeuver: Codable, Identifiable, Equatable, Sendable {
    public var id: Int
    public var metersFromStart: Double
    public var turn: NavigationTurn
    public var instruction: String
    public init(id: Int, metersFromStart: Double, turn: NavigationTurn, instruction: String) {
        self.id = id; self.metersFromStart = metersFromStart; self.turn = turn; self.instruction = instruction
    }
}

public struct NavigationRoute: Codable, Sendable {
    public var id: UUID
    public var points: [NavigationCoordinate]
    public var maneuvers: [NavigationManeuver]
    public init(id: UUID = UUID(), points: [NavigationCoordinate], maneuvers: [NavigationManeuver]) {
        self.id = id; self.points = points
        self.maneuvers = maneuvers.sorted { $0.metersFromStart < $1.metersFromStart }
    }
    public var totalMeters: Double { zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) } }

    /// Verify ordinary left/right instructions against the path drawn at their
    /// marker. Keep special instructions (such as roundabouts) separate.
    public func resolvingTurnDirections() -> Self {
        guard let firstPoint = points.first else { return self }
        let sorted = maneuvers.sorted { $0.metersFromStart < $1.metersFromStart }
        let routeEnd = totalMeters
        func point(at distance: Double) -> NavigationCoordinate? {
            project(firstPoint, from: distance, through: distance)?.coordinate
        }
        func turn(at anchor: NavigationCoordinate, approach: NavigationCoordinate, exit: NavigationCoordinate) -> NavigationTurn {
            let longitudeScale = cos(anchor.latitude * .pi / 180)
            let inEast = (anchor.longitude - approach.longitude) * longitudeScale
            let inNorth = anchor.latitude - approach.latitude
            let outEast = (exit.longitude - anchor.longitude) * longitudeScale
            let outNorth = exit.latitude - anchor.latitude
            // Geographic east/north axes have positive cross product for left.
            let angle = atan2(inEast * outNorth - inNorth * outEast, inEast * outEast + inNorth * outNorth) * 180 / .pi
            guard (20...150).contains(abs(angle)) else { return .unknown }
            return angle > 0 ? .left : .right
        }
        let corrected = sorted.enumerated().map { index, original in
            var step = original
            guard original.turn == .left || original.turn == .right else { return step }
            let anchor = step.metersFromStart
            let previous = index > 0 ? sorted[index - 1].metersFromStart : 0
            let next = index + 1 < sorted.count ? sorted[index + 1].metersFromStart : routeEnd
            // Stay inside adjacent turns, and compare two window sizes so a
            // curb jog or a bend beyond the marker can't easily flip the arrow.
            let radius = min(16, (anchor - previous) * 0.85, (next - anchor) * 0.85)
            if radius >= 4, let center = point(at: anchor),
               let nearIn = point(at: anchor - radius * 0.55), let nearOut = point(at: anchor + radius * 0.55),
               let farIn = point(at: anchor - radius), let farOut = point(at: anchor + radius) {
                let near = turn(at: center, approach: nearIn, exit: nearOut)
                let far = turn(at: center, approach: farIn, exit: farOut)
                step.turn = near == far ? near : .unknown
            } else {
                step.turn = .unknown
            }
            if step.turn != original.turn { step.instruction = "请沿地图标记的路线通过路口" }
            return step
        }
        return Self(id: id, points: points, maneuvers: corrected)
    }
    public struct Projection: Sendable { public var progress: Double; public var distance: Double; public var coordinate: NavigationCoordinate }
    public func project(_ point: NavigationCoordinate, from minimum: Double = 0, through maximum: Double = .infinity) -> Projection? {
        guard point.isValid, points.count >= 2 else { return nil }
        var cursor = 0.0
        var best: Projection?
        let scaleX = cos(point.latitude * .pi / 180) * 111_194.9266
        let scaleY = 111_194.9266
        for (a, b) in zip(points, points.dropFirst()) {
            let length = a.distance(to: b), end = cursor + length
            defer { cursor = end }
            guard length > 0.01, end >= minimum, cursor <= maximum else { continue }
            let ax = (a.longitude - point.longitude) * scaleX, ay = (a.latitude - point.latitude) * scaleY
            let dx = (b.longitude - a.longitude) * scaleX, dy = (b.latitude - a.latitude) * scaleY
            let lower = max(0, (minimum - cursor) / length), upper = min(1, (maximum - cursor) / length)
            guard lower <= upper else { continue }
            let t = min(upper, max(lower, -(ax * dx + ay * dy) / max(0.0001, dx * dx + dy * dy)))
            let coordinate = NavigationCoordinate(latitude: a.latitude + (b.latitude - a.latitude) * t, longitude: a.longitude + (b.longitude - a.longitude) * t)
            let candidate = Projection(progress: cursor + t * length, distance: point.distance(to: coordinate), coordinate: coordinate)
            if best == nil || candidate.distance < best!.distance { best = candidate }
        }
        return best
    }
    /// Fixed-count sampling keeps the entire ActivityKit state below its budget.
    public func simplified(limit: Int = 18) -> [NavigationCoordinate] {
        guard points.count > limit, limit >= 2 else { return points }
        return (0..<limit).map { points[Int((Double($0) * Double(points.count - 1) / Double(limit - 1)).rounded())] }
    }
}

public struct WalkingRouteSummary {
    public let distance: Double
    public let turns: Int
    public init(distance: Double, turns: Int) {
        self.distance = distance
        self.turns = turns
    }

    /// Prefer simpler turns when they save enough effort to justify a small detour.
    public static func recommendedIndex(in routes: [Self]) -> Int? {
        let valid = routes.indices.filter { routes[$0].distance.isFinite && routes[$0].distance > 0 }
        guard let shortest = valid.map({ routes[$0].distance }).min() else { return nil }
        let limit = shortest + min(shortest * 0.10, 200)
        return valid.filter { routes[$0].distance <= limit }.min { first, second in
            let a = routes[first], b = routes[second]
            let scoreA = a.distance + 35 * Double(a.turns)
            let scoreB = b.distance + 35 * Double(b.turns)
            if scoreA != scoreB { return scoreA < scoreB }
            return a.distance < b.distance
        }
    }
}

public enum NavigationVoice: String, CaseIterable, Codable, Sendable {
    case advanceLeft, advanceRight, advanceUTurn, advanceUnknown, nearLeft, nearRight, nearUTurn, nearUnknown, rerouting, arrived
    public var speech: String {
        switch self {
        case .advanceLeft: return "前方五十米左转。"
        case .advanceRight: return "前方五十米右转。"
        case .advanceUTurn: return "前方五十米掉头。"
        case .advanceUnknown: return "前方路口，请查看路线。"
        case .nearLeft: return "在这里左转。"
        case .nearRight: return "在这里右转。"
        case .nearUTurn: return "在这里掉头。"
        case .nearUnknown: return "请按地图指示通过路口。"
        case .rerouting: return "正在重新规划路线。"
        case .arrived: return "已到达目的地，训练继续。"
        }
    }
}

public struct NavigationCue: Equatable, Sendable {
    public var voice: NavigationVoice
    public var routeID: UUID
    public var maneuverID: Int?
    public var createdAt: Date
    public init(voice: NavigationVoice, routeID: UUID, maneuverID: Int? = nil, createdAt: Date = Date()) {
        self.voice = voice; self.routeID = routeID; self.maneuverID = maneuverID; self.createdAt = createdAt
    }
}

public enum NavigationEvent: Sendable { case cue(NavigationCue), reroute }

public struct NavigationEngine: Sendable {
    public private(set) var route: NavigationRoute
    public private(set) var progress = 0.0
    public private(set) var arrived = false
    public private(set) var needsReroute = false
    public private(set) var lastTrustedAt: Date?
    public private(set) var position: NavigationCoordinate?
    private var previousTimestamp: Date?
    private var goodFixes = 0
    private var offRouteSince: Date?
    private var offRouteCount = 0
    private var advanced: Set<Int> = []
    private var near: Set<Int> = []
    public init(route: NavigationRoute) { self.route = route }
    public var remainingMeters: Double { max(0, route.totalMeters - progress) }
    public var nextManeuver: NavigationManeuver? { route.maneuvers.first { $0.metersFromStart >= progress - 8 } }
    public var maneuverRemaining: Double? { nextManeuver.map { max(0, $0.metersFromStart - progress) } }
    public mutating func update(_ fix: TrackPoint, receivedAt now: Date) -> [NavigationEvent] {
        let coordinate = NavigationCoordinate(latitude: fix.latitude, longitude: fix.longitude)
        guard !arrived, !needsReroute, coordinate.isValid, fix.accuracy.isFinite, fix.accuracy >= 0, fix.accuracy <= 20,
              now.timeIntervalSince(fix.timestamp) >= -1, now.timeIntervalSince(fix.timestamp) <= 5,
              previousTimestamp.map({ fix.timestamp > $0 }) ?? true else { return [] }
        let delta = previousTimestamp.map { fix.timestamp.timeIntervalSince($0) } ?? 0
        previousTimestamp = fix.timestamp; goodFixes += 1
        let advance = max(120, min(300, max(0, fix.speed ?? 4) * min(delta, 30) + 50))
        guard let match = route.project(coordinate, from: max(0, progress - 25), through: progress + advance) else { return [] }
        if match.distance > max(35, fix.accuracy * 2) {
            offRouteCount += 1; offRouteSince = offRouteSince ?? fix.timestamp
            if offRouteCount >= 3, fix.timestamp.timeIntervalSince(offRouteSince!) >= 5 {
                needsReroute = true; return [.reroute]
            }
            return []
        }
        offRouteCount = 0; offRouteSince = nil
        lastTrustedAt = fix.timestamp; position = coordinate
        progress = max(progress, match.progress)
        guard goodFixes >= 2 else { return [] }
        if remainingMeters <= 18, fix.accuracy <= 10, let goal = route.points.last, coordinate.distance(to: goal) <= 22 {
            arrived = true
            return [.cue(NavigationCue(voice: .arrived, routeID: route.id, createdAt: now))]
        }
        guard let step = nextManeuver else { return [] }
        let left = step.metersFromStart - progress
        if left <= 15, left >= -8, fix.accuracy <= 10, !near.contains(step.id) {
            near.insert(step.id); advanced.insert(step.id)
            let voice: NavigationVoice
            switch step.turn { case .left: voice = .nearLeft; case .right: voice = .nearRight; case .uTurn: voice = .nearUTurn; default: voice = .nearUnknown }
            return [.cue(NavigationCue(voice: voice, routeID: route.id, maneuverID: step.id, createdAt: now))]
        }
        if left <= 55, left > 15, !advanced.contains(step.id) {
            advanced.insert(step.id)
            let voice: NavigationVoice
            switch step.turn { case .left: voice = .advanceLeft; case .right: voice = .advanceRight; case .uTurn: voice = .advanceUTurn; default: voice = .advanceUnknown }
            return [.cue(NavigationCue(voice: voice, routeID: route.id, maneuverID: step.id, createdAt: now))]
        }
        return []
    }
    public func canPlay(_ cue: NavigationCue, at now: Date) -> Bool {
        guard cue.routeID == route.id, now.timeIntervalSince(cue.createdAt) <= 12 else { return false }
        if cue.voice == .arrived { return arrived }
        guard !arrived, !needsReroute, let lastTrustedAt, now.timeIntervalSince(lastTrustedAt) <= 5,
              let id = cue.maneuverID, let step = route.maneuvers.first(where: { $0.id == id }) else { return false }
        let remaining = step.metersFromStart - progress
        switch cue.voice {
        case .advanceLeft, .advanceRight, .advanceUTurn, .advanceUnknown: return remaining > 15 && remaining <= 65
        default: return remaining >= -8 && remaining <= 20
        }
    }
}

public struct DestinationLibrary: Codable, Equatable, Sendable {
    public var favorites: [SavedDestination] = []
    public var recent: [SavedDestination] = []
    public init() {}
    public mutating func select(_ place: SavedDestination) {
        recent.removeAll { Self.same($0, place) }; recent.insert(place, at: 0); recent = Array(recent.prefix(8))
    }
    public func favorite(for place: SavedDestination) -> SavedDestination? { favorites.first { Self.same($0, place) } }
    public mutating func toggle(_ place: SavedDestination) {
        if let found = favorite(for: place) { favorites.removeAll { $0.id == found.id } }
        else if place.coordinate.isValid { favorites.append(place) }
    }
    public mutating func rename(_ id: UUID, to name: String) {
        guard let index = favorites.firstIndex(where: { $0.id == id }) else { return }
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        favorites[index].nickname = clean.isEmpty ? nil : clean
    }
    static func same(_ a: SavedDestination, _ b: SavedDestination) -> Bool { a.id == b.id || a.coordinate.distance(to: b.coordinate) < 15 && a.name == b.name }
}
