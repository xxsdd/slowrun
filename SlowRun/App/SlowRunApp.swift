import SwiftUI

@main @MainActor struct SlowRunApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var store: RunStore
    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _store = StateObject(wrappedValue: RunStore(settings: settings))
    }
    var body: some Scene {
        WindowGroup { RootView().environmentObject(settings).environmentObject(store).tint(Theme.teal).preferredColorScheme(.dark) }
    }
}
