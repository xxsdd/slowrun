import Foundation

public enum TrainingMilestone: CaseIterable {
    case distance, steps, hours

    public var thresholds: [Double] {
        switch self {
        case .distance: return [10, 50, 100, 1000, 2500, 5000]
        case .steps: return [100000, 250000, 500000, 1000000, 2500000, 5000000]
        case .hours: return [25, 50, 100, 200, 350, 500]
        }
    }
    public var checkpoints: [Double] {
        self == .distance ? (thresholds + [250, 500, 750]).sorted() : thresholds
    }
    public var title: String {
        switch self {
        case .distance: return RunLanguage.text("累计训练距离")
        case .steps: return RunLanguage.text("累计训练步数")
        case .hours: return RunLanguage.text("累计跑步时间")
        }
    }
    public func amount(_ value: Double) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...(self == .steps ? 0 : 2))))
        switch self {
        case .distance: return "\(number) km"
        case .steps: return RunLanguage.text("%1$@ 步", number)
        case .hours: return "\(number) h"
        }
    }
    public func rank(at value: Double) -> String {
        let ranks = ["起步", "青铜", "白银", "黄金", "白金", "钻石", "王者"]
        return RunLanguage.text(ranks[thresholds.filter { value >= $0 }.count])
    }
}

public enum HiddenRunBadge: String, CaseIterable {
    case familiar = "这条路我熟", loop = "家门口绕一圈", direct = "两点一线", untethered = "把地图折起来"
    case early = "城市还没醒", lunch = "午休出去一趟", evening = "傍晚这一圈", weekend = "周末睡醒再跑"
    case twice = "一天出发两次", weekdays = "星期收集家", seasons = "四季都有脚印", doubleBest = "双喜临门"
    case splitMatch = "前后脚", pageTurn = "跨页了"
}

public enum MonthlyBadge: Int, CaseIterable {
    case cover = 8, camera = 12, spread = 15, autograph = 18, collector = 25, full = 0

    public var title: String {
        switch self {
        case .cover: return RunLanguage.text("这个月的封面")
        case .camera: return RunLanguage.text("外景开拍")
        case .spread: return RunLanguage.text("双页特写")
        case .autograph: return RunLanguage.text("封面签名会")
        case .collector: return RunLanguage.text("典藏特刊")
        case .full: return RunLanguage.text("全勤金封面")
        }
    }
    public func target(in month: TrainingMonth) -> Int { self == .full ? month.length : rawValue }
}

public struct TrainingMonth: Hashable, Comparable {
    public let year: Int
    public let month: Int
    public let length: Int
    public var label: String { String(format: "%04d-%02d", year, month) }
    public init(date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        year = calendar.component(.year, from: date)
        month = calendar.component(.month, from: date)
        length = calendar.range(of: .day, in: .month, for: date)!.count
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { (lhs.year, lhs.month) < (rhs.year, rhs.month) }
}

public enum PublicRunChallenge: String, CaseIterable {
    case mapCollector = "地图集邮员"
    case weeklyRegular = "下周见，真的见"

    public var target: Int { self == .mapCollector ? 5 : 4 }
    public var rule: String {
        switch self {
        case .mapCollector: return RunLanguage.text("使用目的地导航，实际到达 5 个不同地点。")
        case .weeklyRegular: return RunLanguage.text("连续 4 周，每周完成至少一次正式训练。周一开始新的一周。")
        }
    }
}

public struct TrainingAchievements {
    public enum Award {
        case milestone(TrainingMilestone, Double), badge(HiddenRunBadge)
        case distanceBest(Double), splitBest(Double), intervalBest(Double)
        case challenge(PublicRunChallenge)
        case monthly(TrainingMonth, MonthlyBadge)

        public var title: String {
            switch self {
            case let .monthly(month, badge): return "\(month.label) · \(badge.title)"
            case let .challenge(challenge): return RunLanguage.text(challenge.rawValue)
            case let .milestone(metric, target):
                let name = metric.thresholds.contains(target) ? metric.rank(at: target) : RunLanguage.text("里程碑")
                return "\(name) · \(metric.title) \(metric.amount(target))"
            case let .badge(badge): return RunLanguage.text(badge.rawValue)
            case let .distanceBest(meters): return RunLanguage.text("最远一次") + " · " + TrainingMilestone.distance.amount(meters / 1000)
            case let .splitBest(seconds): return RunLanguage.text("最快一公里") + " · " + RunFormat.time(seconds)
            case let .intervalBest(seconds): return RunLanguage.text("最长连续跑") + " · " + RunFormat.time(seconds)
            }
        }
    }

    public private(set) var totals: [TrainingMilestone: Double] = [:]
    public private(set) var unlocked: Set<HiddenRunBadge> = []
    public private(set) var challengeProgress: [PublicRunChallenge: Int] = [:]
    public private(set) var monthlyDays: [TrainingMonth: Set<Int>] = [:]
    public private(set) var awards: [UUID: [Award]] = [:]
    public private(set) var longestMeters: Double = 0
    public private(set) var fastestSplit: Double?
    public private(set) var longestRunSeconds: Double = 0

    public static func matchingSplit(in record: WorkoutRecord) -> KilometerSplit? {
        for (a, b) in zip(record.splits, record.splits.dropFirst())
        where a.kilometer > 0 && b.kilometer - 1 == a.kilometer &&
            a.seconds.isFinite && b.seconds.isFinite && a.seconds > 0 && b.seconds > 0 &&
            a.seconds.rounded() == b.seconds.rounded() {
            return a
        }
        return nil
    }

    public init(_ history: [WorkoutRecord] = []) {
        var weekdays = Set<Int>(), seasons = Set<Int>(), daysWithKilometer = Set<String>()
        var destinations: [(place: SavedDestination, days: Set<String>)] = []
        var weeks = Set<Date>()
        var weekRun = 0
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = TimeZone(secondsFromGMT: 0)!
        let records = history.filter { $0.status == .finished }.sorted {
            $0.startedAt == $1.startedAt ? $0.id.uuidString < $1.id.uuidString : $0.startedAt < $1.startedAt
        }
        for record in records {
            let spans = record.activitySpans?.filter { $0.kind == .run } ?? []
            let runningTime = record.runSeconds ?? spans.reduce(0) { $0 + $1.seconds }
            let additions: [TrainingMilestone: Double] = [.distance: record.mainMeters / 1000,
                .steps: Double(record.totalSteps ?? 0), .hours: runningTime / 3600]
            var earned: [Award] = []
            for metric in TrainingMilestone.allCases {
                let before = totals[metric, default: 0]
                let after = before + max(0, additions[metric, default: 0])
                totals[metric] = after
                for threshold in metric.checkpoints.reversed() where before < threshold && after >= threshold {
                    earned.append(.milestone(metric, threshold))
                }
            }

            var found = Set<HiddenRunBadge>()
            let distanceImproved = longestMeters > 0 && record.mainMeters > longestMeters
            let split = record.splits.map(\.seconds).filter { $0.isFinite && $0 > 0 }.min()
            let splitImproved = split.map { time in fastestSplit.map { time.rounded() < $0.rounded() } ?? false } ?? false
            if distanceImproved { earned.append(.distanceBest(record.mainMeters)) }
            if splitImproved, let split { earned.append(.splitBest(split.rounded())) }
            if distanceImproved && splitImproved { found.insert(.doubleBest) }
            longestMeters = max(longestMeters, record.mainMeters)
            if let split { fastestSplit = min(fastestSplit ?? split, split) }
            if let longest = spans.map(\.seconds).max(), longest > longestRunSeconds {
                if longestRunSeconds > 0 && Int(longest) > Int(longestRunSeconds) { earned.append(.intervalBest(longest)) }
                longestRunSeconds = longest
            }

            if record.mainSeconds > 0 || record.mainMeters > 0 {
                if Self.matchingSplit(in: record) != nil { found.insert(.splitMatch) }
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = record.startTimeZone.flatMap(TimeZone.init(identifier:)) ?? .current
                let day = WorkoutDay.key(for: record)
                // Use the same saved local start day as the workout history, including for overnight runs.
                let parts = day.split(separator: "-").compactMap { Int($0) }
                if parts.count == 3, let date = iso.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) {
                    let month = TrainingMonth(date: date, timeZone: iso.timeZone)
                    let ordinal = parts[2]
                    if monthlyDays[month, default: []].insert(ordinal).inserted {
                        let count = monthlyDays[month]?.count ?? 0
                        for badge in MonthlyBadge.allCases where badge.target(in: month) == count {
                            earned.append(.monthly(month, badge))
                        }
                        if ordinal == 1 || ordinal == month.length {
                            let offset = ordinal == 1 ? -1 : 1
                            if let neighbor = iso.date(byAdding: .day, value: offset, to: date) {
                                let adjacent = TrainingMonth(date: neighbor, timeZone: iso.timeZone)
                                if monthlyDays[adjacent]?.contains(iso.component(.day, from: neighbor)) == true {
                                    found.insert(.pageTurn)
                                }
                            }
                        }
                    }
                }
                let hour = calendar.component(.hour, from: record.startedAt)
                let weekday = calendar.component(.weekday, from: record.startedAt)
                // Normalize local civil dates before comparing weeks across DST or time zones.
                let civilDate = calendar.dateComponents([.year, .month, .day], from: record.startedAt)
                if let date = iso.date(from: civilDate),
                   let monday = iso.dateInterval(of: .weekOfYear, for: date)?.start,
                   weekRun < PublicRunChallenge.weeklyRegular.target, weeks.insert(monday).inserted {
                    var length = 1
                    for direction in [-1, 1] {
                        var cursor = monday
                        while length < PublicRunChallenge.weeklyRegular.target,
                              let adjacent = iso.date(byAdding: .weekOfYear, value: direction, to: cursor),
                              weeks.contains(adjacent) {
                            length += 1
                            cursor = adjacent
                        }
                    }
                    weekRun = max(weekRun, length)
                }
                weekdays.insert(weekday)
                seasons.insert((calendar.component(.month, from: record.startedAt) % 12) / 3)
                if weekdays.count == 7 { found.insert(.weekdays) }
                if seasons.count == 4 { found.insert(.seasons) }
                if hour < 6 && record.mainSeconds >= 600 { found.insert(.early) }
                if (12..<14).contains(hour), let end = record.endedAt,
                   calendar.isDate(record.startedAt, inSameDayAs: end), calendar.component(.hour, from: end) < 14 {
                    found.insert(.lunch)
                }
                if (17..<19).contains(hour) && record.mainSeconds >= 900 { found.insert(.evening) }
                if [1, 7].contains(weekday) && (10..<12).contains(hour) { found.insert(.weekend) }
                if record.mainMeters >= 1000 && !daysWithKilometer.insert(day).inserted { found.insert(.twice) }
                if record.plan == .freeRun, record.destinationWorkout != true,
                   record.distanceGoalMeters == nil, record.mainMeters >= 3000 { found.insert(.untethered) }
            }
            for place in record.reachedDestinations ?? [] {
                let day = WorkoutDay.key(for: record)
                if let index = destinations.firstIndex(where: { DestinationLibrary.same($0.place, place) }) {
                    destinations[index].days.insert(day)
                    if destinations[index].days.count >= 5 { found.insert(.familiar) }
                } else { destinations.append((place, [day])) }
            }
            if let start = record.track.first, let end = record.track.last, let finish = record.endedAt,
               abs(start.timestamp.timeIntervalSince(record.startedAt)) <= 60,
               abs(end.timestamp.timeIntervalSince(finish)) <= 60 {
                let displacement = start.distance(to: end)
                if record.totalMeters >= 2000 && displacement <= 100 { found.insert(.loop) }
                if displacement >= 1000 && record.totalMeters > 0 && displacement <= record.totalMeters + 5
                    && displacement >= 0.9 * record.totalMeters { found.insert(.direct) }
            }
            for (challenge, count) in [(PublicRunChallenge.mapCollector, destinations.count), (.weeklyRegular, weekRun)] {
                let progress = min(count, challenge.target)
                if progress == challenge.target && challengeProgress[challenge] != challenge.target {
                    earned.append(.challenge(challenge))
                }
                challengeProgress[challenge] = progress
            }
            for badge in HiddenRunBadge.allCases where found.contains(badge) && unlocked.insert(badge).inserted {
                earned.append(.badge(badge))
            }
            if !earned.isEmpty { awards[record.id] = earned }
        }
    }
}
