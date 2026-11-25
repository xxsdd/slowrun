import SwiftUI
import MapKit
import RunCore

enum Theme {
    static let ink = RunPalette.text
    static let teal = RunPalette.mint
    static let pale = RunPalette.surface
    static let background = RunPalette.background
    static let secondary = RunPalette.secondary
}
struct PrimaryButton: View {
    let title: String
    var symbol: String? = nil
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) { if let symbol { Image(systemName: symbol) }; Text(title).fontWeight(.semibold) }
                .frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(RunPalette.onMint)
                .background(Theme.teal, in: RoundedRectangle(cornerRadius: 17))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
struct AudiobookWorkoutToggle: View {
    @EnvironmentObject private var store: RunStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        let silent = settings.voiceMode == .silent
        let detail = silent ? RunLanguage.text("语音已在设置中关闭") : RunLanguage.text("仅这一次，只播转弯、跑走切换和到达。")
        Toggle(isOn: silent ? .constant(false) : $store.audiobookForNextWorkout) {
            HStack(spacing: 12) {
                Image(systemName: "headphones")
                    .font(.title3).foregroundStyle(Theme.teal).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(RunLanguage.text("今天听书")).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch).tint(Theme.teal).disabled(silent)
        .accessibilityLabel(RunLanguage.text("今天听书")).accessibilityHint(Text(detail))
        .padding(16).background(RunPalette.raised, in: RoundedRectangle(cornerRadius: 17))
    }
}
struct SurfaceCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(RunPalette.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(RunPalette.line.opacity(0.65), lineWidth: 0.5))
    }
}
struct DataRow: View {
    let title: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) { Text(title).foregroundStyle(Theme.secondary); Spacer(minLength: 12); Text(value).monospacedDigit().multilineTextAlignment(.trailing) }.font(.subheadline)
    }
}
struct TrainingMetrics: View {
    let distance: String
    let pace: String
    let elapsed: String
    var phase = RunLanguage.text("训练")
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            column(distance, title: phase + RunLanguage.text("距离"), unit: RunLanguage.text("公里"))
            column(pace, title: RunLanguage.text("当前配速"), unit: RunLanguage.text("分 / 公里"), accent: true)
            column(elapsed, title: phase + RunLanguage.text("用时"), unit: elapsed.filter { $0 == ":" }.count == 2 ? RunLanguage.text("时 : 分 : 秒") : RunLanguage.text("分 : 秒"))
        }.padding(.vertical, 22)
            .overlay(alignment: .top) { Rectangle().fill(RunPalette.line).frame(height: 0.5) }
            .overlay(alignment: .bottom) { Rectangle().fill(RunPalette.line).frame(height: 0.5) }
    }
    private func column(_ value: String, title: String, unit: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(.system(size: 31, weight: .semibold, design: .rounded)).monospacedDigit().tracking(-1).lineLimit(1).minimumScaleFactor(0.48).foregroundStyle(accent ? Theme.teal : Theme.ink)
            Text(unit).font(.system(size: 10)).foregroundStyle(Theme.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct PhaseBreakdown: View {
    let record: WorkoutRecord
    var body: some View {
        DisclosureGroup(RunLanguage.text("阶段明细")) {
            VStack(spacing: 16) {
                if let totals = record.phaseStatistics {
                    ForEach(WorkoutPhase.allCases) { phase in
                        VStack(alignment: .leading, spacing: 7) {
                            DataRow(title: phase.title, value: String(format: RunLanguage.text("%.2f 公里 · "), totals[phase].meters / 1000) + RunFormat.time(totals[phase].seconds))
                            Text((totals[phase].steps.map { RunLanguage.text("%1$@ 步", "\($0)") } ?? RunLanguage.text("步数未获取")) + "　·　" + (totals[phase].calories.map { RunLanguage.text("约 %1$@ 千卡", "\(Int($0))") } ?? RunLanguage.text("热量未估算")))
                                .font(.caption).foregroundStyle(Theme.secondary)
                        }
                    }
                } else { Text(RunLanguage.text("旧版未分别保存热身与放松的数据，保留原有全程与训练总计。")).font(.caption).foregroundStyle(Theme.secondary) }
            }.padding(.top, 16)
        }.tint(Theme.secondary)
    }
}
struct Metric: View {
    let value: String
    let label: String
    var size: CGFloat = 29
    var body: some View {
        VStack(spacing: 6) {
            Text(value).font(.system(size: size, weight: .semibold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity)
    }
}
struct NoteBox: View {
    let title: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption.bold()).foregroundStyle(Theme.teal)
            Text(text).font(.subheadline).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(Theme.pale, in: RoundedRectangle(cornerRadius: 15))
    }
}
private struct RouteSegment: Identifiable {
    let id: Int
    let points: [TrackPoint]
    var coordinates: [CLLocationCoordinate2D] { points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) } }
}
struct RouteMap: View {
    let points: [TrackPoint]
    private var segments: [RouteSegment] {
        Dictionary(grouping: points, by: \.segment).map { RouteSegment(id: $0.key, points: $0.value) }.sorted { $0.id < $1.id }
    }
    var body: some View {
        Group {
            if points.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "location.magnifyingglass").font(.title2)
                    Text(RunLanguage.text("等待可信定位后显示路线")).font(.caption)
                }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.background)
            } else {
                Map(initialPosition: .automatic) {
                    ForEach(segments) { segment in
                        if segment.points.count > 1 { MapPolyline(coordinates: segment.coordinates).stroke(Theme.teal, lineWidth: 4) }
                    }
                    if let first = points.first {
                        Annotation(RunLanguage.text("起点"), coordinate: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)) {
                            Circle().fill(.white).frame(width: 10, height: 10).overlay(Circle().stroke(Theme.teal, lineWidth: 3))
                        }
                    }
                    if let last = points.last {
                        Annotation(RunLanguage.text("当前位置"), coordinate: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)) {
                            Circle().fill(Theme.teal).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                    }
                }.mapStyle(.standard(elevation: .flat))
            }
        }.clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
