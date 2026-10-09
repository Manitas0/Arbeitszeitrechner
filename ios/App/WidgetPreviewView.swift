import SwiftUI
import ArbeitszeitKit

/// Seite mit den Widget-Ansichten in Widget-Größe, nur für Bildschirmfotos (`-AZWidgetPreview YES`).
struct WidgetPreviewView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let snapshot = WidgetSnapshot(entries: model.entries, settings: model.settings, now: model.now)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Widget-Vorschau")
                    .font(.title2.weight(.bold))
                    .accessibilityIdentifier("widget-preview-title")

                caption("Stempeln (klein) – hell und dunkel")
                HStack(spacing: 12) {
                    WidgetFrame(width: 170, height: 170) {
                        ClockWidgetView(snapshot: snapshot)
                    }
                    WidgetFrame(width: 170, height: 170) {
                        ClockWidgetView(snapshot: snapshot)
                    }
                    .environment(\.colorScheme, .dark)
                }

                caption("Woche (mittel)")
                WidgetFrame(width: 364, height: 170) {
                    WeekWidgetView(snapshot: snapshot)
                }
                WidgetFrame(width: 364, height: 170) {
                    WeekWidgetView(snapshot: snapshot)
                }
                .environment(\.colorScheme, .dark)

                caption("Kontrollzentrum (ab iOS 18)")
                ControlPreview(action: snapshot.action)
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }

    private func caption(_ text: String) -> some View {
        return Text(verbatim: text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

/// Rahmen in Widget-Größe mit Hintergrund und Innenabstand wie auf dem Homescreen.
private struct WidgetFrame<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    let content: Content

    init(width: CGFloat, height: CGFloat, @ViewBuilder content: () -> Content) {
        self.width = width
        self.height = height
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: width)
            .frame(height: height)
            .background(Palette.widgetBackground)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color.black.opacity(0.12), radius: 6, y: 2)
    }
}

/// Nachbildung des Knopfs im Kontrollzentrum.
private struct ControlPreview: View {
    let action: ClockAction?

    var body: some View {
        let title = action?.label ?? "Feierabend"
        let symbol = action?.symbolName ?? "clock"
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Color.white)
                .frame(width: 64, height: 64)
                .background(Color.gray.opacity(0.75), in: Circle())
            Text(verbatim: title)
                .font(.caption.weight(.medium))
        }
    }
}
