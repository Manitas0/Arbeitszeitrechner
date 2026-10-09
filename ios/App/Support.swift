import SwiftUI
import UniformTypeIdentifiers

/// Textdatei für den Datei-Export (Sicherung als JSON, Stundenzettel als CSV), immer UTF-8.
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        return [.json, .commaSeparatedText, .plainText]
    }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = String(decoding: data, as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// true, wenn der Nutzer den Dateidialog abgebrochen hat (dann keine Fehlermeldung).
func isUserCancellation(_ error: Error) -> Bool {
    let nsError = error as NSError
    return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
}

/// Kurze Meldung unten am Bildschirmrand, die nach ein paar Sekunden verschwindet.
struct MessageBanner: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let text = message {
                    Text(verbatim: text)
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: Color.black.opacity(0.15), radius: 8, y: 2)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .accessibilityIdentifier("banner")
                        .task(id: text) {
                            try? await Task.sleep(for: .seconds(2.5))
                            withAnimation {
                                message = nil
                            }
                        }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: message)
    }
}

extension View {
    func messageBanner(_ message: Binding<String?>) -> some View {
        return modifier(MessageBanner(message: message))
    }
}

/// Bezeichnung mit Erklärung darunter, z. B. für Schalter in den Einstellungen.
struct TitleWithDescription: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: title)
            Text(verbatim: description)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
