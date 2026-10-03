import SwiftUI

@main
struct SpotifyWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage(AppSettings.notchPlayerKey, store: AppSettings.store) private var notchPlayer = true

    var body: some Scene {
        // The controls live either in the notch or in the menu bar, never both.
        // With the notch player on, the menu bar item is a plain menu.
        MenuBarExtra(isInserted: inserted(!usesNotch)) {
            MenuBarPopover()
                .environmentObject(delegate.controller)
                .environmentObject(delegate.settings)
        } label: {
            MenuBarLabel(controller: delegate.controller)
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra(isInserted: inserted(usesNotch)) {
            AppMenuItems(settings: delegate.settings)
        } label: {
            MenuBarLabel(controller: delegate.controller)
        }
        .menuBarExtraStyle(.menu)
    }

    private var usesNotch: Bool { notchPlayer && NotchController.hasNotch }

    private func inserted(_ value: Bool) -> Binding<Bool> {
        Binding(get: { value }, set: { _ in })
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = PlayerController()
    lazy var settings = SettingsWindow(controller: controller)
    private var notch: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        notch = NotchController(controller: controller)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.contains(where: { $0.scheme == AppGroup.openSpotifyURL.scheme }) {
            SpotifyApp.open()
        }
    }
}
