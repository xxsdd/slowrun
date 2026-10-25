import AVFoundation
import Combine
import RunCore

@MainActor final class SpeechCoordinator: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published var status = ""
    private let settings: AppSettings
    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var queue: [WorkoutEvent] = []
    private var busy = false
    private var utteranceID: ObjectIdentifier?
    private var playerID: ObjectIdentifier?
    private var currentEvent: WorkoutEvent?
    var isIdle: Bool { !busy && queue.isEmpty }
    init(settings: AppSettings) {
        self.settings = settings; super.init(); synthesizer.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(routeChanged), name: AVAudioSession.routeChangeNotification, object: nil)
    }
    func enqueue(_ events: [WorkoutEvent]) {
        guard settings.voiceMode != .silent else { return }
        if events.contains(where: { if case .coaching = $0 { return false }; return true }) {
            if case .coaching? = currentEvent { stop() }
            queue.removeAll { if case .coaching = $0 { return true }; return false }
        }
        if events.contains(where: { if case .stage = $0 { return true }; if case .freeRunStarted = $0 { return true }; return false }) {
            queue.removeAll {
                switch $0 { case .adjustment, .pace: return true; default: return false }
            }
        }
        queue.append(contentsOf: events)
        if queue.count > 4 { queue = Array(queue.suffix(4)) }
        pump()
    }
    func stop() {
        queue.removeAll()
        utteranceID = nil; playerID = nil
        currentEvent = nil
        player?.stop(); player = nil; synthesizer.stopSpeaking(at: .immediate); busy = false
        deactivate()
    }
    private func pump() {
        guard !busy, !queue.isEmpty else { return }
        guard settings.voiceMode != .silent else { queue.removeAll(); return }
        let event = queue.removeFirst(); busy = true; currentEvent = event
        // Workout speech never waits for a computer or a network response.
        if settings.voiceMode == .system {
            speakSystem(event.speech, fallback: false)
            return
        }
        do {
            guard let audio = OfflineVoicePack.shared.audio(for: event) else { throw ServiceError.invalidResponse }
            try activate()
            let audioPlayer = try AVAudioPlayer(data: audio); audioPlayer.delegate = self
            player = audioPlayer; playerID = ObjectIdentifier(audioPlayer)
            guard audioPlayer.play() else { throw ServiceError.invalidResponse }
            status = "微软语音正在离线播报"
        } catch {
            player?.stop(); player = nil; playerID = nil
            if settings.fallbackToSystem { speakSystem(event.speech, fallback: true) }
            else { status = "离线语音文件不可用，本次保持静音"; complete() }
        }
    }
    private func activate() throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try AVAudioSession.sharedInstance().setActive(true)
    }
    private func deactivate() { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    private func speakSystem(_ text: String, fallback: Bool) {
        do { try activate() } catch { status = "音频暂不可用"; complete(); return }
        status = fallback ? "当前使用系统语音备用（非微软）" : "系统语音正在播报"
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN"); utterance.rate = 0.48
        utteranceID = ObjectIdentifier(utterance)
        synthesizer.speak(utterance)
    }
    private func complete() { busy = false; player = nil; utteranceID = nil; playerID = nil; currentEvent = nil; deactivate(); pump() }
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
            self.player = nil; self.playerID = nil
            if self.settings.fallbackToSystem, let event = self.currentEvent { self.speakSystem(event.speech, fallback: true) }
            else { self.status = "音频播放失败"; self.complete() }
        }
    }
    @objc nonisolated private func interrupted(_ notification: Notification) {
        guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: value) == .began else { return }
        Task { @MainActor [weak self] in self?.stop(); self?.status = "播报被系统打断，记录继续" }
    }
    @objc nonisolated private func routeChanged(_ notification: Notification) {
        guard let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: reason) == .oldDeviceUnavailable else { return }
        Task { @MainActor [weak self] in self?.stop(); self?.status = "耳机已断开，已停止当前播报" }
    }
}
