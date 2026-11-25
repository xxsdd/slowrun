import SwiftUI
import RunCore

private func medalColor(_ metric: TrainingMilestone, at value: Double) -> Color {
    let colors: [Color] = [Theme.secondary, Color(red: 0.90, green: 0.63, blue: 0.44),
                           Color(red: 0.80, green: 0.84, blue: 0.90), .yellow,
                           Color(red: 0.60, green: 0.93, blue: 0.86), .cyan,
                           Color(red: 0.82, green: 0.64, blue: 1.00)]
    return colors[metric.thresholds.filter { value >= $0 }.count]
}

private extension TrainingMilestone {
    func badgeAsset(at value: Double) -> String? {
        guard let index = thresholds.lastIndex(where: { value >= $0 }) else { return nil }
        let track: String
        switch self {
        case .distance: track = "distance"
        case .steps: track = "steps"
        case .hours: track = "hours"
        }
        let ranks = ["bronze", "silver", "gold", "platinum", "diamond", "champion"]
        return "rank-\(track)-\(ranks[index])"
    }
}

private extension HiddenRunBadge {
    var badgeAsset: String {
        switch self {
        case .familiar: return "hidden-familiar"
        case .loop: return "hidden-loop"
        case .direct: return "hidden-direct"
        case .untethered: return "hidden-untethered"
        case .early: return "hidden-early"
        case .lunch: return "hidden-lunch"
        case .evening: return "hidden-evening"
        case .weekend: return "hidden-weekend"
        case .twice: return "hidden-twice"
        case .weekdays: return "hidden-weekdays"
        case .seasons: return "hidden-seasons"
        case .doubleBest: return "hidden-doubleBest"
        case .splitMatch: return "hidden-splitMatch"
        case .pageTurn: return "hidden-pageTurn"
        }
    }
}

private extension PublicRunChallenge {
    var badgeAsset: String { self == .mapCollector ? "challenge-mapCollector" : "challenge-weeklyRegular" }
}

private extension MonthlyBadge {
    var badgeAsset: String { self == .full ? "month-full" : "month-\(rawValue)" }
}

private extension TrainingAchievements.Award {
    var badgeAsset: String? {
        switch self {
        case let .milestone(metric, value) where metric.thresholds.contains(value):
            return metric.badgeAsset(at: value)
        case let .badge(badge): return badge.badgeAsset
        case let .challenge(challenge): return challenge.badgeAsset
        case let .monthly(_, badge): return badge.badgeAsset
        default: return nil
        }
    }
}

private struct PandaAchievementArt: View {
    let asset: String
    let size: CGFloat
    var body: some View {
        Image(asset).resizable().scaledToFit().frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct WorkoutAwardsView: View {
    let awards: [TrainingAchievements.Award]
    let record: WorkoutRecord
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    private var accent: Color {
        if let first = awards.first, case let .milestone(metric, level) = first {
            return medalColor(metric, at: level)
        }
        return .yellow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(RunLanguage.text("本次获得"), systemImage: "medal.fill")
                .font(.caption.bold()).foregroundStyle(accent)
                .symbolEffect(.bounce, value: appeared)
            ForEach(Array(awards.enumerated()), id: \.offset) { index, award in
                HStack(spacing: 10) {
                    if let asset = award.badgeAsset {
                        PandaAchievementArt(asset: asset, size: index == 0 ? 72 : 46)
                    }
                    VStack(alignment: .leading) {
                        Text(award.title).font(index == 0 ? .title3.bold() : .subheadline)
                        if case .badge(.splitMatch) = award, let split = TrainingAchievements.matchingSplit(in: record) {
                            Text(RunLanguage.text("第 %1$@ 和第 %2$@ 公里都是 %3$@。",
                                 String(split.kilometer), String(split.kilometer + 1), RunFormat.time(split.seconds.rounded())))
                                .font(.caption).foregroundStyle(Theme.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(18)
        .background(LinearGradient(colors: [accent.opacity(0.20), RunPalette.raised],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18))
        .onAppear { appeared = !reduceMotion }
    }
}

struct AchievementsView: View {
    let achievements: TrainingAchievements
    @State private var expanded: TrainingMilestone?
    @State private var selectedMonth: TrainingMonth?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(RunLanguage.text("累计里程碑")).font(.headline)
                ForEach(TrainingMilestone.allCases, id: \.self) { metric in
                    milestone(metric)
                }
                Text(RunLanguage.text("公开挑战")).font(.headline)
                monthlyCollection
                ForEach(PublicRunChallenge.allCases, id: \.self) { challenge in
                    let count = achievements.challengeProgress[challenge, default: 0]
                    SurfaceCard {
                        HStack(spacing: 12) {
                            PandaAchievementArt(asset: challenge.badgeAsset, size: 62)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(RunLanguage.text(challenge.rawValue)).font(.headline)
                                Text(challenge.rule).font(.caption).foregroundStyle(Theme.secondary)
                                HStack {
                                    ForEach(0..<challenge.target, id: \.self) { index in
                                        Image(systemName: challenge == .mapCollector ? "mappin.circle.fill" : "calendar")
                                            .foregroundStyle(index < count ? Theme.teal : Theme.secondary.opacity(0.4))
                                    }
                                    Text("\(count) / \(challenge.target)").font(.caption.monospacedDigit())
                                }.accessibilityHidden(true)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
                            .accessibilityValue("\(count) / \(challenge.target)")
                    }
                }
                Text(RunLanguage.text("个人纪录")).font(.headline)
                SurfaceCard {
                    VStack(spacing: 14) {
                        recordRow("最远一次", achievements.longestMeters > 0 ? TrainingMilestone.distance.amount(achievements.longestMeters / 1000) : "—")
                        recordRow("最快一公里", achievements.fastestSplit.map { RunFormat.time($0.rounded()) } ?? "—")
                        recordRow("最长连续跑", achievements.longestRunSeconds > 0 ? RunFormat.time(achievements.longestRunSeconds) : "—")
                    }
                }
                HStack {
                    Text(RunLanguage.text("隐藏成就")).font(.headline)
                    Spacer()
                    Text("\(achievements.unlocked.count) / \(HiddenRunBadge.allCases.count)").monospacedDigit()
                }
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(HiddenRunBadge.allCases.filter { achievements.unlocked.contains($0) }, id: \.self) { badge in
                            HStack(spacing: 12) {
                                PandaAchievementArt(asset: badge.badgeAsset, size: 58)
                                Text(RunLanguage.text(badge.rawValue))
                            }
                        }
                        if achievements.unlocked.count < HiddenRunBadge.allCases.count {
                            Label(RunLanguage.text("其余成就将在跑完后揭晓"), systemImage: "lock.fill")
                                .font(.subheadline).foregroundStyle(Theme.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(20)
        }.background(Theme.background).navigationTitle(RunLanguage.text("我的成就"))
    }

    private var monthlyCollection: some View {
        let current = TrainingMonth(date: Date())
        let months = Set(achievements.monthlyDays.keys).union([current]).sorted(by: >)
        let month = selectedMonth.flatMap { months.contains($0) ? $0 : nil } ?? current
        let count = achievements.monthlyDays[month]?.count ?? 0
        return SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(RunLanguage.text("月度成就")).font(.headline)
                    Spacer()
                    Menu {
                        ForEach(months, id: \.self) { item in
                            Button(item.label) { selectedMonth = item }
                        }
                    } label: {
                        Label(month.label, systemImage: "calendar").font(.subheadline)
                    }
                }
                Text(RunLanguage.text("当月已训练 %1$@ 天", String(count))).font(.subheadline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92))], spacing: 12) {
                    ForEach(MonthlyBadge.allCases, id: \.self) { badge in
                        let target = badge.target(in: month)
                        VStack(spacing: 3) {
                            PandaAchievementArt(asset: badge.badgeAsset, size: 58)
                                .saturation(count >= target ? 1 : 0.25)
                            Text(badge.title).font(.caption.bold())
                            Label(RunLanguage.text("%1$@ 天", String(target)),
                                  systemImage: count >= target ? "checkmark.circle.fill" : "lock")
                                .font(.caption2).foregroundStyle(count >= target ? Theme.teal : Theme.secondary)
                        }.accessibilityElement(children: .combine)
                            .accessibilityValue(RunLanguage.text(count >= target ? "已完成" : "未解锁"))
                    }
                }
            }
        }
    }

    private func recordRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(RunLanguage.text(key))
            Spacer()
            Text(value).monospacedDigit().bold()
        }
    }

    private func milestone(_ metric: TrainingMilestone) -> some View {
        let value = achievements.totals[metric, default: 0]
        let next = metric.checkpoints.first { $0 > value }
        let previous = metric.checkpoints.last { $0 <= value } ?? 0
        return SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    expanded = expanded == metric ? nil : metric
                } label: {
                    HStack {
                        if let asset = metric.badgeAsset(at: value) {
                            PandaAchievementArt(asset: asset, size: 54)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(metric.title).font(.headline)
                            Text(metric.amount(value)).monospacedDigit().font(.title2.bold())
                        }
                        Spacer()
                        Text(metric.rank(at: value))
                            .font(.subheadline.bold()).foregroundStyle(medalColor(metric, at: value))
                        Image(systemName: expanded == metric ? "chevron.up" : "chevron.down").font(.caption)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                if let next {
                    ProgressView(value: max(0, value - previous), total: next - previous).tint(Theme.teal)
                    Text(RunLanguage.text("下一站 %1$@", metric.amount(next))).font(.caption).foregroundStyle(Theme.secondary)
                }
                if expanded == metric {
                    ForEach(metric.checkpoints, id: \.self) { checkpoint in
                        let title = metric.thresholds.contains(checkpoint) ? metric.rank(at: checkpoint) : RunLanguage.text("里程碑")
                        HStack(spacing: 10) {
                            if metric.thresholds.contains(checkpoint), let asset = metric.badgeAsset(at: checkpoint) {
                                PandaAchievementArt(asset: asset, size: 52)
                            }
                            Text("\(title) · \(metric.amount(checkpoint))").font(.subheadline)
                            Spacer()
                            Image(systemName: value >= checkpoint ? "checkmark.circle.fill" : "lock")
                                .foregroundStyle(value >= checkpoint ? Theme.teal : Theme.secondary)
                                .accessibilityHidden(true)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(value >= checkpoint ? RunLanguage.text("已完成") : RunLanguage.text("未解锁"))
                    }
                }
            }
        }
    }
}
