import AVFoundation
import Combine
import RunCore

private enum PlaybackError: Error { case unavailable }

@MainActor final class SpeechCoordinator: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published var status = ""
    private let settings: AppSettings
    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var queue = WorkoutSpeechQueue()
    private var currentItem: WorkoutSpeechQueue.Item?
    private var sessionActive = false
    private var utteranceID: ObjectIdentifier?
    private var playerID: ObjectIdentifier?
    var navigationIsValid: ((NavigationCue) -> Bool)?
    var isIdle: Bool { currentItem == nil && queue.isEmpty }
    init(settings: AppSettings) {
        self.settings = settings; super.init(); synthesizer.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(routeChanged), name: AVAudioSession.routeChangeNotification, object: nil)
    }
    func enqueue(_ events: [WorkoutEvent], audiobookMode: Bool) {
        guard settings.voiceMode != .silent else { return }
        queue.enqueue(events, audiobookMode: audiobookMode)
        pump()
    }
    func enqueueNavigation(_ cue: NavigationCue, audiobookMode: Bool) {
        guard settings.voiceMode != .silent, navigationIsValid?(cue) == true else { return }
        queue.enqueueNavigation(cue, audiobookMode: audiobookMode)
        pump()
    }
    func cancelNavigation() { queue.cancelNavigation() }

    func stop() {
        queue.removeAll()
        utteranceID = nil; playerID = nil
        currentItem = nil
        player?.stop()
        player = nil
        synthesizer.stopSpeaking(at: .immediate)
        deactivate()
    }
    private func pump() {
        guard currentItem == nil else { return }
        if settings.voiceMode == .silent { queue.removeAll() }
        let validate = navigationIsValid
        guard let item = queue.next(navigationIsValid: { validate?($0) == true }) else {
            deactivate()
            return
        }
        currentItem = item
        // Workout speech never waits for a computer or a network response.
        if settings.voiceMode == .system {
            speakSystem(item.text, fallback: false)
            return
        }
        do {
            let data: Data?
            switch item { case .workout(let event): data = OfflineVoicePack.shared.audio(for: event); case .navigation(let cue): data = OfflineVoicePack.shared.audio(for: cue.voice) }
            guard let audio = data else { throw PlaybackError.unavailable }
            try activate()
            let audioPlayer = try AVAudioPlayer(data: audio); audioPlayer.delegate = self
            player = audioPlayer; playerID = ObjectIdentifier(audioPlayer)
            guard audioPlayer.play() else { throw PlaybackError.unavailable }
            status = RunLanguage.text("微软语音正在离线播报")
        } catch {
            player?.stop(); player = nil; playerID = nil
            if settings.fallbackToSystem { speakSystem(item.text, fallback: true) }
            else { status = RunLanguage.text("离线语音文件不可用，本次保持静音"); complete() }
        }
    }
    private func activate() throws {
        guard !sessionActive else { return }
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try AVAudioSession.sharedInstance().setActive(true)
        sessionActive = true
    }
    private func deactivate() {
        guard sessionActive else { return }
        sessionActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    private func speakSystem(_ text: String, fallback: Bool) {
        do { try activate() } catch { status = RunLanguage.text("音频暂不可用"); complete(); return }
        status = fallback ? RunLanguage.text("当前使用系统语音备用（非微软）") : RunLanguage.text("系统语音正在播报")
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: RunLanguage.isEnglish ? "en-CA" : "zh-CN"); utterance.rate = 0.48
        utteranceID = ObjectIdentifier(utterance)
        synthesizer.speak(utterance)
    }
    private func complete() {
        player = nil
        utteranceID = nil
        playerID = nil
        currentItem = nil
        pump()
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in if self?.utteranceID == id { self?.complete() } }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in if self?.utteranceID == id { self?.complete() } }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor [weak self] in if self?.playerID == id { self?.complete() } }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let id = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, self.playerID == id else { return }
            self.player?.stop()
            self.player = nil; self.playerID = nil
            if self.settings.fallbackToSystem, let item = self.currentItem { self.speakSystem(item.text, fallback: true) }
            else { self.status = RunLanguage.text("音频播放失败"); self.complete() }
        }
    }
    @objc nonisolated private func interrupted(_ notification: Notification) {
        guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: value) == .began else { return }
        Task { @MainActor [weak self] in self?.stop(); self?.status = RunLanguage.text("播报被系统打断，记录继续") }
    }
    @objc nonisolated private func routeChanged(_ notification: Notification) {
        guard let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: reason) == .oldDeviceUnavailable else { return }
        Task { @MainActor [weak self] in self?.stop(); self?.status = RunLanguage.text("耳机已断开，已停止当前播报") }
    }
}
