import SwiftUI
import RunCore

struct SettingsView: View {
    var body: some View {
        List {
            Section("常用设置") {
                NavigationLink { BodySettingsView() } label: { setting("身体资料", subtitle: "体重、身高", icon: "person.crop.circle") }
                NavigationLink { TrainingPreferencesView() } label: { setting("训练偏好", subtitle: "跑走时长、目标配速", icon: "figure.run") }
                NavigationLink { VoiceSettingsView() } label: { setting("语音播报", subtitle: "微软离线语音、播报间隔", icon: "speaker.wave.2") }
                NavigationLink { DataSettingsView() } label: { setting("数据管理", subtitle: "记录与运动权限", icon: "tray") }
            }.listRowBackground(RunPalette.surface)
            Section("高级设置") {
                NavigationLink { AISettingsView() } label: { setting("AI 服务连接", subtitle: "地址、令牌、连接检查", icon: "network") }
            }.listRowBackground(RunPalette.surface)
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("设置")
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
            Section("身体资料") {
                HStack { Text("体重 · kg"); TextField("可选", text: $settings.weightText).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                HStack { Text("身高 · cm"); TextField("可选", text: $settings.heightText).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                if !settings.weightText.isEmpty && settings.weightKg == nil { Text("体重需在 25–300 kg 之间，当前不估算热量。").font(.caption).foregroundStyle(.orange) }
            }.listRowBackground(RunPalette.surface)
            Section { Text("活动热量使用体重、运动时间和粗略强度估算，属于成人平地活动参考；坡度、负重和个体差异未测量。身高仅作个人资料，不据此声称测得精确热量。修改资料用于下一次训练，旧记录保留原值。").font(.caption).foregroundStyle(Theme.secondary) }.listRowBackground(RunPalette.surface)
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("身体资料")
    }
}
struct TrainingPreferencesView: View {
    @EnvironmentObject private var settings: AppSettings
    var body: some View {
        Form {
            Section("自由跑 · 跑走循环") {
                durationPicker("跑步段", selection: $settings.freeRunSeconds, allowZero: false)
                durationPicker("步行段", selection: $settings.freeWalkSeconds, allowZero: true)
                Text("上下滑动设置。步行选为 0 就连续跑；设置保存在下一次训练中，进行中的训练不改变。").font(.caption).foregroundStyle(Theme.secondary)
            }.listRowBackground(RunPalette.surface)
            Section("目标配速") {
                TargetPacePicker()
                Text("跑步时与目标相差不超过 1 分钟，评价为刚刚好。只影响播报，不强制改变你的跑走安排。").font(.caption).foregroundStyle(Theme.secondary)
            }.listRowBackground(RunPalette.surface)
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("训练偏好")
    }
    private func durationPicker(_ title: String, selection: Binding<Int>, allowZero: Bool) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.subheadline.weight(.medium))
            Picker(title, selection: selection) {
                ForEach(Array(stride(from: allowZero ? 0 : 15, through: 3600, by: 15)), id: \.self) { seconds in
                    Text(seconds == 0 ? "0 · 连续跑，不安排步行" : RunFormat.spokenTime(Double(seconds))).tag(seconds)
                }
            }.pickerStyle(.wheel).frame(height: 130).clipped()
        }
    }
}
struct DataSettingsView: View {
    var body: some View {
        Form {
            Section {
                NavigationLink("管理训练记录") { HistoryView() }
                Button("查看系统权限") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                Text("训练保存在本机。删除入口在每条记录详情底部，删除记录不会让课程进度倒退。").font(.caption).foregroundStyle(Theme.secondary)
            }.listRowBackground(RunPalette.surface)
            Section("锁屏") { Text("开始训练后自动显示实时活动。锁屏仅显示所在阶段的距离、配速、用时与剩余倒计时。").font(.subheadline) }.listRowBackground(RunPalette.surface)
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("数据管理")
    }
}
struct VoiceSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: RunStore
    var body: some View { Form {
            Section("语音") {
                Picker("播报方式", selection: $settings.voiceMode) { ForEach(VoiceMode.allCases) { mode in Text(mode.title).tag(mode) } }
                if settings.voiceMode == .microsoft { Toggle("语音文件不可用时使用系统语音", isOn: $settings.fallbackToSystem) }
                Text(settings.voiceDescription).font(.caption).foregroundStyle(.secondary)
                Button("试听离线播报") {
                    if store.speech.isIdle { store.speech.enqueue([.stage(.warmup), .kilometer(1, 390, 390)]) }
                }.disabled(settings.voiceMode == .silent || store.hasWorkout)
                Text("试听包含一条固定提醒和一条公里用时。可断开 Wi-Fi 与移动网络后检查；训练中不进行试听。").font(.caption).foregroundStyle(.secondary)
            }
            Section("当前配速播报") {
                Toggle("播报当前配速", isOn: $settings.paceReportEnabled)
                if settings.paceReportEnabled {
                    Picker("播报间隔", selection: $settings.paceReportInterval) {
                        ForEach(AppSettings.paceReportIntervals, id: \.self) { seconds in
                            Text(seconds < 60 ? "每 \(seconds) 秒" : (seconds % 60 == 0 ? "每 \(seconds / 60) 分钟" : "每 \(seconds / 60) 分 \(seconds % 60) 秒")).tag(seconds)
                        }
                    }.pickerStyle(.wheel).frame(height: 150).clipped()
                }
                Button("试听配速示例") {
                    if store.speech.isIdle { store.speech.enqueue([.paceReport(pace: settings.targetPace ?? 450, target: settings.targetPace)]) }
                }.disabled(settings.voiceMode == .silent || store.hasWorkout)
                Text("示例按目标配速朗读，未设目标时示例为 7 分 30 秒；不代表当前实际速度。选择微软语音后，配速也使用预录音频，离线组合播放。").font(.caption).foregroundStyle(.secondary)
                Text("上下滑动选择 30 秒至 5 分钟，自动保存，训练中调整也会生效。只影响定时配速，不关闭每公里和阶段提示；无可靠定位时不编造配速。").font(.caption).foregroundStyle(.secondary)
            }
            Section("跑步小提示") {
                Toggle("动作与呼吸提醒", isOn: $settings.coachingTips)
                Text("累计跑步每隔至少 3 分钟，择机一次说完手臂、呼吸和说话检查三条；只在跑步阶段播，公里和阶段播报优先。").font(.caption).foregroundStyle(.secondary)
                NavigationLink("提醒内容与资料来源") {
                    List {
                        Section {
                            Text("每累计跑步至少 3 分钟，择机播报下面三条动作。提示供你自己检查，不代表手机检测到了姿势或呼吸问题。").font(.subheadline)
                        }
                        ForEach(CoachingTip.allCases) { tip in
                            Section(tip.title) {
                                Text(tip.speech)
                                if tip == .breathing {
                                    Text("这句计数是你的自选口令；呼吸不顺时不用硬跟次数。下方资料介绍一般呼吸方式，没有规定两吸一呼。").font(.caption).foregroundStyle(.secondary)
                                }
                                Link(tip.sourceTitle, destination: tip.sourceURL).font(.caption)
                                if let video = tip.demonstrationURL { Link("NHS 视频：放松双手与手臂", destination: video).font(.caption) }
                            }
                        }
                    }.navigationTitle("跑步小提示").navigationBarTitleDisplayMode(.inline)
                }
            }

    }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("语音播报") }
}
struct AISettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var checkingService = false
    @State private var serviceStatus: String?
    var body: some View { Form {
            Section("可选的 AI 复盘服务") {
                TextField("服务地址 https://…", text: $settings.serviceURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                SecureField("个人访问令牌", text: $settings.serviceToken).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button(checkingService ? "正在检查…" : "检查 AI 连接") {
                    guard let url = settings.endpoint else { serviceStatus = "请先填写有效的服务地址。"; return }
                    checkingService = true; serviceStatus = nil
                    Task {
                        defer { checkingService = false }
                        do { try await ServiceClient(baseURL: url, token: settings.serviceToken).checkConnection(); serviceStatus = "AI 服务可连接，模型已配置。生成复盘时才调用模型。" }
                        catch { serviceStatus = error.localizedDescription }
                    }
                }.disabled(checkingService)
                if let serviceStatus { Text(serviceStatus).font(.caption).foregroundStyle(.secondary) }
                Text("这里用于跑后的 AI 复盘。训练播报使用手机里的音频和系统语音，无需连接服务。模型密钥只放服务端；个人访问令牌保存在 iPhone 钥匙串。").font(.caption).foregroundStyle(.secondary)
                if !settings.serviceURL.isEmpty && settings.endpoint == nil { Text("请输入不含用户名、密码或查询参数的 HTTPS 地址。调试构建可使用明确的本地 HTTP 地址。").font(.caption).foregroundStyle(.orange) }
                if settings.serviceURL.contains("localhost") || settings.serviceURL.contains("127.0.0.1") { Text("注意：手机上的 localhost 是手机自身。连接 Windows 服务时，需要手机能访问的电脑地址。").font(.caption).foregroundStyle(.orange) }
            }

    }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("AI 服务连接") }
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
        Toggle("设置目标配速", isOn: enabled)
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
                Text("每公里用时")
                Spacer()
                Text("\(minutes) 分 \(seconds) 秒").monospacedDigit().fontWeight(.semibold)
            }
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    Picker("分钟", selection: $minutes) {
                        ForEach(2...20, id: \.self) { value in Text("\(value) 分").tag(value) }
                    }.pickerStyle(.wheel).labelsHidden().accessibilityLabel("目标配速分钟")
                        .frame(width: geometry.size.width / 2, height: 150).clipped()
                    Picker("秒", selection: $seconds) {
                        ForEach(0...59, id: \.self) { value in Text(String(format: "%02d 秒", value)).tag(value) }
                    }.pickerStyle(.wheel).labelsHidden().accessibilityLabel("目标配速秒")
                        .frame(width: geometry.size.width / 2, height: 150).clipped()
                }
            }.frame(height: 150)
            Text("上下滑动选择分钟和秒，自动保存，下一次训练生效。").font(.caption).foregroundStyle(.secondary)
        } else {
            Text("当前为自由跑。开启后滑动选择目标配速；关闭时不判断跑得太快。").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func save() {
        guard settings.targetPace != nil else { return }
        settings.targetPaceText = String(format: "%d:%02d", minutes, seconds)
    }
}
