import SwiftUI
import RunCore

@main @MainActor struct SlowRunApp: App {
    @AppStorage(RunLanguage.key) private var language = ""
    @StateObject private var settings: AppSettings
    @StateObject private var store: RunStore
    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _store = StateObject(wrappedValue: RunStore(settings: settings))
    }
    var body: some Scene {
        WindowGroup {
            Group {
                if language == "en" || language == "zh-Hans" {
                    RootView().environmentObject(settings).environmentObject(store)
                        .environment(\.locale, Locale(identifier: language)).id(language)
                } else {
                    VStack(alignment: .leading, spacing: 20) {
                        Image(systemName: "figure.run").font(.largeTitle).foregroundStyle(Theme.teal)
                        Text(verbatim: "选择语言").font(.largeTitle.bold())
                        Text(verbatim: "Choose your language").font(.title2)
                        PrimaryButton(title: "English", symbol: "chevron.right") { language = "en" }
                        PrimaryButton(title: "简体中文", symbol: "chevron.right") { language = "zh-Hans" }
                    }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.background)
                }
            }.tint(Theme.teal).preferredColorScheme(.dark)
        }
    }
}
