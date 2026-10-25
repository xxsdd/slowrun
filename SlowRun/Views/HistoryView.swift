import SwiftUI
import RunCore

struct HistoryView: View {
    @EnvironmentObject private var store: RunStore
    var body: some View {
        ScrollView {
            if store.history.isEmpty {
                ContentUnavailableView("还没有训练记录", systemImage: "figure.run", description: Text("完成一趟训练后，在这里回看。"))
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(store.history) { record in
                        NavigationLink { WorkoutDetailView(initialRecord: record) } label: {
                            SurfaceCard {
                                VStack(alignment: .leading, spacing: 16) {
                                    HStack {
                                        Text(record.startedAt, format: .dateTime.month().day()).foregroundStyle(Theme.secondary)
                                        Spacer()
                                        Text(record.completionTitle).foregroundStyle(record.isCompleted ? Theme.teal : Theme.secondary)
                                        Image(systemName: "chevron.right").foregroundStyle(Theme.secondary)
                                    }.font(.caption)
                                    Text(record.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                                    HStack(alignment: .firstTextBaseline, spacing: 24) {
                                        item(String(format: "%.2f", record.mainMeters / 1000), label: "训练公里")
                                        item(RunFormat.time(record.mainSeconds), label: "训练用时")
                                    }
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                }.padding(22)
            }
        }.background(Theme.background).navigationTitle("训练记录")
    }
    private func item(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.system(size: 29, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.ink)
            Text(label).font(.caption2).foregroundStyle(Theme.secondary)
        }
    }
}
