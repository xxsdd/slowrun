import SwiftUI
import RunCore

struct SettingsView: View {
    @AppStorage(RunLanguage.key) private var language = ""
    var body: some View {
        List {
            Section(RunLanguage.text("常用设置")) {
                NavigationLink { BodySettingsView() } label: { setting(RunLanguage.text("身体资料"), subtitle: RunLanguage.text("体重、身高"), icon: "person.crop.circle") }
                NavigationLink { TrainingPreferencesView() } label: { setting(RunLanguage.text("训练偏好"), subtitle: RunLanguage.text("跑走时长、目标配速"), icon: "figure.run") }
                NavigationLink { VoiceSettingsView() } label: { setting(RunLanguage.text("语音播报"), subtitle: RunLanguage.text("微软离线语音、播报间隔"), icon: "speaker.wave.2") }
                NavigationLink { DataSettingsView() } label: { setting(RunLanguage.text("数据管理"), subtitle: RunLanguage.text("记录与运动权限"), icon: "tray") }
            }.listRowBackground(RunPalette.surface)
            Section {
                Picker("Language / 语言", selection: $language) {
                    Text(verbatim: "English").tag("en")
                    Text(verbatim: "简体中文").tag("zh-Hans")
                }
            }.listRowBackground(RunPalette.surface)
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle(RunLanguage.text("设置"))
    }
    private func setting(_ title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(Theme.secondary).frame(width: 26)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.body.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(Theme.secondary)
            }
        }.padding(.vertical, 8)
    }
}
struct BodySettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    var body: some View {
        Form {
            Section(RunLanguage.text("身体资料")) {
                HStack { Text(RunLanguage.text("体重 · kg")); TextField(RunLanguage.text("可选"), text: $settings.weightText).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                HStack { Text(RunLanguage.text("身高 · cm")); TextField(RunLanguage.text("可选"), text: $settings.heightText).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                if !settings.weightText.isEmpty && settings.weightKg == nil { Text(RunLanguage.text("体重需在 25–300 kg 之间，当前不估算热量。")).font(.caption).foregroundStyle(.orange) }
            }.listRowBackground(RunPalette.surface)
            Section { Text(RunLanguage.text("活动热量使用体重、运动时间和粗略强度估算，属于成人平地活动参考；坡度、负重和个体差异未测量。身高仅作个人资料，不据此声称测得精确热量。修改资料用于下一次训练，旧记录保留原值。")).font(.caption).foregroundStyle(Theme.secondary) }.listRowBackground(RunPalette.surface)
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle(RunLanguage.text("身体资料"))
    }
}
struct TrainingPreferencesView: View {
    @EnvironmentObject private var settings: AppSettings
    var body: some View {
        Form {
            Section(RunLanguage.text("自由跑 · 跑走循环")) {
                durationPicker(RunLanguage.text("跑步段"), selection: $settings.freeRunSeconds, allowZero: false)
                durationPicker(RunLanguage.text("步行段"), selection: $settings.freeWalkSeconds, allowZero: true)
                Text(RunLanguage.text("上下滑动设置。步行选为 0 就连续跑；设置保存在下一次训练中，进行中的训练不改变。")).font(.caption).foregroundStyle(Theme.secondary)
            }.listRowBackground(RunPalette.surface)
            Section(RunLanguage.text("目标配速")) {
                TargetPacePicker()
                Text(RunLanguage.text("跑步时与目标相差不超过 1 分钟，评价为刚刚好。只影响播报，不强制改变你的跑走安排。")).font(.caption).foregroundStyle(Theme.secondary)
            }.listRowBackground(RunPalette.surface)
            Section(RunLanguage.text("自由跑与目的地跑")) { DistanceGoalPicker() }.listRowBackground(RunPalette.surface)
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle(RunLanguage.text("训练偏好"))
    }
    private func durationPicker(_ title: String, selection: Binding<Int>, allowZero: Bool) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.subheadline.weight(.medium))
            Picker(title, selection: selection) {
                ForEach(Array(stride(from: allowZero ? 0 : 15, through: 3600, by: 15)), id: \.self) { seconds in
                    Text(seconds == 0 ? RunLanguage.text("0 · 连续跑，不安排步行") : RunFormat.spokenTime(Double(seconds))).tag(seconds)
                }
            }.pickerStyle(.wheel).frame(height: 130).clipped()
        }
    }
}
struct DataSettingsView: View {
    var body: some View {
        Form {
            Section {
                NavigationLink(RunLanguage.text("管理训练记录")) { HistoryView() }
                Button(RunLanguage.text("查看系统权限")) { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                Text(RunLanguage.text("训练保存在本机。删除入口在每条记录详情底部，删除记录不会让课程进度倒退。")).font(.caption).foregroundStyle(Theme.secondary)
            }.listRowBackground(RunPalette.surface)
            Section(RunLanguage.text("锁屏")) { Text(RunLanguage.text("开始训练后自动显示实时活动。锁屏仅显示所在阶段的距离、配速、用时与剩余倒计时。")).font(.subheadline) }.listRowBackground(RunPalette.surface)
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle(RunLanguage.text("数据管理"))
    }
}
struct VoiceSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: RunStore
    var body: some View { Form {
            Section(RunLanguage.text("语音")) {
                Picker(RunLanguage.text("播报方式"), selection: $settings.voiceMode) { ForEach(VoiceMode.allCases) { mode in Text(mode.title).tag(mode) } }
                if settings.voiceMode == .microsoft { Toggle(RunLanguage.text("语音文件不可用时使用系统语音"), isOn: $settings.fallbackToSystem) }
                Text(settings.voiceDescription).font(.caption).foregroundStyle(.secondary)
                Button(RunLanguage.text("试听离线播报")) {
                    if store.speech.isIdle { store.speech.enqueue([.stage(.warmup), .kilometer(1, 390, 390)], audiobookMode: false) }
                }.disabled(settings.voiceMode == .silent || store.hasWorkout)
                Text(RunLanguage.text("试听包含一条固定提醒和一条公里用时。可断开 Wi-Fi 与移动网络后检查；训练中不进行试听。")).font(.caption).foregroundStyle(.secondary)
            }
            Section(RunLanguage.text("当前配速播报")) {
                Toggle(RunLanguage.text("播报当前配速"), isOn: $settings.paceReportEnabled)
                Toggle(RunLanguage.text("偏离目标时提醒"), isOn: $settings.deviationAlerts)
                if settings.deviationAlerts {
                    Text(RunLanguage.text("设置目标配速后，跑步时最近 30 秒内有 20 秒偏快或偏慢超过 10 秒/公里，就提醒一次。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if settings.paceReportEnabled {
                    Picker(RunLanguage.text("播报间隔"), selection: $settings.paceReportInterval) {
                        ForEach(AppSettings.paceReportIntervals, id: \.self) { seconds in
                            Text(seconds < 60 ? RunLanguage.text("每 %1$@ 秒", "\(seconds)") : (seconds % 60 == 0 ? RunLanguage.text("每 %1$@ 分钟", "\(seconds / 60)") : RunLanguage.text("每 %1$@ 分 %2$@ 秒", "\(seconds / 60)", "\(seconds % 60)"))).tag(seconds)
                        }
                    }.pickerStyle(.wheel).frame(height: 150).clipped()
                }
                Button(RunLanguage.text("试听配速示例")) {
                    if store.speech.isIdle { store.speech.enqueue([.paceReport(pace: settings.targetPace ?? 450, target: settings.targetPace)], audiobookMode: false) }
                }.disabled(settings.voiceMode == .silent || store.hasWorkout)
                Text(RunLanguage.text("示例按目标配速朗读，未设目标时示例为 7 分 30 秒；不代表当前实际速度。选择微软语音后，配速也使用预录音频，离线组合播放。")).font(.caption).foregroundStyle(.secondary)
                Text(RunLanguage.text("上下滑动选择 30 秒至 5 分钟，自动保存，训练中调整也会生效。只影响定时配速，不关闭每公里和阶段提示；无可靠定位时不编造配速。")).font(.caption).foregroundStyle(.secondary)
            }
            Section(RunLanguage.text("跑步小提示")) {
                Toggle(RunLanguage.text("动作与呼吸提醒"), isOn: $settings.coachingTips)
                Text(RunLanguage.text("累计跑步每隔至少 3 分钟，择机一次说完手臂、呼吸和说话检查三条；只在跑步阶段播，公里和阶段播报优先。")).font(.caption).foregroundStyle(.secondary)
                NavigationLink(RunLanguage.text("提醒内容与资料来源")) {
                    List {
                        Section {
                            Text(RunLanguage.text("每累计跑步至少 3 分钟，择机播报下面三条动作。提示供你自己检查，不代表手机检测到了姿势或呼吸问题。")).font(.subheadline)
                        }
                        ForEach(CoachingTip.allCases) { tip in
                            Section(tip.title) {
                                Text(RunLanguage.text(tip.speech))
                                if tip == .breathing {
                                    Text(RunLanguage.text("这句计数是你的自选口令；呼吸不顺时不用硬跟次数。下方资料介绍一般呼吸方式，没有规定两吸一呼。")).font(.caption).foregroundStyle(.secondary)
                                }
                                Link(tip.sourceTitle, destination: tip.sourceURL).font(.caption)
                                if let video = tip.demonstrationURL { Link(RunLanguage.text("NHS 视频：放松双手与手臂"), destination: video).font(.caption) }
                            }
                        }
                    }.navigationTitle(RunLanguage.text("跑步小提示")).navigationBarTitleDisplayMode(.inline)
                }
            }

    }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle(RunLanguage.text("语音播报")) }
}
struct TargetPacePicker: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var minutes = 7
    @State private var seconds = 30
    private var enabled: Binding<Bool> {
        Binding(get: { settings.targetPace != nil }, set: { value in
            settings.targetPaceText = value ? String(format: "%d:%02d", minutes, seconds) : ""
        })
    }
    var body: some View {
        Toggle(RunLanguage.text("设置目标配速"), isOn: enabled)
            .onAppear {
                // Preserve an existing target; a free run stays free until enabled.
                if let pace = settings.targetPace {
                    let total = Int(pace.rounded())
                    minutes = min(20, max(2, total / 60)); seconds = total % 60
                }
            }
            .onChange(of: minutes) { _, _ in save() }
            .onChange(of: seconds) { _, _ in save() }
        if settings.targetPace != nil {
            HStack {
                Text(RunLanguage.text("每公里用时"))
                Spacer()
                Text(RunLanguage.text("%1$@ 分 %2$@ 秒", "\(minutes)", "\(seconds)")).monospacedDigit().fontWeight(.semibold)
            }
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    Picker(RunLanguage.text("分钟"), selection: $minutes) {
                        ForEach(2...20, id: \.self) { value in Text(RunLanguage.text("%1$@ 分", "\(value)")).tag(value) }
                    }.pickerStyle(.wheel).labelsHidden().accessibilityLabel(RunLanguage.text("目标配速分钟"))
                        .frame(width: geometry.size.width / 2, height: 150).clipped()
                    Picker(RunLanguage.text("秒"), selection: $seconds) {
                        ForEach(0...59, id: \.self) { value in Text(String(format: RunLanguage.text("%02d 秒"), value)).tag(value) }
                    }.pickerStyle(.wheel).labelsHidden().accessibilityLabel(RunLanguage.text("目标配速秒"))
                        .frame(width: geometry.size.width / 2, height: 150).clipped()
                }
            }.frame(height: 150)
            Text(RunLanguage.text("上下滑动选择分钟和秒，自动保存，下一次训练生效。")).font(.caption).foregroundStyle(.secondary)
        } else {
            Text(RunLanguage.text("当前为自由跑。开启后滑动选择目标配速；关闭时不判断跑得太快。")).font(.caption).foregroundStyle(.secondary)
        }
    }
    private func save() {
        guard settings.targetPace != nil else { return }
        settings.targetPaceText = String(format: "%d:%02d", minutes, seconds)
    }
}
