import SwiftUI
import ArbeitszeitKit

@main
struct ArbeitszeitApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(Palette.accent)
        }
    }
}

/// Seiten, auf die von der Wochenübersicht aus navigiert wird.
enum AppRoute: Hashable {
    case settings
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [AppRoute] = []

    var body: some View {
        content
            .messageBanner($model.banner)
            .onChange(of: scenePhase) { _, phase in
                // Es kann inzwischen per Widget, Kontrollzentrum oder Siri gestempelt worden sein.
                if phase == .active {
                    model.reload()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if LaunchOptions.widgetPreview {
            WidgetPreviewView()
        } else {
            NavigationStack(path: $path) {
                WeekView(openSettings: { path.append(.settings) })
                    .navigationDestination(for: AppRoute.self) { route in
                        switch route {
                        case .settings:
                            SettingsView(settings: model.settings, onDone: { path.removeAll() })
                        }
                    }
            }
        }
    }
}
