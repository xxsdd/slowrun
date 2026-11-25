import SwiftUI
import RunCore

struct HistoryView: View {
    @EnvironmentObject private var store: RunStore
    @State private var month = Date()
    @State private var selectedDay = ""
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.firstWeekday = 2; return c }
    private var groups: [String: [WorkoutRecord]] { WorkoutDay.groups(store.history) }
    private var summary: DailyWorkoutSummary { DailyWorkoutSummary(groups[selectedDay] ?? []) }
    private var monthStart: Date { calendar.date(from: calendar.dateComponents([.year, .month], from: month))! }
    private var dayCount: Int { calendar.range(of: .day, in: .month, for: month)!.count }
    private var leadingDays: Int { (calendar.component(.weekday, from: monthStart) + 5) % 7 }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                NavigationLink { AchievementsView(achievements: store.achievements) } label: {
                    Label(RunLanguage.text("我的成就"), systemImage: "medal.fill")
                        .font(.headline).foregroundStyle(Theme.teal)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        .background(RunPalette.raised, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain)
                SurfaceCard {
                    VStack(spacing: 15) {
                        HStack {
                            monthButton("chevron.left", amount: -1)
                            Spacer()
                            Text(month, format: .dateTime.year().month(.wide)).font(.headline)
                            Spacer()
                            monthButton("chevron.right", amount: 1)
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                            ForEach([RunLanguage.text("一"), RunLanguage.text("二"), RunLanguage.text("三"), RunLanguage.text("四"), RunLanguage.text("五"), RunLanguage.text("六"), RunLanguage.text("日")], id: \.self) { Text($0).font(.caption2).foregroundStyle(Theme.secondary).frame(height: 20) }
                            ForEach(0..<(leadingDays + dayCount), id: \.self) { index in
                                if index < leadingDays { Color.clear.frame(height: 42) }
                                else { dayCell(index - leadingDays + 1) }
                            }
                        }
                        HStack(spacing: 6) {
                            Circle().fill(Theme.teal).frame(width: 4, height: 4)
                            Text(RunLanguage.text("有运动记录 · 跨午夜归入开始当天")).font(.caption2).foregroundStyle(Theme.secondary)
                            Spacer()
                            Button(RunLanguage.text("今天")) { month = Date(); selectedDay = WorkoutDay.key(for: Date(), calendar: calendar) }.font(.caption)
                        }
                    }
                }
                HStack {
                    Text(selectedDay.isEmpty ? RunLanguage.text("当天运动") : selectedDay).font(.headline)
                    Spacer()
                    Text(RunLanguage.text("%1$@ 次运动", "\(summary.records.count)")).font(.caption).foregroundStyle(Theme.secondary)
                }
                if summary.records.isEmpty {
                    ContentUnavailableView(RunLanguage.text("当天没有记录"), systemImage: "calendar", description: Text(RunLanguage.text("有运动的日期会标一个小圆点。")))
                } else {
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(RunLanguage.text("全程汇总 · 含热身与放松")).font(.caption).foregroundStyle(Theme.secondary)
                            HStack(alignment: .top, spacing: 8) {
                                item(String(format: "%.2f", summary.meters / 1000), label: RunLanguage.text("总距离 · 公里"))
                                item(RunFormat.time(summary.seconds), label: RunLanguage.text("运动用时"))
                                item(summary.calories.map { String(format: "%.0f", $0) } ?? "—", label: summary.hasPartialCalories ? RunLanguage.text("部分热量 · 千卡") : RunLanguage.text("估算热量 · 千卡"))
                            }
                            if summary.hasPartialCalories { Text(RunLanguage.text("部分旧记录没有热量数据，热量仅汇总已知部分。")).font(.caption2).foregroundStyle(Theme.secondary) }
                        }
                    }
                    NavigationLink { WorkoutDayView(day: selectedDay) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(RunLanguage.text("打开当天记录")).font(.headline)
                                Text(RunLanguage.text("训练明细与分段成绩")).font(.caption).foregroundStyle(Theme.secondary)
                            }
                            Spacer(); Image(systemName: "chevron.right")
                        }.foregroundStyle(Theme.teal).padding(18).background(RunPalette.raised, in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain)
                    ForEach(summary.records) { record in
                        NavigationLink { WorkoutDetailView(initialRecord: record) } label: {
                            SurfaceCard {
                                VStack(alignment: .leading, spacing: 15) {
                                    HStack {
                                        Text(record.startedAt, format: .dateTime.hour().minute()).foregroundStyle(Theme.secondary)
                                        Spacer()
                                        Text(record.completionTitle).foregroundStyle(record.isCompleted ? Theme.teal : Theme.secondary)
                                        Image(systemName: "chevron.right").foregroundStyle(Theme.secondary)
                                    }.font(.caption)
                                    Text(record.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                                    HStack(alignment: .firstTextBaseline, spacing: 24) {
                                        item(String(format: "%.2f", record.mainMeters / 1000), label: RunLanguage.text("训练公里"))
                                        item(RunFormat.time(record.mainSeconds), label: RunLanguage.text("训练用时"))
                                    }
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(20)
        }.background(Theme.background).navigationTitle(RunLanguage.text("训练记录"))
            .onAppear {
                if selectedDay.isEmpty {
                    selectedDay = store.history.first.map { WorkoutDay.key(for: $0) } ?? WorkoutDay.key(for: Date(), calendar: calendar)
                    if let date = dateFromKey(selectedDay) { month = date }
                }
            }
    }
    private func monthButton(_ symbol: String, amount: Int) -> some View {
        Button { month = calendar.date(byAdding: .month, value: amount, to: monthStart)! } label: {
            Image(systemName: symbol).frame(width: 38, height: 38).background(RunPalette.raised, in: Circle())
        }.buttonStyle(.plain).accessibilityLabel(amount < 0 ? RunLanguage.text("上个月") : RunLanguage.text("下个月"))
    }
    private func dayCell(_ day: Int) -> some View {
        let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart)!
        let key = WorkoutDay.key(for: date, calendar: calendar)
        let selected = selectedDay == key
        let count = groups[key]?.count ?? 0
        return Button { selectedDay = key } label: {
            VStack(spacing: 4) {
                Text("\(day)").font(.system(size: 14, weight: selected ? .bold : .regular)).monospacedDigit()
                Circle().fill(count > 0 ? (selected ? RunPalette.onMint : Theme.teal) : .clear).frame(width: 4, height: 4)
            }.frame(maxWidth: .infinity).frame(height: 42)
                .foregroundStyle(selected ? RunPalette.onMint : Theme.ink)
                .background(selected ? Theme.teal : .clear, in: RoundedRectangle(cornerRadius: 11))
        }.buttonStyle(.plain).accessibilityLabel(RunLanguage.text("%1$@，%2$@ 次运动", "\(key)", "\(count)"))
    }
    private func dateFromKey(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
    private func item(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
