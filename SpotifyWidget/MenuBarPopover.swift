import ServiceManagement
import SwiftUI
import WidgetKit

/// The window that drops down from the menu bar item: cover, track, scrubber, controls, and volume.
struct MenuBarPopover: View {
    @EnvironmentObject private var controller: PlayerController

    static let width: CGFloat = 280

    var body: some View {
        let s = controller.snapshot
        VStack(spacing: 12) {
            if s.hasTrack {
                Artwork(image: controller.artworkImage)
                TrackInfo(snapshot: s)
                Scrubber(snapshot: s) { position in
                    Task { await controller.seek(to: position) }
                }
                TransportControls(snapshot: s)
            } else {
                EmptyState(status: s.status)
            }
            if let error = controller.account.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            BottomBar(snapshot: s)
        }
        .padding(14)
        .frame(width: Self.width)
    }
}

private struct Artwork: View {
    let image: NSImage?

    var body: some View {
        Button {
            SpotifyApp.open()
        } label: {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 48))
                                .foregroundStyle(.tertiary)
                        }
                }
            }
            .frame(width: MenuBarPopover.width - 28, height: MenuBarPopover.width - 28)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .help("Open Spotify")
    }
}

private struct TrackInfo: View {
    let snapshot: NowPlaying

    var body: some View {
        VStack(spacing: 2) {
            Text(snapshot.title)
                .font(.headline)
            Text(snapshot.artist)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity)
        .help("\(snapshot.title) — \(snapshot.artist)")
    }
}

/// Progress bar with elapsed and remaining time. Drag or click to seek.
private struct Scrubber: View {
    let snapshot: NowPlaying
    let seek: (TimeInterval) -> Void
    /// Where the user is dragging to, as a fraction; nil when not dragging.
    @State private var dragging: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let s = snapshot
            let duration = max(s.duration, 1)
            let position = dragging.map { $0 * duration } ?? s.position(at: context.date)
            VStack(spacing: 4) {
                ThinSlider(value: position / duration) { fraction in
                    dragging = fraction
                } onCommit: { fraction in
                    dragging = nil
                    seek(fraction * duration)
                }
                HStack {
                    Text(Self.format(position))
                    Spacer()
                    Text("-" + Self.format(max(0, s.duration - position)))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct TransportControls: View {
    @EnvironmentObject private var controller: PlayerController
    let snapshot: NowPlaying

    var body: some View {
        HStack {
            // Keeps the row symmetric when the like button is hidden.
            Group {
                if let liked = snapshot.liked {
                    IconButton(help: liked ? "Remove from Liked Songs" : "Save to Liked Songs", tint: liked ? .green : nil) {
                        perform(.toggleLike)
                    } label: {
                        LikeIconShape(liked: liked)
                            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                            .frame(width: 17, height: 17)
                    }
                } else {
                    Color.clear.frame(width: 28, height: 28)
                }
            }
            Spacer()
            IconButton(help: "Previous Track") { perform(.previous) } label: {
                Image(systemName: "backward.fill").font(.system(size: 17))
            }
            Spacer()
            IconButton(help: snapshot.isPlaying ? "Pause" : "Play") { perform(.playPause) } label: {
                Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26))
                    .frame(width: 32)
            }
            Spacer()
            IconButton(help: "Next Track") { perform(.next) } label: {
                Image(systemName: "forward.fill").font(.system(size: 17))
            }
            Spacer()
            IconButton(help: snapshot.shuffle ? "Turn Shuffle Off" : "Turn Shuffle On", tint: snapshot.shuffle ? .green : nil) {
                Task { await controller.setShuffle(!snapshot.shuffle) }
            } label: {
                Image(systemName: "shuffle").font(.system(size: 15, weight: .semibold))
            }
        }
        .padding(.horizontal, 4)
    }

    private func perform(_ command: PlayerCommand) {
        Task { await controller.perform(command) }
    }
}

private struct BottomBar: View {
    @EnvironmentObject private var controller: PlayerController
    let snapshot: NowPlaying
    @State private var volume: Double?
    /// The last volume sent while dragging, so each step reaches Spotify once.
    @State private var sentVolume: Int?

    var body: some View {
        HStack(spacing: 8) {
            if snapshot.status != .notRunning, snapshot.status != .noPermission {
                let current = volume ?? Double(snapshot.volume ?? 50) / 100
                Image(systemName: "speaker.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ThinSlider(value: current) { fraction in
                    volume = fraction
                    send(fraction)
                } onCommit: { fraction in
                    send(fraction)
                    volume = nil
                    sentVolume = nil
                }
                Image(systemName: "speaker.wave.3.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Spacer()
            }
            SettingsMenu(account: controller.account)
        }
    }

    private func send(_ fraction: Double) {
        let percent = Int((fraction * 100).rounded())
        guard percent != sentVolume else { return }
        sentVolume = percent
        Task { await controller.setVolume(percent) }
    }
}

private struct SettingsMenu: View {
    @EnvironmentObject private var controller: PlayerController
    @ObservedObject var account: SpotifyAccount
    @AppStorage(MenuBarLabel.showTitleKey) private var showTitle = true
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Menu {
            if account.isConnected {
                Button("Disconnect Spotify Account") { account.disconnect() }
            } else {
                Button("Connect Spotify Account…") { account.connect() }
            }
            Divider()
            Toggle("Show Song in Menu Bar", isOn: $showTitle)
            Toggle("Open at Login", isOn: $openAtLogin)
                .onChange(of: openAtLogin) { _, enabled in
                    openAtLogin = controller.setOpenAtLogin(enabled)
                }
            Button("Reload Widget") { WidgetCenter.shared.reloadAllTimelines() }
            Divider()
            Button("Quit Spotify Widget") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Settings")
    }
}

private struct EmptyState: View {
    let status: PlayerStatus

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: status == .noPermission ? "lock.fill" : "music.note")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.headline)
            switch status {
            case .noPermission:
                Button("Grant Automation Access…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                }
            case .notRunning:
                Button("Open Spotify") { SpotifyApp.open() }
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var message: String {
        switch status {
        case .noPermission: "Needs Automation access to Spotify"
        case .notRunning: "Spotify isn't running"
        default: "Nothing playing"
        }
    }
}

/// A borderless symbol button that brightens on hover.
private struct IconButton<Label: View>: View {
    let help: String
    var tint: Color?
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint ?? (hovering ? .primary : .primary.opacity(0.8)))
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// A slim track that thickens on hover, used for both seeking and volume.
private struct ThinSlider: View {
    let value: Double
    let onChange: (Double) -> Void
    let onCommit: (Double) -> Void
    @State private var hovering = false

    var body: some View {
        GeometryReader { geo in
            let fraction = min(1, max(0, value))
            let height: CGFloat = hovering ? 6 : 4
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.15))
                Capsule().fill(.primary.opacity(hovering ? 0.9 : 0.7))
                    .frame(width: geo.size.width * fraction)
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { onChange(Self.fraction($0.location.x, in: geo.size.width)) }
                    .onEnded { onCommit(Self.fraction($0.location.x, in: geo.size.width)) }
            )
            .animation(.easeOut(duration: 0.12), value: hovering)
        }
        .frame(height: 14)
        .onHover { hovering = $0 }
    }

    private static func fraction(_ x: CGFloat, in width: CGFloat) -> Double {
        width > 0 ? min(1, max(0, Double(x / width))) : 0
    }
}

/// The menu bar item itself: a note, plus the current song when enabled.
struct MenuBarLabel: View {
    static let showTitleKey = "showTitleInMenuBar"
    @ObservedObject var controller: PlayerController
    @AppStorage(showTitleKey) private var showTitle = true

    var body: some View {
        let s = controller.snapshot
        Image(systemName: s.isPlaying ? "music.note" : "music.note.list")
        if showTitle, s.hasTrack {
            Text(Self.shortened(s.title))
        }
    }

    /// The menu bar has no room for long titles, and labels there can't truncate on their own.
    private static func shortened(_ title: String, limit: Int = 24) -> String {
        title.count > limit ? title.prefix(limit - 1).trimmingCharacters(in: .whitespaces) + "…" : title
    }
}

enum SpotifyApp {
    static func open() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: SpotifyProvider.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
}
