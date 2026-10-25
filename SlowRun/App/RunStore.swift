import Foundation
import Combine
import CoreLocation
import CoreMotion
import RunCore

@MainActor final class RunStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var engine: WorkoutEngine?
    @Published private(set) var history: [WorkoutRecord] = []
    @Published var lastFinished: WorkoutRecord?
    @Published var errorMessage: String?
    @Published var locationMessage = "训练开始后使用定位记录路线"
    @Published var lastCue = ""
    @Published var recoveryNotice = false
    let settings: AppSettings
    let speech: SpeechCoordinator
    private let location = CLLocationManager()
    private let pedometer = CMPedometer()
    private let storage = WorkoutStorage()
    private let liveActivity = LiveActivityCoordinator()
    private var timer: Timer?
    private var savedAt = Date.distantPast
    private var lastMotionCount = 0
    private var lastMotionDate = Date()
    @Published private(set) var savingWorkout = false
    private var motionGeneration = UUID()
    var record: WorkoutRecord? { engine?.record }
    var hasWorkout: Bool { record != nil && record?.status != .finished }
    var liveMessage: String? { liveActivity.message }

    init(settings: AppSettings) {
        self.settings = settings; speech = SpeechCoordinator(settings: settings)
        super.init()
        location.delegate = self; location.activityType = .fitness
        location.desiredAccuracy = kCLLocationAccuracyBest; location.distanceFilter = kCLDistanceFilterNone
        location.pausesLocationUpdatesAutomatically = false
        do {
            history = try storage.records()
            if !settings.progressInitialized { settings.courseProgress = CourseProgress(records: history) }
            if var restored = try storage.loadActive(), restored.record.status != .finished {
                restored.recoverPaused(at: Date()); engine = restored; recoveryNotice = true
                try storage.saveActive(restored)
                liveActivity.sync(restored.record, force: true)
            } else {
                liveActivity.end()
                if let pending = try storage.loadActive(), pending.record.status == .finished {
                    engine = pending; saveCompletedWorkout()
                }
            }
        } catch { errorMessage = "本地记录读取失败，原始文件仍保留：\(error.localizedDescription)" }
    }
    func start(_ plan: WorkoutPlan, session: Int = 1) {
        guard engine == nil else {
            if record?.status == .finished { errorMessage = "上一趟训练尚未成功保存，请先点重试保存。" }
            return
        }
        lastFinished = nil; recoveryNotice = false; settings.lastPlan = plan
        engine = WorkoutEngine(plan: plan, weightKg: settings.weightKg, targetPace: settings.targetPace, session: session, freeRunSeconds: Double(settings.freeRunSeconds), freeWalkSeconds: Double(settings.freeWalkSeconds))
        process([.stage(.warmup)]); startSensors(); startTimer(); persist(force: true); updateLive(force: true)
    }
    func togglePause() {
        guard let record else { return }
        if record.status == .active {
            process(engine?.pause(at: Date()) ?? [])
            stopSensors(); speech.stop(); lastCue = "训练已暂停，距离和用时保持不变。"
        } else if record.status == .paused {
            engine?.resume(at: Date()); recoveryNotice = false; startSensors(); startTimer()
            engine?.notePriorityCue()
            lastCue = "训练已继续。按舒服的节奏来。"
        }
        persist(force: true); updateLive(force: true)
    }
    func skipPreparation() { process(engine?.skipPreparation(at: Date()) ?? []); persist(force: true); updateLive(force: true) }
    func finish() {
        process(engine?.finish(at: Date()) ?? [])
        if engine?.record.status == .finished { saveCompletedWorkout() }
    }
    func beginCooldown() {
        let wasPaused = record?.status == .paused
        process(engine?.beginCooldown(at: Date()) ?? [])
        if wasPaused && hasWorkout { startSensors(); startTimer() }
        persist(force: true); updateLive(force: true)
    }
    private func startTimer() {
        timer?.invalidate()
        let value = Timer(timeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        timer = value; RunLoop.main.add(value, forMode: .common)
    }
    private func tick() {
        guard hasWorkout else { return }
        process(engine?.advance(to: Date()) ?? [])
        scheduleOptionalSpeech()
        persist(); updateLive()
    }
    private func scheduleOptionalSpeech() {
        // A due three-minute routine gets the first quiet slot, otherwise a
        // frequent pace report can consume the entire short run-stage window.
        if let tip = engine?.takeCoachingTip(enabled: settings.coachingTips && settings.voiceMode != .silent, audioIdle: speech.isIdle) {
            process([tip]); persist(force: true)
        }
        if let report = engine?.takePaceReport(audioIdle: speech.isIdle, interval: Double(settings.paceReportInterval), enabled: settings.paceReportEnabled && settings.voiceMode != .silent) {
            lastCue = report.speech; speech.enqueue([report]); persist(force: true)
        }
    }
    func sceneChanged() { tick(); persist(force: true); updateLive(force: true) }
    private func process(_ events: [WorkoutEvent]) {
        guard !events.isEmpty else { return }
        if events.contains(where: { if case .coaching = $0 { return false }; return true }) { engine?.notePriorityCue() }
        lastCue = events.last?.speech ?? lastCue; speech.enqueue(events)
        if events.contains(.finished) { saveCompletedWorkout() }
        else if events.contains(where: { if case .stage = $0 { return true }; if case .freeRunStarted = $0 { return true }; return false }) { persist(force: true); updateLive(force: true) }
    }
    private func saveCompletedWorkout() {
        guard let snapshot = engine, snapshot.record.status == .finished, !savingWorkout else { return }
        timer?.invalidate(); timer = nil; stopSensors(); liveActivity.end()
        savingWorkout = true
        // Preserve the finished snapshot even if final pedometer lookup/save fails.
        do { try storage.saveActive(snapshot) }
        catch { savingWorkout = false; errorMessage = "结束记录暂存失败，请重试保存。"; return }
        Task {
            var finalized = snapshot
            if let spans = snapshot.record.activitySpans, snapshot.record.stepsFinalized != true {
                var counts: [WorkoutPhase: Int?] = [:]
                for phase in WorkoutPhase.allCases {
                    var total = 0
                    var available = CMPedometer.isStepCountingAvailable()
                    for span in spans where span.kind.phase == phase && span.seconds > 0 {
                        if let value = await querySteps(from: span.start, to: span.end) { total += value }
                        else { available = false }
                    }
                    counts[phase] = .some(available ? total : nil)
                }
                finalized.finalizeSteps(counts)
            }
            engine = finalized
            do {
                try storage.save(finalized.record)
                settings.courseProgress.register(finalized.record)
                try storage.clearActive()
                history = try storage.records(); lastFinished = finalized.record; engine = nil
            } catch { errorMessage = "训练已结束，但保存失败。请保留应用并重试：\(error.localizedDescription)" }
            savingWorkout = false
        }
    }
    private func querySteps(from start: Date, to end: Date) async -> Int? {
        guard CMPedometer.isStepCountingAvailable(), CMPedometer.authorizationStatus() != .denied,
              CMPedometer.authorizationStatus() != .restricted else { return nil }
        return await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: end) { data, error in
                continuation.resume(returning: error == nil ? data?.numberOfSteps.intValue : nil)
            }
        }
    }
    func retrySave() { saveCompletedWorkout() }
    private func persist(force: Bool = false) {
        guard let engine, engine.record.status != .finished, force || Date().timeIntervalSince(savedAt) >= 5 else { return }
        do { try storage.saveActive(engine); savedAt = Date() }
        catch { errorMessage = "进行中记录保存失败：\(error.localizedDescription)" }
    }
    private func updateLive(force: Bool = false) { if let record { liveActivity.sync(record, force: force) } }
    private func startSensors() {
        switch location.authorizationStatus {
        case .notDetermined: location.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: startLocation()
        default: locationMessage = "定位未开启：可继续按时间训练，距离与配速不可用。请在系统设置中允许定位。"
        }
        startMotion()
    }
    private func startLocation() {
        guard record?.status == .active else { return }
        location.allowsBackgroundLocationUpdates = true; location.showsBackgroundLocationIndicator = true
        location.startUpdatingLocation()
        locationMessage = location.accuracyAuthorization == .fullAccuracy ? "等待可信 GPS 信号…" : "请在系统设置中开启精确位置，才能可靠记录距离。"
    }
    private func startMotion() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        lastMotionCount = 0; lastMotionDate = Date(); motionGeneration = UUID(); let generation = motionGeneration
        pedometer.startUpdates(from: lastMotionDate) { [weak self] data, _ in
            guard let data else { return }
            Task { @MainActor in
                guard let self, self.motionGeneration == generation, self.record?.status == .active else { return }
                let count = data.numberOfSteps.intValue
                guard data.endDate > self.lastMotionDate else { return }
                self.process(self.engine?.advance(to: data.endDate) ?? [])
                self.engine?.recordMotion(steps: max(0, count - self.lastMotionCount), cadence: data.currentCadence.map { $0.doubleValue * 60 }, from: self.lastMotionDate, to: data.endDate)
                self.lastMotionDate = data.endDate
                self.lastMotionCount = count
            }
        }
    }
    private func stopSensors() { location.stopUpdatingLocation(); pedometer.stopUpdates(); motionGeneration = UUID() }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.authorizationChanged() }
    }
    private func authorizationChanged() {
        guard record?.status == .active else { return }
        if location.authorizationStatus == .authorizedAlways || location.authorizationStatus == .authorizedWhenInUse { startLocation() }
        else if location.authorizationStatus != .notDetermined { locationMessage = "定位未开启，距离和配速暂不可用。计时训练继续。" }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let points = locations.map { value in
            TrackPoint(latitude: value.coordinate.latitude, longitude: value.coordinate.longitude, timestamp: value.timestamp, accuracy: value.horizontalAccuracy, speed: value.speed >= 0 ? value.speed : nil)
        }
        Task { @MainActor [weak self] in self?.receiveLocations(points) }
    }
    private func receiveLocations(_ points: [TrackPoint]) {
        guard record?.status == .active else { return }
        let previousStage = record?.stageIndex
        for point in points {
            let events = engine?.ingest(point, receivedAt: Date()) ?? []
            process(events)
        }
        // Location callbacks also drive timed transitions while the app is in
        // the background. Don't rely exclusively on a foreground Timer.
        if record?.stageIndex == previousStage { scheduleOptionalSpeech() }
        if let last = record?.lastGPSAt, Date().timeIntervalSince(last) <= 15 { locationMessage = "GPS 记录中" }
        else { locationMessage = "定位信号较弱，等待可信位置；不会补造距离。" }
        persist(); updateLive()
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in self?.locationMessage = "定位暂不可用，计时继续，等待信号恢复。" }
    }
    func saveEffort(_ effort: Effort, for id: UUID) {
        guard var value = history.first(where: { $0.id == id }) else { return }
        value.effort = effort; saveUpdated(value)
    }
    func saveMemo(_ memo: String, for id: UUID) {
        guard var value = history.first(where: { $0.id == id }) else { return }
        value.memo = String(memo.prefix(2000)); saveUpdated(value)
    }
    func saveAI(_ text: String, for id: UUID) {
        guard var value = history.first(where: { $0.id == id }) else { return }
        value.aiReview = text; saveUpdated(value)
    }
    @discardableResult func deleteWorkout(_ id: UUID) -> Bool {
        guard history.contains(where: { $0.id == id }) else { return false }
        do {
            try storage.delete(id)
            history.removeAll { $0.id == id }
            if lastFinished?.id == id { lastFinished = nil }
            return true
        } catch {
            errorMessage = "删除失败，记录仍保留：\(error.localizedDescription)"
            return false
        }
    }
    private func saveUpdated(_ value: WorkoutRecord) {
        do { try storage.save(value); history = try storage.records(); if lastFinished?.id == value.id { lastFinished = value } }
        catch { errorMessage = "记录更新失败：\(error.localizedDescription)" }
    }
}
