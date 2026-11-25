import SwiftUI
import RunCore

struct RootView: View {
    @EnvironmentObject private var store: RunStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                if store.hasWorkout {
                    if store.navigation.showsNavigation { DestinationRunningView(navigation: store.navigation) } else { RunningView() }
                } else { HomeView() }
            }.tabItem { Label(RunLanguage.text("开始跑"), systemImage: "figure.run") }.tag(0)
            NavigationStack { HistoryView() }.tabItem { Label(RunLanguage.text("训练记录"), systemImage: "chart.xyaxis.line") }.tag(1)
            NavigationStack { SettingsView() }.tabItem { Label(RunLanguage.text("设置"), systemImage: "slider.horizontal.3") }.tag(2)
        }
        .tint(Theme.teal)
        .onChange(of: scenePhase) { _, _ in store.sceneChanged() }
        .onOpenURL { url in if url.scheme == "slowrun" { tab = 0 } }
        .sheet(item: $store.lastFinished) { record in
            NavigationStack {
                WorkoutDetailView(initialRecord: record)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(RunLanguage.text("完成")) { store.lastFinished = nil } } }
            }
        }
        .alert(RunLanguage.text("需要留意"), isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            if store.record?.status == .finished { Button(RunLanguage.text("重试保存")) { store.retrySave() } }
            Button(RunLanguage.text("知道了"), role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
}
struct HomeView: View {
    @EnvironmentObject private var store: RunStore
    @EnvironmentObject private var settings: AppSettings
    @State private var plan: WorkoutPlan = .beginner
    @State private var session = 1
    @State private var choosingCourse = false
    private var formalTime: Double { plan.stages(session: session).filter { $0.kind.isMain }.reduce(0) { $0 + ($1.seconds ?? 0) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(RunLanguage.text("准备出发")).font(.subheadline).foregroundStyle(Theme.secondary)
                    Text(RunLanguage.text("今天怎么跑")).font(.system(size: 32, weight: .bold))
                }.padding(.top, 10)
                HStack(spacing: 8) {
                    modeButton(RunLanguage.text("新手计划"), selected: plan.isBeginner) { chooseNextCourse() }
                    modeButton(RunLanguage.text("自由跑"), selected: plan == .freeRun) { plan = .freeRun }
                    Menu {
                        Button(RunLanguage.text("3 公里轻松跑")) { plan = .threeK }
                        Button(RunLanguage.text("5 公里轻松跑")) { plan = .fiveK }
                    } label: { Text(plan.targetMeters == nil ? RunLanguage.text("距离跑") : plan.shortTitle).frame(maxWidth: .infinity, minHeight: 46).background(RunPalette.raised, in: RoundedRectangle(cornerRadius: 13)) }.tint(plan.targetMeters == nil ? Theme.secondary : Theme.teal)
                }
                NavigationLink {
                    DestinationSearchView(navigation: store.navigation)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "location.north.line.fill").font(.title2).foregroundStyle(Theme.teal)
                        VStack(alignment: .leading, spacing: 5) { Text(RunLanguage.text("跑去目的地")).font(.headline).foregroundStyle(Theme.ink); Text(RunLanguage.text("选一个地方，边跑边走，让语音带路")).font(.caption).foregroundStyle(Theme.secondary) }
                        Spacer(); Image(systemName: "chevron.right").foregroundStyle(Theme.secondary)
                    }.padding(17).frame(maxWidth: .infinity, minHeight: 75).background(RunPalette.raised, in: RoundedRectangle(cornerRadius: 17)).contentShape(Rectangle())
                }.buttonStyle(.plain)
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Text(plan.shortTitle).font(.subheadline).foregroundStyle(Theme.secondary)
                            Spacer()
                            Text(plan.isBeginner ? (settings.courseProgress.finished ? RunLanguage.text("计划已完成") : RunLanguage.text("本次课程")) : plan == .freeRun ? (settings.distanceGoalEnabled ? RunLanguage.text("含热身的距离目标") : RunLanguage.text("无限循环")) : RunLanguage.text("距离目标"))
                                .font(.caption.weight(.medium)).foregroundStyle(Theme.teal)
                        }
                        Text(plan.isBeginner ? RunLanguage.text("第 %1$@ 周 · 第 %2$@ 次", "\(plan.week ?? 1)", "\(session)") : plan == .freeRun ? (settings.freeWalkSeconds == 0 ? RunLanguage.text("连续自由跑") : RunLanguage.text("跑走交替")) : plan.title)
                            .font(.system(size: 26, weight: .semibold))
                        if plan.isBeginner {
                            HStack(spacing: 6) {
                                ForEach(1...3, id: \.self) { day in
                                    Capsule().fill(settings.courseProgress.completed.contains(((plan.week ?? 1) - 1) * 3 + day - 1) ? Theme.teal : RunPalette.line).frame(height: 4)
                                }
                            }
                            DataRow(title: RunLanguage.text("正式训练"), value: RunFormat.time(formalTime))
                        } else if plan == .freeRun {
                            DataRow(title: RunLanguage.text("跑步段"), value: settings.freeWalkSeconds == 0 ? RunLanguage.text("不限时") : RunFormat.time(Double(settings.freeRunSeconds)))
                            DataRow(title: RunLanguage.text("步行段"), value: settings.freeWalkSeconds == 0 ? RunLanguage.text("不安排步行") : RunFormat.time(Double(settings.freeWalkSeconds)))
                            NavigationLink(RunLanguage.text("调整跑走时长")) { TrainingPreferencesView() }.font(.subheadline)
                        } else { DataRow(title: RunLanguage.text("正式训练目标"), value: plan.shortTitle) }
                        Divider().overlay(RunPalette.line)
                        DataRow(title: RunLanguage.text("步行热身"), value: RunLanguage.text("5 分钟 · 可跳过"))
                        DataRow(title: RunLanguage.text("结束后放松"), value: RunLanguage.text("可选 5 分钟"))
                        if plan.isBeginner {
                            DisclosureGroup(RunLanguage.text("查看每一段")) {
                                VStack(spacing: 12) {
                                    ForEach(Array(plan.stages(session: session).enumerated()), id: \.offset) { _, part in
                                        DataRow(title: part.kind.title, value: RunFormat.time(part.seconds ?? 0))
                                    }
                                }.padding(.top, 12)
                            }.font(.subheadline).tint(Theme.secondary)
                        }
                    }
                }
                if plan == .freeRun { SurfaceCard { DistanceGoalPicker() } }
                if store.record?.status == .finished {
                    PrimaryButton(title: store.savingWorkout ? RunLanguage.text("正在整理并保存…") : RunLanguage.text("重试保存训练"), symbol: "square.and.arrow.down") { store.retrySave() }.disabled(store.savingWorkout)
                } else {
                    AudiobookWorkoutToggle()
                    PrimaryButton(title: RunLanguage.text("开始训练"), symbol: "play.fill") { store.start(plan, session: session) }
                }
                if plan.isBeginner {
                    Button(RunLanguage.text("选择其他课程 / 重跑")) { choosingCourse = true }.font(.subheadline).foregroundStyle(Theme.secondary)
                    Text(RunLanguage.text("完成本节后自动接上下一节；两次训练之间留出休息日。")).font(.caption).foregroundStyle(Theme.secondary)
                }
                HStack(spacing: 7) {
                    if !store.audiobookForNextWorkout && settings.voiceMode != .silent && settings.paceReportEnabled {
                        Image(systemName: "speaker.wave.2").accessibilityHidden(true)
                        Text(RunLanguage.text("每 ") + RunFormat.spokenTime(Double(settings.paceReportInterval)) + RunLanguage.text(" 报配速"))
                    }
                    Spacer()
                    Text(settings.targetPace.map { RunLanguage.text("目标 ") + RunFormat.pace($0) } ?? RunLanguage.text("未设目标配速"))
                }.font(.caption).foregroundStyle(Theme.secondary)
            }.padding(22)
        }.background(Theme.background).navigationTitle(RunLanguage.text("慢慢跑")).navigationBarTitleDisplayMode(.inline)
        .onAppear { plan = settings.lastPlan; if plan.isBeginner { chooseNextCourse() } }
        .onChange(of: settings.courseProgress.nextIndex) { _, _ in if plan.isBeginner { chooseNextCourse() } }
        .onChange(of: plan) { _, value in settings.lastPlan = value }
        .sheet(isPresented: $choosingCourse) {
            NavigationStack {
                Form {
                    Picker(RunLanguage.text("训练周"), selection: $plan) { ForEach(WorkoutPlan.beginnerWeeks) { Text($0.title).tag($0) } }
                    Picker(RunLanguage.text("本周第几次"), selection: $session) { ForEach(1...3, id: \.self) { Text(RunLanguage.text("第 %1$@ 次", "\($0)")).tag($0) } }.pickerStyle(.segmented)
                    Text(RunLanguage.text("可以重跑任何课程，已完成进度会保留。")).font(.caption).foregroundStyle(.secondary)
                }.navigationTitle(RunLanguage.text("选择课程")).toolbar { Button(RunLanguage.text("完成")) { choosingCourse = false } }
            }.presentationDetents([.medium])
        }
    }
    private func chooseNextCourse() { plan = settings.courseProgress.plan; session = settings.courseProgress.session }
    private func modeButton(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(text).font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 46).foregroundStyle(selected ? Theme.teal : Theme.secondary).background(RunPalette.raised, in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(selected ? Theme.teal.opacity(0.6) : .clear)).contentShape(Rectangle()) }.buttonStyle(.plain)
    }
}
