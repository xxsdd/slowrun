import SwiftUI
import RunCore

struct RootView: View {
    @EnvironmentObject private var store: RunStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                if store.hasWorkout { RunningView() } else { HomeView() }
            }.tabItem { Label("开始跑", systemImage: "figure.run") }.tag(0)
            NavigationStack { HistoryView() }.tabItem { Label("训练记录", systemImage: "chart.xyaxis.line") }.tag(1)
            NavigationStack { SettingsView() }.tabItem { Label("设置", systemImage: "slider.horizontal.3") }.tag(2)
        }
        .tint(Theme.teal)
        .onChange(of: scenePhase) { _, _ in store.sceneChanged() }
        .onOpenURL { url in if url.scheme == "slowrun" { tab = 0 } }
        .sheet(item: $store.lastFinished) { record in
            NavigationStack {
                WorkoutDetailView(initialRecord: record)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { store.lastFinished = nil } } }
            }
        }
        .alert("需要留意", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            if store.record?.status == .finished { Button("重试保存") { store.retrySave() } }
            Button("知道了", role: .cancel) { store.errorMessage = nil }
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
                    Text("准备出发").font(.subheadline).foregroundStyle(Theme.secondary)
                    Text("今天怎么跑").font(.system(size: 32, weight: .bold))
                }.padding(.top, 10)
                HStack(spacing: 8) {
                    modeButton("新手计划", selected: plan.isBeginner) { chooseNextCourse() }
                    modeButton("自由跑", selected: plan == .freeRun) { plan = .freeRun }
                    Menu {
                        Button("3 公里轻松跑") { plan = .threeK }
                        Button("5 公里轻松跑") { plan = .fiveK }
                    } label: { Text(plan.targetMeters == nil ? "距离跑" : plan.shortTitle).frame(maxWidth: .infinity, minHeight: 46).background(RunPalette.raised, in: RoundedRectangle(cornerRadius: 13)) }.tint(plan.targetMeters == nil ? Theme.secondary : Theme.teal)
                }
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Text(plan.shortTitle).font(.subheadline).foregroundStyle(Theme.secondary)
                            Spacer()
                            Text(plan.isBeginner ? (settings.courseProgress.finished ? "计划已完成" : "本次课程") : plan == .freeRun ? "无限循环" : "距离目标")
                                .font(.caption.weight(.medium)).foregroundStyle(Theme.teal)
                        }
                        Text(plan.isBeginner ? "第 \(plan.week ?? 1) 周 · 第 \(session) 次" : plan == .freeRun ? (settings.freeWalkSeconds == 0 ? "连续自由跑" : "跑走交替") : plan.title)
                            .font(.system(size: 26, weight: .semibold))
                        if plan.isBeginner {
                            HStack(spacing: 6) {
                                ForEach(1...3, id: \.self) { day in
                                    Capsule().fill(settings.courseProgress.completed.contains(((plan.week ?? 1) - 1) * 3 + day - 1) ? Theme.teal : RunPalette.line).frame(height: 4)
                                }
                            }
                            DataRow(title: "正式训练", value: RunFormat.time(formalTime))
                        } else if plan == .freeRun {
                            DataRow(title: "跑步段", value: settings.freeWalkSeconds == 0 ? "不限时" : RunFormat.time(Double(settings.freeRunSeconds)))
                            DataRow(title: "步行段", value: settings.freeWalkSeconds == 0 ? "不安排步行" : RunFormat.time(Double(settings.freeWalkSeconds)))
                            NavigationLink("调整跑走时长") { TrainingPreferencesView() }.font(.subheadline)
                        } else { DataRow(title: "正式训练目标", value: plan.shortTitle) }
                        Divider().overlay(RunPalette.line)
                        DataRow(title: "步行热身", value: "5 分钟 · 可跳过")
                        DataRow(title: "结束后放松", value: "可选 5 分钟")
                        if plan.isBeginner {
                            DisclosureGroup("查看每一段") {
                                VStack(spacing: 12) {
                                    ForEach(Array(plan.stages(session: session).enumerated()), id: \.offset) { _, part in
                                        DataRow(title: part.kind.title, value: RunFormat.time(part.seconds ?? 0))
                                    }
                                }.padding(.top, 12)
                            }.font(.subheadline).tint(Theme.secondary)
                        }
                    }
                }
                if store.record?.status == .finished {
                    PrimaryButton(title: store.savingWorkout ? "正在整理并保存…" : "重试保存训练", symbol: "square.and.arrow.down") { store.retrySave() }.disabled(store.savingWorkout)
                } else {
                    PrimaryButton(title: "开始训练", symbol: "play.fill") { store.start(plan, session: session) }
                }
                if plan.isBeginner {
                    Button("选择其他课程 / 重跑") { choosingCourse = true }.font(.subheadline).foregroundStyle(Theme.secondary)
                    Text("完成本节后自动接上下一节；两次训练之间留出休息日。").font(.caption).foregroundStyle(Theme.secondary)
                }
                HStack(spacing: 7) {
                    Image(systemName: "speaker.wave.2")
                    Text(settings.voiceMode == .silent ? "语音已关闭" : "播报每 " + RunFormat.spokenTime(Double(settings.paceReportInterval)))
                    Spacer()
                    Text(settings.targetPace.map { "目标 " + RunFormat.pace($0) } ?? "未设目标配速")
                }.font(.caption).foregroundStyle(Theme.secondary)
            }.padding(22)
        }.background(Theme.background).navigationTitle("慢慢跑").navigationBarTitleDisplayMode(.inline)
        .onAppear { plan = settings.lastPlan; if plan.isBeginner { chooseNextCourse() } }
        .onChange(of: settings.courseProgress.nextIndex) { _, _ in if plan.isBeginner { chooseNextCourse() } }
        .onChange(of: plan) { _, value in settings.lastPlan = value }
        .sheet(isPresented: $choosingCourse) {
            NavigationStack {
                Form {
                    Picker("训练周", selection: $plan) { ForEach(WorkoutPlan.beginnerWeeks) { Text($0.title).tag($0) } }
                    Picker("本周第几次", selection: $session) { ForEach(1...3, id: \.self) { Text("第 \($0) 次").tag($0) } }.pickerStyle(.segmented)
                    Text("可以重跑任何课程，已完成进度会保留。").font(.caption).foregroundStyle(.secondary)
                }.navigationTitle("选择课程").toolbar { Button("完成") { choosingCourse = false } }
            }.presentationDetents([.medium])
        }
    }
    private func chooseNextCourse() { plan = settings.courseProgress.plan; session = settings.courseProgress.session }
    private func modeButton(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(text).font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 46).foregroundStyle(selected ? Theme.teal : Theme.secondary).background(RunPalette.raised, in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(selected ? Theme.teal.opacity(0.6) : .clear)).contentShape(Rectangle()) }.buttonStyle(.plain)
    }
}
