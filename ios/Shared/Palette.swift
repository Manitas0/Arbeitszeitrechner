import SwiftUI
import UIKit

/// Farben wie in der Android-App (Material-Farbschema), jeweils für Hell und Dunkel.
enum Palette {
    static let accent = adaptive(light: 0x1B6B5A, dark: 0x8AD6C0)
    static let onAccent = adaptive(light: 0xFFFFFF, dark: 0x00382D)

    /// Wochenkarte (primaryContainer)
    static let summaryBackground = adaptive(light: 0xA6F2DC, dark: 0x005143)
    static let onSummary = adaptive(light: 0x002019, dark: 0xA6F2DC)

    /// Karte von heute (secondaryContainer)
    static let todayBackground = adaptive(light: 0xCDE8DD, dark: 0x344C44)
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)

    /// Hinweis-Karte (tertiaryContainer)
    static let hintBackground = adaptive(light: 0xC5E7FF, dark: 0x284A5E)
    static let onHint = adaptive(light: 0x001E2D, dark: 0xC5E7FF)

    /// Urlaub, Krank, Feiertag (tertiary)
    static let absence = adaptive(light: 0x416277, dark: 0xA9CBE3)
    /// Warnungen: Grenze überschritten, über 10 h, jetzt ausstempeln
    static let negative = adaptive(light: 0xB3261E, dark: 0xFFB4AB)
    /// Überstunden
    static let positive = adaptive(light: 0x1E7A3A, dark: 0x7DDB94)
    /// Beginn oder Ende fehlt, ungültige Eingabe
    static let error = adaptive(light: 0xB3261E, dark: 0xF2B8B5)

    static let widgetBackground = adaptive(light: 0xF4FBF7, dark: 0x1B2320)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? Palette.uiColor(dark) : Palette.uiColor(light)
        })
    }

    private static func uiColor(_ rgb: UInt32) -> UIColor {
        return UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
