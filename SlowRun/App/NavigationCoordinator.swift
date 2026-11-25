import Foundation
import Combine
import CoreLocation
import MapKit
import RunCore

extension NavigationCoordinate {
    var clCoordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    init(_ coordinate: CLLocationCoordinate2D) { self.init(latitude: coordinate.latitude, longitude: coordinate.longitude) }
}

@MainActor final class NavigationCoordinator: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum State { case off, navigating, rerouting, failed, waiting, arrived }
    struct RouteOption {
        let route: MKRoute
        let geometry: NavigationRoute
        var summary: WalkingRouteSummary {
            WalkingRouteSummary(distance: route.distance, turns: geometry.maneuvers.count)
        }
    }
    @Published var query = "" { didSet { scheduleSearch() } }
    @Published private(set) var searchResults: [SavedDestination] = []
    @Published private(set) var searching = false
    @Published private(set) var searchError: String?
    @Published private(set) var library = DestinationLibrary()
    @Published private(set) var storageError: String?
    @Published private(set) var selectedDestination: SavedDestination?
    @Published private(set) var previewRoutes: [RouteOption] = []
    @Published var previewIndex = 0
    @Published private(set) var routeLoading = false
    @Published private(set) var routeError: String?
    @Published private(set) var state: State = .off
    @Published private(set) var activeDestination: SavedDestination?
    @Published private(set) var currentCoordinate: CLLocationCoordinate2D?
    @Published private(set) var engine: NavigationEngine?
    @Published private(set) var routeLine: MKPolyline?
    @Published private(set) var bearing: Double?
    private var orientation = NavigationOrientation()
    var onCue: ((NavigationCue) -> Void)?
    var onArrival: ((SavedDestination) -> Void)?
    var onRouteChanged: (() -> Void)?
    private let locator = CLLocationManager()
    private var currentFix: TrackPoint?
    private var searchTask: Task<Void, Never>?
    private var localSearch: MKLocalSearch?
    private var previewDirections: MKDirections?
    private var activeDirections: MKDirections?
    private var previewGeneration = UUID()
    private var activeGeneration = UUID()
    private var waitingForPreviewFix = false
    private var locationWaitTask: Task<Void, Never>?
    private var previewUsers = 0
    private var workoutID: UUID?
    private var previewOrigin: NavigationCoordinate?
    private var lastReplan = Date.distantPast
    private var recentSpoken: [(NavigationVoice, NavigationCoordinate, Date, UUID)] = []
    private var writable = true
    private let directory: URL
    var selectedRoute: RouteOption? { previewRoutes.indices.contains(previewIndex) ? previewRoutes[previewIndex] : nil }
    var showsNavigation: Bool { activeDestination != nil }
    var remainingMeters: Double? { engine?.remainingMeters }
    var destinationTitle: String { activeDestination?.displayName ?? RunLanguage.text("跑去目的地") }
    var nextSymbol: String {
        if state == .navigating && !locationReliable { return "location.slash" }
        switch state { case .arrived: return "checkmark"; case .rerouting: return "arrow.triangle.2.circlepath"; case .failed, .waiting: return "location.slash"; default: return engine?.nextManeuver?.turn.symbol ?? "arrow.up" }
    }
    var instructionTitle: String {
        if state == .navigating && !locationReliable { return RunLanguage.text("正在确认当前位置") }
        switch state {
        case .arrived: return RunLanguage.text("已到达目的地")
        case .rerouting: return RunLanguage.text("正在重新规划")
        case .failed: return RunLanguage.text("路线暂不可用")
        case .waiting: return RunLanguage.text("等待定位，准备带路")
        default:
            guard let step = engine?.nextManeuver, let meters = engine?.maneuverRemaining else { return RunLanguage.text("沿路线继续") }
            let direction: String
            switch step.turn { case .left: direction = RunLanguage.text("左转"); case .right: direction = RunLanguage.text("右转"); case .uTurn: direction = RunLanguage.text("掉头"); default: direction = RunLanguage.text("查看路口指引") }
            if meters <= 15 { return step.turn == .unknown ? RunLanguage.text("按地图通过路口") : RunLanguage.text("前方路口") + direction }
            return RunLanguage.text("%1$@米后", "\(max(10, Int((meters / 10).rounded()) * 10))") + direction
        }
    }
    var instructionDetail: String {
        if state == .navigating && !locationReliable { return RunLanguage.text("定位信号较弱，训练计时继续") }
        if state == .arrived { return RunLanguage.text("导航已结束，跑走训练继续") }
        if state == .failed { return RunLanguage.text("训练继续记录，请联网后重试规划") }
        if state == .rerouting { return RunLanguage.text("找到新路线后继续带路") }
        if state == .waiting { return RunLanguage.text("定位恢复后自动规划，训练继续") }
        return engine?.nextManeuver?.instruction ?? activeDestination?.name ?? ""
    }
    var locationReliable: Bool { engine?.lastTrustedAt.map { Date().timeIntervalSince($0) <= 8 } ?? false }
    var mapCoordinates: [CLLocationCoordinate2D] { engine?.route.points.map(\.clCoordinate) ?? [] }
    var nextTurnCoordinate: CLLocationCoordinate2D? {
        guard let engine, let step = engine.nextManeuver, let position = engine.position else { return nil }
        return engine.route.project(position, from: step.metersFromStart, through: step.metersFromStart)?.coordinate.clCoordinate
    }
    func receiveHeading(_ degrees: Double, accuracy: Double, timestamp: Date) {
        orientation.heading(degrees, accuracy: accuracy, timestamp: timestamp, at: Date())
        if bearing != orientation.bearing { bearing = orientation.bearing }
    }
    var vancouverRegion: MKCoordinateRegion {
        MKCoordinateRegion(center: currentCoordinate ?? CLLocationCoordinate2D(latitude: 49.2827, longitude: -123.1207), span: MKCoordinateSpan(latitudeDelta: 0.07, longitudeDelta: 0.10))
    }

    func searchOrigin(at time: Date) -> NavigationCoordinate? {
        guard [.authorizedAlways, .authorizedWhenInUse].contains(locator.authorizationStatus),
              let fix = currentFix,
              (-1...15).contains(time.timeIntervalSince(fix.timestamp)) else { return nil }
        return NavigationCoordinate(latitude: fix.latitude, longitude: fix.longitude)
    }

    override init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SlowRunNavigation", isDirectory: true)
        super.init()
        locator.delegate = self; locator.desiredAccuracy = kCLLocationAccuracyBest
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("places.json")
            if FileManager.default.fileExists(atPath: file.path) { library = try JSONDecoder().decode(DestinationLibrary.self, from: Data(contentsOf: file)) }
        } catch { writable = false; storageError = RunLanguage.text("常去地点读取失败，原文件已保留。") }
    }
    func requestLocation() {
        switch locator.authorizationStatus {
        case .notDetermined: locator.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            if previewUsers > 0 { locator.startUpdatingLocation() } else { locator.requestLocation() }
        default: routeError = RunLanguage.text("请在系统设置中允许位置与精确位置，再规划路线。")
        }
        locationWaitTask?.cancel()
        locationWaitTask = Task {
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled, waitingForPreviewFix else { return }
            waitingForPreviewFix = false; routeLoading = false
            routeError = RunLanguage.text("尚未获得可靠位置，请到开阔处后重试。")
        }
    }
    func beginLocationPreview() { previewUsers += 1; requestLocation() }
    func endLocationPreview() { previewUsers = max(0, previewUsers - 1); if previewUsers == 0 { locator.stopUpdatingLocation() } }
    func prepare(_ place: SavedDestination) {
        selectedDestination = place; previewDirections?.cancel(); previewGeneration = UUID()
        previewRoutes = []; previewIndex = 0; routeError = nil
        library.select(place); saveLibrary()
        Task { await loadPreview() }
    }
    func loadPreview() async {
        guard let place = selectedDestination else { return }
        guard let fix = currentFix, Date().timeIntervalSince(fix.timestamp) <= 15, fix.accuracy >= 0, fix.accuracy <= 50 else {
            waitingForPreviewFix = true; routeLoading = true; routeError = RunLanguage.text("正在获取当前位置…"); requestLocation(); return
        }
        waitingForPreviewFix = false; locationWaitTask?.cancel(); routeLoading = true; routeError = nil
        previewDirections?.cancel(); let generation = UUID(); previewGeneration = generation
        let origin = NavigationCoordinate(latitude: fix.latitude, longitude: fix.longitude)
        let directions = makeDirections(from: origin, to: place.coordinate); previewDirections = directions
        do {
            let response = try await directions.calculate()
            guard previewGeneration == generation else { return }
            previewRoutes = Self.routeOptions(response.routes)
            previewIndex = 0; previewOrigin = origin
            if previewRoutes.isEmpty { routeError = RunLanguage.text("没有找到可用步行路线，请换一个入口或地点。") }
        } catch { if previewGeneration == generation { routeError = RunLanguage.text("步行路线规划失败，请检查网络后重试。") } }
        if previewGeneration == generation { routeLoading = false }
    }
    func beginPrepared(workoutID: UUID) -> Bool {
        guard let route = selectedRoute, let destination = selectedDestination, let fix = currentFix,
              Date().timeIntervalSince(fix.timestamp) <= 15, let origin = previewOrigin,
              origin.distance(to: NavigationCoordinate(latitude: fix.latitude, longitude: fix.longitude)) <= 75 else {
            routeError = RunLanguage.text("当前位置已变化或定位过期，请刷新路线再开始。"); return false
        }
        activeDirections?.cancel(); activeGeneration = UUID(); self.workoutID = workoutID
        locator.stopUpdatingLocation()
        activeDestination = destination; install(route); recentSpoken = []; persistActive()
        return true
    }
    func canBeginPrepared() -> Bool {
        guard selectedRoute != nil, let fix = currentFix, let origin = previewOrigin,
              Date().timeIntervalSince(fix.timestamp) <= 15,
              origin.distance(to: NavigationCoordinate(latitude: fix.latitude, longitude: fix.longitude)) <= 75 else {
            routeError = RunLanguage.text("请先获取当前位置并刷新路线。"); requestLocation(); return false
        }
        return true
    }
    func ingest(_ point: TrackPoint, enabled: Bool) {
        let now = Date(), coordinate = NavigationCoordinate(latitude: point.latitude, longitude: point.longitude)
        guard coordinate.isValid, point.accuracy.isFinite, point.accuracy >= 0, point.accuracy <= 50,
              now.timeIntervalSince(point.timestamp) >= -1, now.timeIntervalSince(point.timestamp) <= 5 else { return }
        orientation.motion(point, at: now)
        if bearing != orientation.bearing { bearing = orientation.bearing }
        if currentFix == nil || point.timestamp > currentFix!.timestamp { currentFix = point; currentCoordinate = coordinate.clCoordinate }
        if waitingForPreviewFix { waitingForPreviewFix = false; Task { await loadPreview() } }
        guard enabled, showsNavigation, state != .arrived else { return }
        if state == .waiting { retryRoute(); return }
        guard state == .navigating else { return }
        let events = engine?.update(point, receivedAt: now) ?? []
        for event in events {
            switch event {
            case .reroute: retryRoute()
            case .cue(let cue):
                if cue.voice == .arrived {
                    state = .arrived
                    if let activeDestination { onArrival?(activeDestination) }
                    clearActiveFile()
                    onRouteChanged?()
                }
                let anchor = engine?.route.maneuvers.first(where: { $0.id == cue.maneuverID }).flatMap { step in engine?.route.project(coordinate, from: step.metersFromStart, through: step.metersFromStart)?.coordinate } ?? coordinate
                recentSpoken.removeAll { now.timeIntervalSince($0.2) > 25 }
                if !recentSpoken.contains(where: { $0.3 != cue.routeID && $0.0 == cue.voice && $0.1.distance(to: anchor) < 20 }) {
                    recentSpoken.append((cue.voice, anchor, now, cue.routeID)); onCue?(cue)
                }
            }
        }
    }
    func canPlay(_ cue: NavigationCue) -> Bool {
        if cue.voice == .rerouting { return state == .rerouting && Date().timeIntervalSince(cue.createdAt) < 12 }
        return engine?.canPlay(cue, at: Date()) == true && state != .off
    }
    func retryRoute() {
        guard let destination = activeDestination, state != .arrived, Date().timeIntervalSince(lastReplan) >= 12,
              let fix = currentFix, Date().timeIntervalSince(fix.timestamp) <= 5, fix.accuracy <= 20 else { return }
        state = .rerouting; lastReplan = Date(); onRouteChanged?()
        if let id = engine?.route.id { onCue?(NavigationCue(voice: .rerouting, routeID: id)) }
        activeDirections?.cancel(); let generation = UUID(); activeGeneration = generation
        let directions = makeDirections(from: NavigationCoordinate(latitude: fix.latitude, longitude: fix.longitude), to: destination.coordinate); activeDirections = directions
        Task {
            do {
                let response = try await directions.calculate()
                guard generation == activeGeneration, showsNavigation else { return }
                guard let route = Self.routeOptions(response.routes).first else { state = .failed; return }
                onRouteChanged?(); install(route); persistActive()
            } catch { if generation == activeGeneration { state = .failed; onRouteChanged?() } }
        }
    }
    func stop() {
        locator.stopUpdatingLocation()
        activeGeneration = UUID(); activeDirections?.cancel(); onRouteChanged?()
        engine = nil; routeLine = nil; activeDestination = nil; workoutID = nil; state = .off; clearActiveFile()
    }
    func restore(workoutID: UUID) {
        let url = directory.appendingPathComponent("active.json")
        guard let data = try? Data(contentsOf: url), let item = try? JSONDecoder().decode(Active.self, from: data), item.workoutID == workoutID else { return }
        self.workoutID = workoutID; activeDestination = item.destination; state = .waiting
    }
    func toggleFavorite(_ place: SavedDestination) { guard writable else { return }; library.toggle(place); saveLibrary() }
    func renameFavorite(_ id: UUID, name: String) { guard writable else { return }; library.rename(id, to: name); saveLibrary() }
    func removeFavorite(_ place: SavedDestination) { if library.favorite(for: place) != nil { toggleFavorite(place) } }
    private func saveLibrary() {
        guard writable else { return }
        do { try JSONEncoder().encode(library).write(to: directory.appendingPathComponent("places.json"), options: .atomic) }
        catch { storageError = RunLanguage.text("常去地点保存失败，请稍后重试。") }
    }
    private struct Active: Codable { var workoutID: UUID; var destination: SavedDestination }
    private func persistActive() {
        guard let workoutID, let destination = activeDestination else { return }
        do { try JSONEncoder().encode(Active(workoutID: workoutID, destination: destination)).write(to: directory.appendingPathComponent("active.json"), options: .atomic) }
        catch { storageError = RunLanguage.text("导航暂存失败，重开 App 后可能需要重新选目的地。") }
    }
    private func clearActiveFile() { let url = directory.appendingPathComponent("active.json"); if FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.removeItem(at: url) } }
    private func install(_ option: RouteOption) {
        routeLine = option.route.polyline
        engine = NavigationEngine(route: option.geometry)
        state = .navigating
    }
    private func makeDirections(from origin: NavigationCoordinate, to destination: NavigationCoordinate) -> MKDirections {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.clCoordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.clCoordinate))
        request.transportType = .walking; request.requestsAlternateRoutes = true
        return MKDirections(request: request)
    }
    private static func routeOptions(_ routes: [MKRoute]) -> [RouteOption] {
        var options = routes.filter { $0.distance.isFinite && $0.distance > 0 && $0.polyline.pointCount >= 2 }
            .map { RouteOption(route: $0, geometry: coreRoute($0)) }
        if let index = WalkingRouteSummary.recommendedIndex(in: options.map(\.summary)), index != 0 {
            let recommended = options.remove(at: index)
            options.insert(recommended, at: 0)
        }
        return options
    }
    static func coordinates(_ polyline: MKPolyline) -> [NavigationCoordinate] {
        var result = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: polyline.pointCount)
        polyline.getCoordinates(&result, range: NSRange(location: 0, length: result.count))
        return result.map(NavigationCoordinate.init)
    }
    static func coreRoute(_ route: MKRoute) -> NavigationRoute {
        var value = NavigationRoute(points: coordinates(route.polyline), maneuvers: [])
        let routeLength = value.totalMeters
        var cursor = 0.0
        for (index, step) in route.steps.enumerated() {
            defer { cursor += max(0, step.distance) }
            let text = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, let anchor = coordinates(step.polyline).first else { continue }
            let lower = max(0, cursor - 40), upper = min(routeLength, cursor + max(100, step.distance + 50))
            let at = value.project(anchor, from: lower, through: upper)?.progress ?? cursor
            let lowerText = text.lowercased()
            guard !["arriv", "destination", "到达", "到達", RunLanguage.text("目的地")].contains(where: lowerText.contains) else { continue }
            let turn = NavigationTurn.parse(text)
            if at > 8, turn != .straight { value.maneuvers.append(.init(id: index, metersFromStart: at, turn: turn, instruction: text)) }
        }
        return value.resolvingTurnDirections()
    }
    private func scheduleSearch() {
        searchTask?.cancel(); localSearch?.cancel(); let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchError = nil
        searchResults = []
        guard !text.isEmpty else { searching = false; return }
        searching = true
        searchTask = Task {
            do {
                try await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                let request = MKLocalSearch.Request(); request.naturalLanguageQuery = text; request.region = vancouverRegion; request.resultTypes = [.address, .pointOfInterest]
                let search = MKLocalSearch(request: request); localSearch = search
                let response = try await search.start()
                guard !Task.isCancelled, query.trimmingCharacters(in: .whitespacesAndNewlines) == text else { return }
                searchResults = response.mapItems.compactMap { item in
                    let coordinate = NavigationCoordinate(item.placemark.coordinate)
                    guard coordinate.isValid else { return nil }
                    return SavedDestination(name: item.name ?? RunLanguage.text("地图地点"), address: item.placemark.title ?? "", coordinate: coordinate)
                }
                searching = false
                if searchResults.isEmpty { searchError = RunLanguage.text("没有找到地点，试试英文名、完整地址或地图选点。") }
            } catch { if !Task.isCancelled { searching = false; searchError = RunLanguage.text("搜索暂不可用，请检查网络后重试。") } }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fixes = locations.map { TrackPoint(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude, timestamp: $0.timestamp, accuracy: $0.horizontalAccuracy, speed: $0.speed >= 0 ? $0.speed : nil) }
        Task { @MainActor [weak self] in for fix in fixes { self?.ingest(fix, enabled: false) } }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if [.authorizedAlways, .authorizedWhenInUse].contains(locator.authorizationStatus) {
                if previewUsers > 0 { locator.startUpdatingLocation() } else { locator.requestLocation() }
            }
            else if locator.authorizationStatus != .notDetermined { routeLoading = false; routeError = RunLanguage.text("请在系统设置中允许位置与精确位置，再规划路线。") }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in self?.routeLoading = false; self?.routeError = RunLanguage.text("暂时无法获取当前位置，请到开阔处后重试。") }
    }
}
