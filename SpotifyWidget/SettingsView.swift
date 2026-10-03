import ServiceManagement
import SwiftUI
import WidgetKit

/// The settings window. Managed by hand because a menu-bar-only app can't reliably bring a SwiftUI `Settings` scene forward.
@MainActor
final class SettingsWindow: ObservableObject {
    private var window: NSWindow?
    private let controller: PlayerController

    init(controller: PlayerController) {
        self.controller = controller
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView().environmentObject(controller))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Spotify Widget Settings"
            // The glass runs under the title bar too, and the window itself stays clear so the glass can show what's behind it.
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var controller: PlayerController
    @AppStorage(AppSettings.menuBarShowsCoverKey, store: AppSettings.store) private var showsCover = true
    @AppStorage(AppSettings.menuBarShowsTitleKey, store: AppSettings.store) private var showsTitle = true
    @AppStorage(AppSettings.widgetTransparencyKey, store: AppSettings.store) private var transparency = 0.0
    @AppStorage(AppSettings.widgetGreyscaleKey, store: AppSettings.store) private var greyscale = 0.0
    @AppStorage(AppSettings.notchPlayerKey, store: AppSettings.store) private var notchPlayer = true
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Menu Bar") {
                Toggle("Show album cover", isOn: $showsCover)
                Toggle("Show song title", isOn: $showsTitle)
            }

            if NotchController.hasNotch {
                Section("Notch") {
                    Toggle("Player in the notch", isOn: $notchPlayer)
                    Text("Hover the notch for the controls. The menu bar item then only holds the menu.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Transparency") {
                    // Only reload once the drag ends: every widget reload re-renders the cover.
                    Slider(value: $transparency, in: 0...1) { editing in
                        if !editing { WidgetCenter.shared.reloadAllTimelines() }
                    }
                }
                LabeledContent("Greyscale") {
                    Slider(value: $greyscale, in: 0...1) { editing in
                        if !editing { WidgetCenter.shared.reloadAllTimelines() }
                    }
                }
                WidgetPreview(
                    cover: controller.artworkImage,
                    look: WidgetLook(transparency: transparency, greyscale: greyscale)
                )
            } header: {
                Text("Widget")
            }

            Section("General") {
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, enabled in
                        openAtLogin = controller.setOpenAtLogin(enabled)
                    }
                AccountRow(account: controller.account)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .background { WindowGlass() }
    }
}

/// Liquid Glass on macOS 26 and later, the frosted window material before that.
private struct WindowGlass: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: .rect)
                .ignoresSafeArea()
        } else {
            BehindWindowBlur()
                .ignoresSafeArea()
        }
    }
}

private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct AccountRow: View {
    @ObservedObject var account: SpotifyAccount

    var body: some View {
        LabeledContent("Spotify account") {
            if account.isConnected {
                Button("Disconnect") { account.disconnect() }
            } else {
                Button("Connect…") { account.connect() }
            }
        }
        if let error = account.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// A rough stand-in for the widget over a busy background, so the slider has visible effect without waiting on WidgetKit.
private struct WidgetPreview: View {
    let cover: NSImage?
    let look: WidgetLook

    var body: some View {
        ZStack {
            LinearGradient(colors: [.orange, .pink, .purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.12).opacity(look.backgroundOpacity))
                .overlay {
                    if let cover {
                        Image(nsImage: cover)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .saturation(look.saturation)
                            .opacity(look.coverOpacity)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(width: 150, height: 150)
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
