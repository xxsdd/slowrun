import SwiftUI
import MapKit
import RunCore

struct DestinationSearchView: View {
    @EnvironmentObject private var store: RunStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var navigation: NavigationCoordinator
    @State private var preview = false
    @State private var picking = false
    @State private var managing = false
    @State private var pendingPoint: SavedDestination?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 21) {
                VStack(alignment: .leading, spacing: 9) {
                    Text(RunLanguage.text("想跑去哪里？")).font(.system(size: 31, weight: .bold))
                    Label(RunLanguage.text("温哥华 · 从当前位置出发"), systemImage: "location.fill").font(.caption).foregroundStyle(Theme.secondary)
                }
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
                    TextField(RunLanguage.text("地点、公园或地址"), text: $navigation.query).autocorrectionDisabled().submitLabel(.search)
                    if !navigation.query.isEmpty { Button { navigation.query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel(RunLanguage.text("清空搜索")) }
                }.padding(15).background(RunPalette.raised, in: RoundedRectangle(cornerRadius: 14))
                Button { picking = true } label: { Label(RunLanguage.text("在地图上选点"), systemImage: "mappin.and.ellipse").frame(maxWidth: .infinity, minHeight: 40, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.plain).foregroundStyle(Theme.teal)
                if let error = navigation.storageError { Text(error).font(.caption).foregroundStyle(.orange) }
                if navigation.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack { Text(RunLanguage.text("常去地点")).font(.headline); Spacer(); Button(RunLanguage.text("管理")) { managing = true }.font(.subheadline) }
                    if navigation.library.favorites.isEmpty { Text(RunLanguage.text("搜索地点后点星标，下次就能在这里直接选择。")).font(.subheadline).foregroundStyle(Theme.secondary) }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(navigation.library.favorites) { place in
                            Button { choose(place) } label: {
                                VStack(alignment: .leading, spacing: 11) {
                                    HStack { Image(systemName: "star.fill").foregroundStyle(Theme.teal); Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(Theme.secondary) }
                                    Text(place.displayName).font(.headline).lineLimit(1)
                                    Text(place.name).font(.caption2).foregroundStyle(Theme.secondary).lineLimit(1)
                                }.padding(16).frame(maxWidth: .infinity, minHeight: 112, alignment: .leading).background(RunPalette.raised, in: RoundedRectangle(cornerRadius: 16)).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                    Text(RunLanguage.text("最近选择")).font(.headline).padding(.top, 3)
                    if navigation.library.recent.isEmpty { Text(RunLanguage.text("选择过的地点会出现在这里。")).font(.subheadline).foregroundStyle(Theme.secondary) }
                    ForEach(navigation.library.recent) { place in placeRow(place) }
                } else {
                    if navigation.searching { HStack { ProgressView(); Text(RunLanguage.text("正在搜索地点…")).foregroundStyle(Theme.secondary) }.font(.subheadline) }
                    if let error = navigation.searchError { Text(error).font(.subheadline).foregroundStyle(Theme.secondary) }
                    if !navigation.searchResults.isEmpty {
                        TimelineView(.periodic(from: .now, by: 5)) { _ in
                            searchResults(at: .now)
                        }
                    }
                }
                Text(RunLanguage.text("收藏保存目的地，每次从你的出发位置重新规划。地图搜索和路线规划需要联网。")).font(.caption).foregroundStyle(Theme.secondary).padding(.top, 10)
            }.padding(22)
        }.scrollDismissesKeyboard(.interactively).background(Theme.background).navigationTitle(RunLanguage.text("跑去目的地")).navigationBarTitleDisplayMode(.inline)
        .onAppear { navigation.query = ""; navigation.beginLocationPreview() }
        .onDisappear { navigation.endLocationPreview() }
        .sheet(isPresented: $preview) {
            NavigationStack {
                DestinationRoutePreview(navigation: navigation) {
                    if store.startDestination() { preview = false; dismiss() }
                }
            }
        }
        .sheet(isPresented: $picking, onDismiss: { if let point = pendingPoint { pendingPoint = nil; choose(point) } }) {
            NavigationStack { DestinationMapPicker(navigation: navigation) { place in pendingPoint = place; picking = false } }
        }
        .sheet(isPresented: $managing) { NavigationStack { FavoriteDestinationsView(navigation: navigation) } }
    }
    private func choose(_ place: SavedDestination) { navigation.prepare(place); preview = true }
    private func searchResults(at time: Date) -> some View {
        let origin = navigation.searchOrigin(at: time)
        let results = DestinationSearchResult.ranked(navigation.searchResults, from: origin)
        return VStack(alignment: .leading, spacing: 5) {
            Text(origin == nil ? RunLanguage.text("取得当前位置后按距离排序") : RunLanguage.text("直线距离 · 从近到远"))
                .font(.caption).foregroundStyle(Theme.secondary)
            ForEach(results.prefix(15)) { result in
                placeRow(result.place, distance: result.distanceMeters)
            }
        }
    }
    private func placeRow(_ place: SavedDestination, distance: Double? = nil) -> some View {
        HStack(spacing: 10) {
            Button { choose(place) } label: {
                HStack(spacing: 11) {
                    Image(systemName: "mappin.circle").font(.title2).foregroundStyle(Theme.secondary)
                    VStack(alignment: .leading, spacing: 6) { Text(place.name).font(.subheadline).foregroundStyle(Theme.ink); Text(place.address).font(.caption2).foregroundStyle(Theme.secondary).lineLimit(2) }
                    Spacer(minLength: 0)
                    if let distance {
                        Text(distanceLabel(distance))
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(Theme.teal).fixedSize()
                            .accessibilityLabel(RunLanguage.text("直线距离 ") + distanceLabel(distance))
                    }
                }.frame(maxWidth: .infinity, minHeight: 58, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button { navigation.toggleFavorite(place) } label: { Image(systemName: navigation.library.favorite(for: place) == nil ? "star" : "star.fill").frame(width: 44, height: 44).contentShape(Rectangle()) }
                .accessibilityLabel(navigation.library.favorite(for: place) == nil ? RunLanguage.text("收藏 ") + place.name : RunLanguage.text("取消收藏 ") + place.name)
        }.padding(.vertical, 4).overlay(alignment: .bottom) { Rectangle().fill(RunPalette.line).frame(height: 0.5) }
    }
    private func distanceLabel(_ meters: Double) -> String {
        let rounded = meters.rounded()
        return rounded < 1000 ? String(format: RunLanguage.text("%.0f 米"), rounded) : String(format: RunLanguage.text("%.1f 公里"), meters / 1000)
    }
}

struct FavoriteDestinationsView: View {
    @ObservedObject var navigation: NavigationCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var editing: SavedDestination?
    @State private var nickname = ""
    var body: some View {
        List {
            Section(RunLanguage.text("给地点起一个好认的名字")) {
                ForEach(navigation.library.favorites) { place in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(place.displayName).font(.headline)
                        Text(place.name).font(.caption).foregroundStyle(Theme.secondary)
                        HStack { Button(RunLanguage.text("改名")) { nickname = place.displayName; editing = place }.buttonStyle(.borderless); Spacer(); Button(RunLanguage.text("移除收藏"), role: .destructive) { navigation.removeFavorite(place) }.buttonStyle(.borderless) }
                    }.padding(.vertical, 7).listRowBackground(RunPalette.surface)
                }
                if navigation.library.favorites.isEmpty { Text(RunLanguage.text("还没有常去地点。")).foregroundStyle(Theme.secondary).listRowBackground(RunPalette.surface) }
            }
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle(RunLanguage.text("管理常去地点"))
            .toolbar { Button(RunLanguage.text("完成")) { dismiss() } }
            .alert(RunLanguage.text("给地点起个名字"), isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
                TextField(RunLanguage.text("显示名称"), text: $nickname)
                Button(RunLanguage.text("保存")) { if let editing { navigation.renameFavorite(editing.id, name: nickname) }; editing = nil }
                Button(RunLanguage.text("取消"), role: .cancel) { editing = nil }
            }
    }
}

struct DestinationRoutePreview: View {
    @EnvironmentObject private var store: RunStore
    @ObservedObject var navigation: NavigationCoordinator
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    var onStart: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                if let option = navigation.selectedRoute, let place = navigation.selectedDestination {
                    let route = option.route
                    Map {
                        MapPolyline(route.polyline).stroke(Theme.teal, lineWidth: 6)
                        Marker(place.name, coordinate: place.coordinate.clCoordinate).tint(Theme.teal)
                        if let source = navigation.currentCoordinate { Annotation(RunLanguage.text("当前位置"), coordinate: source) { LocationDot() } }
                    }.mapStyle(.standard(elevation: .flat)).frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 18))
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(format: "%.2f", route.distance / 1000)).font(.system(size: 31, weight: .semibold)).monospacedDigit()
                        Text(RunLanguage.text("公里")).font(.subheadline)
                        Spacer()
                        Text(RunLanguage.text("步行路线 · %1$@ 处转向", "\(option.summary.turns)")).font(.caption).foregroundStyle(Theme.secondary)
                    }
                    if navigation.previewRoutes.count > 1 {
                        Picker(RunLanguage.text("选择路线"), selection: $navigation.previewIndex) {
                            ForEach(navigation.previewRoutes.indices, id: \.self) { index in
                                let summary = navigation.previewRoutes[index].summary
                                let name = index == 0 ? RunLanguage.text("推荐") : RunLanguage.text("路线 %1$@", "\(index + 1)")
                                Text(String(format: RunLanguage.text("%@ · %.2f 公里 · %d 处转向"), name, summary.distance / 1000, summary.turns)).tag(index)
                            }
                        }.pickerStyle(.menu)
                    }
                    HStack { Text(place.name).font(.headline); Spacer(); Button { navigation.toggleFavorite(place) } label: { Label(navigation.library.favorite(for: place) == nil ? RunLanguage.text("收藏") : RunLanguage.text("已收藏"), systemImage: navigation.library.favorite(for: place) == nil ? "star" : "star.fill").font(.subheadline).frame(minHeight: 44) } }
                    if !place.address.isEmpty { Text(place.address).font(.caption).foregroundStyle(Theme.secondary) }
                } else {
                    VStack(spacing: 16) { if navigation.routeLoading { ProgressView(); Text(RunLanguage.text("正在规划步行路线…")) } else { Image(systemName: "map").font(.largeTitle); Text(RunLanguage.text("先确认路线，再出发")) } }.foregroundStyle(Theme.secondary).frame(maxWidth: .infinity, minHeight: 230)
                }
                if let error = navigation.routeError { Text(error).font(.subheadline).foregroundStyle(Theme.secondary) }
                if !navigation.routeLoading { Button(RunLanguage.text("刷新当前位置与路线")) { navigation.requestLocation(); Task { await navigation.loadPreview() } }.font(.subheadline).frame(minHeight: 40) }
                SurfaceCard {
                    VStack(spacing: 16) {
                        DataRow(title: RunLanguage.text("跑步段"), value: settings.freeWalkSeconds == 0 ? RunLanguage.text("不限时") : RunFormat.time(Double(settings.freeRunSeconds)))
                        DataRow(title: RunLanguage.text("步行段"), value: settings.freeWalkSeconds == 0 ? RunLanguage.text("不安排步行") : RunFormat.time(Double(settings.freeWalkSeconds)))
                        NavigationLink(RunLanguage.text("调整跑走时长")) { TrainingPreferencesView() }.font(.subheadline)
                        DataRow(title: RunLanguage.text("热身"), value: RunLanguage.text("步行 5 分钟，立即开始带路"))
                    }
                }
                Text(RunLanguage.text("转弯时先播导航，再播跑走切换。到达后导航结束，训练继续记录。")).font(.caption).foregroundStyle(Theme.secondary)
                if !store.hasWorkout {
                    SurfaceCard { DistanceGoalPicker() }
                    AudiobookWorkoutToggle()
                }
                PrimaryButton(title: RunLanguage.text("确认路线，开始"), symbol: "location.fill", action: onStart).disabled(navigation.selectedRoute == nil || navigation.routeLoading)
            }.padding(22)
        }.background(Theme.background).navigationTitle(RunLanguage.text("确认路线")).navigationBarTitleDisplayMode(.inline)
            .onAppear { navigation.beginLocationPreview() }.onDisappear { navigation.endLocationPreview() }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(RunLanguage.text("返回")) { dismiss() } } }
    }
}

struct DestinationMapPicker: View {
    @ObservedObject var navigation: NavigationCoordinator
    @Environment(\.dismiss) private var dismiss
    var onSelect: (SavedDestination) -> Void
    @State private var point: CLLocationCoordinate2D?
    @State private var camera: MapCameraPosition = .automatic
    var body: some View {
        VStack(spacing: 0) {
            MapReader { proxy in
                Map(position: $camera) {
                    if let point { Marker(RunLanguage.text("目的地"), coordinate: point).tint(Theme.teal) }
                    if let current = navigation.currentCoordinate { Annotation(RunLanguage.text("当前位置"), coordinate: current) { LocationDot() } }
                }.mapStyle(.standard(elevation: .flat))
                    .onTapGesture { position in if let coordinate = proxy.convert(position, from: .local) { point = coordinate } }
            }
            VStack(alignment: .leading, spacing: 14) {
                Text(RunLanguage.text("移动地图，轻点想去的位置。")).font(.subheadline).foregroundStyle(Theme.secondary)
                PrimaryButton(title: RunLanguage.text("选择这个位置"), symbol: "mappin") {
                    guard let point else { return }
                    onSelect(SavedDestination(name: RunLanguage.text("地图选点"), address: RunLanguage.text("可收藏并改名"), coordinate: NavigationCoordinate(point)))
                }.disabled(point == nil)
            }.padding(20).background(RunPalette.surface)
        }.background(Theme.background).navigationTitle(RunLanguage.text("地图选点")).navigationBarTitleDisplayMode(.inline)
            .onAppear { camera = .region(navigation.vancouverRegion); navigation.beginLocationPreview() }
            .onDisappear { navigation.endLocationPreview() }.toolbar { Button(RunLanguage.text("取消")) { dismiss() } }
    }
}

struct LocationDot: View {
    var body: some View { Circle().fill(Color.blue).frame(width: 13, height: 13).overlay(Circle().stroke(.white, lineWidth: 3)).padding(8).background(Color.blue.opacity(0.16), in: Circle()) }
}

struct DestinationRunningView: View {
    @EnvironmentObject private var store: RunStore
    @ObservedObject var navigation: NavigationCoordinator
    @State private var camera: MapCameraPosition = .automatic
    @State private var confirmFinish = false
    @State private var changingDestination = false
    @State private var showDetails = false
    @State private var following = true
    @State private var zoomDistance: Double = 350
    @State private var cameraHeading: Double = 0
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    Map(position: $camera) {
                        if !navigation.mapCoordinates.isEmpty { MapPolyline(coordinates: navigation.mapCoordinates).stroke(Theme.teal, lineWidth: 6) }
                        if let place = navigation.activeDestination { Marker(place.displayName, coordinate: place.coordinate.clCoordinate).tint(Theme.teal) }
                        if let point = navigation.nextTurnCoordinate, navigation.locationReliable {
                            Annotation(RunLanguage.text("下一个转弯"), coordinate: point) { Circle().fill(Theme.teal).frame(width: 15, height: 15).overlay(Circle().stroke(RunPalette.surface, lineWidth: 3)) }
                        }
                        if let current = navigation.currentCoordinate {
                            Annotation(RunLanguage.text("当前位置"), coordinate: current) {
                                if let bearing = navigation.bearing {
                                    NavigationPositionArrow().fill(Color.blue).overlay(NavigationPositionArrow().stroke(.white, lineWidth: 2))
                                        .frame(width: 22, height: 29).rotationEffect(.degrees(bearing - cameraHeading))
                                        .padding(12).background(Color.blue.opacity(0.14), in: Circle())
                                } else { LocationDot() }
                            }
                        }
                    }.mapStyle(.standard(elevation: .flat))
                    .onChange(of: camera.positionedByUser) { _, user in if user { following = false } }
                    .onMapCameraChange(frequency: .continuous) { context in
                        cameraHeading = context.camera.heading
                        if camera.positionedByUser { following = false; zoomDistance = max(80, min(20000, context.camera.distance)) }
                    }
                    VStack(spacing: 0) {
                        HStack(spacing: 14) {
                            Image(systemName: navigation.nextSymbol).font(.system(size: 32, weight: .semibold)).foregroundStyle(Theme.teal).frame(width: 39)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(navigation.instructionTitle).font(.system(size: 23, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.65)
                                Text(navigation.instructionDetail).font(.caption).foregroundStyle(Theme.secondary).lineLimit(2)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(15).background(RunPalette.surface, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(RunPalette.line))
                        Spacer()
                        HStack {
                            Label(RunLanguage.text("目的地"), systemImage: "mappin.circle.fill").font(.caption)
                            Spacer()
                            if navigation.state == .arrived { Text(RunLanguage.text("已到达")).font(.headline) }
                            else if navigation.state == .rerouting || navigation.state == .failed || navigation.state == .waiting { Text(RunLanguage.text("正在更新路线")).font(.caption).foregroundStyle(Theme.secondary) }
                            else { Text(RunLanguage.text("还有")).font(.caption).foregroundStyle(Theme.secondary); Text(navigation.remainingMeters.map { String(format: RunLanguage.text("%.2f 公里"), $0 / 1000) } ?? "—").font(.headline).monospacedDigit() }
                            Button { following = true; recenter(force: true) } label: { Image(systemName: "location.north.line.fill").frame(width: 44, height: 44).foregroundStyle(following ? Theme.teal : RunPalette.background).background(following ? RunPalette.raised : RunPalette.text, in: Circle()) }.accessibilityLabel(RunLanguage.text("回到导航"))
                        }.padding(.horizontal, 13).padding(.vertical, 7).background(RunPalette.surface, in: RoundedRectangle(cornerRadius: 14))
                    }.padding(13).padding(.bottom, 22)
                }.frame(maxWidth: .infinity).frame(height: max(160, geometry.size.height - (store.record?.distanceGoalMeters == nil ? 298 : 385)))
                if let record = store.record {
                    VStack(spacing: 13) {
                        HStack {
                            Text(record.status == .paused ? RunLanguage.text("已暂停") : record.currentPhase.title + " · " + (record.stage.kind == .run ? RunLanguage.text("跑步") : RunLanguage.text("步行"))).font(.caption.weight(.semibold)).foregroundStyle(Theme.teal)
                            Spacer()
                            Text(RunLanguage.text("本段剩余 ") + (record.stageRemainingSeconds.map(RunFormat.time) ?? "∞")).font(.caption).monospacedDigit()
                        }
                        HStack(alignment: .top, spacing: 8) {
                            navMetric(record.currentPhaseMeters.map { String(format: "%.2f", $0 / 1000) } ?? "—", label: record.currentPhase.metricTitle + RunLanguage.text("距离 · 公里"))
                            navMetric(RunFormat.pace(record.currentPace), label: RunLanguage.text("当前配速"), accent: true)
                            navMetric(RunFormat.time(record.currentPhaseSeconds), label: record.currentPhase.metricTitle + RunLanguage.text("用时"))
                        }.padding(.vertical, 8)
                        HStack {
                            Text(RunLanguage.text("步频 ") + (record.cadence.map { String(format: RunLanguage.text("%.0f 步/分"), $0) } ?? "—")).font(.caption).foregroundStyle(Theme.secondary)
                            Spacer()
                            Button(RunLanguage.text("更多数据")) { showDetails = true }.font(.caption)
                            if navigation.state == .failed { Button(RunLanguage.text("重试路线")) { navigation.retryRoute() }.font(.caption) }
                        }
                        if record.distanceGoalMeters != nil { DistanceGoalProgressView(record: record) }
                        HStack(spacing: 10) {
                            Button { store.togglePause() } label: { Label(record.status == .paused ? RunLanguage.text("继续训练") : RunLanguage.text("暂停"), systemImage: record.status == .paused ? "play.fill" : "pause.fill").frame(maxWidth: .infinity, minHeight: 48).background(RunPalette.raised, in: RoundedRectangle(cornerRadius: 13)).contentShape(Rectangle()) }.buttonStyle(.plain)
                            Button { confirmFinish = true } label: { Label(RunLanguage.text("结束训练"), systemImage: "stop.fill").frame(maxWidth: .infinity, minHeight: 48).foregroundStyle(RunPalette.background).background(RunPalette.text, in: RoundedRectangle(cornerRadius: 13)).contentShape(Rectangle()) }.buttonStyle(.plain)
                        }.font(.subheadline.weight(.semibold))
                        if [.warmup, .cooldown].contains(record.stage.kind) { Button(record.stage.kind == .warmup ? RunLanguage.text("跳过热身") : RunLanguage.text("结束放松，保存训练")) { store.skipPreparation() }.font(.caption).frame(minHeight: 26) }
                        else { Text(navigation.state == .arrived ? RunLanguage.text("导航已结束，训练继续") : RunLanguage.text("训练距离与距目的地分别统计")).font(.caption2).foregroundStyle(Theme.secondary) }
                    }.padding(.horizontal, 20).padding(.vertical, 16).background(RunPalette.surface)
                }
            }.background(Theme.background)
        }.navigationTitle(navigation.destinationTitle).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(RunLanguage.text("换目的地")) { changingDestination = true }.font(.caption) } }
            .onAppear { recenter() }
            .onChange(of: navigation.currentCoordinate?.latitude) { _, _ in if following { recenter() } }
            .onChange(of: navigation.currentCoordinate?.longitude) { _, _ in if following { recenter() } }
            .onChange(of: navigation.bearing) { _, _ in if following { recenter() } }
            .sheet(isPresented: $changingDestination) { NavigationStack { DestinationSearchView(navigation: navigation) } }
            .sheet(isPresented: $showDetails) { NavigationStack { ScrollView { if let record = store.record { VStack(spacing: 22) { SecondaryMetrics(record: record); PhaseBreakdown(record: record); Text(store.locationMessage).font(.caption).foregroundStyle(Theme.secondary) }.padding(22) } }.background(Theme.background).navigationTitle(RunLanguage.text("本次训练")).toolbar { Button(RunLanguage.text("完成")) { showDetails = false } } } }
            .confirmationDialog(RunLanguage.text("结束本次训练"), isPresented: $confirmFinish, titleVisibility: .visible) {
                Button(RunLanguage.text("立即结束并保存")) { store.finish() }
                if store.record?.stage.kind != .cooldown { Button(RunLanguage.text("步行放松 5 分钟")) { store.beginCooldown() } }
                Button(RunLanguage.text("继续训练"), role: .cancel) { }
            }
    }
    private func recenter(force: Bool = false) {
        guard force || (following && !camera.positionedByUser), let coordinate = navigation.currentCoordinate else { return }
        withAnimation(.linear(duration: 0.3)) { camera = .camera(MapCamera(centerCoordinate: coordinate, distance: zoomDistance, heading: navigation.bearing ?? cameraHeading, pitch: 0)) }
    }
    private func navMetric(_ value: String, label: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(label).font(.system(size: 10)).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.8); Text(value).font(.system(size: 27, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(accent ? Theme.teal : Theme.ink).lineLimit(1).minimumScaleFactor(0.6) }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
