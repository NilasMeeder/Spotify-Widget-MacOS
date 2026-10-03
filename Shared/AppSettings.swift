import Foundation

/// Preferences shared by the host app and the widget extension through the App Group.
enum AppSettings {
    static let store = UserDefaults(suiteName: AppGroup.id) ?? .standard

    static let menuBarShowsCoverKey = "menuBarShowsCover"
    static let menuBarShowsTitleKey = "menuBarShowsTitle"
    /// 0 is a solid widget; 1 lets the desktop show through as far as the text stays readable.
    static let widgetTransparencyKey = "widgetTransparency"
    /// 0 keeps the cover's color; 1 is fully grey.
    static let widgetGreyscaleKey = "widgetGreyscale"

    /// Whether hovering the notch drops down the player. On by default.
    static let notchPlayerKey = "notchPlayer"

    static var notchPlayerEnabled: Bool {
        store.object(forKey: notchPlayerKey) as? Bool ?? true
    }

    static var widgetLook: WidgetLook {
        WidgetLook(
            transparency: min(1, max(0, store.double(forKey: widgetTransparencyKey))),
            greyscale: min(1, max(0, store.double(forKey: widgetGreyscaleKey)))
        )
    }
}

/// How the widget draws its cover backdrop.
struct WidgetLook: Equatable {
    var transparency = 0.0
    var greyscale = 0.0

    var backgroundOpacity: Double { 1 - transparency }
    /// A trace of cover always stays, so the widget keeps its look.
    var coverOpacity: Double { 1 - 0.85 * transparency }
    var saturation: Double { 1 - greyscale }
    /// Eased off when transparent, so the bottom doesn't read as a black band; the text shadow keeps it legible.
    var scrimStrength: Double { 0.8 - 0.3 * transparency }
}
