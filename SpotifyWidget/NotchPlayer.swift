import AppKit
import SwiftUI

/// Drops a player out of the notch while the pointer rests on it.
///
/// Two panels sit over the notch. The player panel always has its full size, so it never resizes mid-animation;
/// collapsed, it shows only a black shape inside the notch and lets the mouse through. Behind it, a notch-sized
/// trigger panel catches the hover. Nothing runs while collapsed: the hover comes from tracking areas,
/// and the scrubber's timer only exists while the player is shown.
@MainActor
final class NotchController {
    static var hasNotch: Bool { notchScreen != nil }

    private let controller: PlayerController
    private let model = NotchModel()
    private var panel: NotchPanel?
    private var trigger: NotchPanel?
    private var playerHover: HoverView?
    private var notch: NSRect = .zero
    private var observers: [NSObjectProtocol] = []
    private var hoverTask: Task<Void, Never>?

    init(controller: PlayerController) {
        self.controller = controller
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: AppSettings.store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateIfToggled() }
        })
        update()
    }

    private func updateIfToggled() {
        if AppSettings.notchPlayerEnabled != (panel != nil) { update() }
    }

    /// Places the panels over the notch, or removes them when there's no notch or the player is turned off.
    private func update() {
        guard AppSettings.notchPlayerEnabled, let screen = Self.notchScreen else {
            hoverTask?.cancel()
            model.expanded = false
            panel?.orderOut(nil)
            trigger?.orderOut(nil)
            panel = nil
            trigger = nil
            return
        }
        let height = screen.safeAreaInsets.top
        let leftWidth = screen.auxiliaryTopLeftArea?.width ?? 0
        let rightWidth = screen.auxiliaryTopRightArea?.width ?? 0
        notch = NSRect(
            x: screen.frame.minX + leftWidth,
            y: screen.frame.maxY - height,
            width: screen.frame.width - leftWidth - rightWidth,
            height: height
        )
        model.notchSize = notch.size
        model.expandedSize = CGSize(width: notch.width + 220, height: notch.height + 138)

        let trigger = trigger ?? makeTrigger()
        self.trigger = trigger
        trigger.setFrame(notch, display: false)
        trigger.orderFrontRegardless()

        let panel = panel ?? makePanel()
        self.panel = panel
        panel.setFrame(expandedFrame, display: true)
        panel.ignoresMouseEvents = !model.expanded
        panel.orderFrontRegardless()
    }

    private var expandedFrame: NSRect {
        let size = model.expandedSize
        return NSRect(x: notch.midX - size.width / 2, y: notch.maxY - size.height, width: size.width, height: size.height)
    }

    private func makeTrigger() -> NotchPanel {
        let trigger = Self.basePanel()
        // Not fully clear, so the pointer isn't let through to what's behind; too faint to see
        // where it sticks out past the notch's rounded corners.
        trigger.isOpaque = false
        trigger.backgroundColor = NSColor(white: 0, alpha: 0.01)
        trigger.contentView = HoverView { [weak self] in self?.hoverChanged() }
        return trigger
    }

    private func makePanel() -> NotchPanel {
        let panel = Self.basePanel()
        panel.isOpaque = false
        panel.backgroundColor = .clear

        let root = NotchView(model: model).environmentObject(controller)
        let hosting = FirstMouseHostingView(rootView: root)
        // The panel's size is ours to set; the content only fills it.
        hosting.sizingOptions = []
        let container = HoverView { [weak self] in self?.hoverChanged() }
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container
        playerHover = container
        return panel
    }

    private static func basePanel() -> NotchPanel {
        let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Above the menu bar, which the notch is part of.
        panel.level = .init(NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        return panel
    }

    /// Called whenever the pointer enters or leaves either panel. Where the pointer ends up decides,
    /// after short delays so brushing past the notch doesn't open it and a slightly shaky pointer doesn't close it.
    private func hoverChanged() {
        hoverTask?.cancel()
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(self?.model.expanded == true ? 250 : 120))
            // Let a drag on the scrubber finish, even when it strays outside the panel.
            while !Task.isCancelled, NSEvent.pressedMouseButtons != 0 {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled, let self else { return }
            let pointer = NSEvent.mouseLocation
            if self.model.expanded {
                if !Self.rect(self.expandedFrame, contains: pointer) { self.collapse() }
            } else if Self.rect(self.notch, contains: pointer) {
                self.expand()
            }
        }
    }

    private func expand() {
        guard let panel, !model.expanded, controller.snapshot.hasTrack else { return }
        panel.ignoresMouseEvents = false
        // The pointer is already inside, so only its leaving needs reporting.
        playerHover?.track(assumingInside: true)
        withAnimation(.spring(duration: 0.35, bounce: 0.25)) { model.expanded = true }
    }

    private func collapse() {
        guard model.expanded else { return }
        panel?.ignoresMouseEvents = true
        withAnimation(.smooth(duration: 0.25)) { model.expanded = false }
    }

    /// Includes the top edge: a pointer pushed against the top of the screen sits right on it.
    private static func rect(_ rect: NSRect, contains point: NSPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }

    private static var notchScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    }
}

@MainActor
private final class NotchModel: ObservableObject {
    @Published var expanded = false
    @Published var notchSize = CGSize(width: 185, height: 32)
    @Published var expandedSize = CGSize(width: 405, height: 170)
}

/// Can become key without activating the app, so the scrubber can be dragged.
private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Buttons react to the first click, even though the panel is never key beforehand.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Reports the pointer entering and leaving, whether or not the app is active.
private final class HoverView: NSView {
    private let onHover: () -> Void
    private var area: NSTrackingArea?

    init(onHover: @escaping () -> Void) {
        self.onHover = onHover
        super.init(frame: .zero)
        track(assumingInside: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func track(assumingInside: Bool) {
        if let area { removeTrackingArea(area) }
        var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        if assumingInside { options.insert(.assumeInside) }
        let area = NSTrackingArea(rect: .zero, options: options, owner: self)
        addTrackingArea(area)
        self.area = area
    }

    override func mouseEntered(with event: NSEvent) { onHover() }
    override func mouseExited(with event: NSEvent) { onHover() }
}

private struct NotchView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        let expanded = model.expanded
        let size = expanded ? model.expandedSize : model.notchSize
        let shape = NotchShape(topRadius: expanded ? 12 : 4, bottomRadius: expanded ? 22 : 8)
        ZStack(alignment: .top) {
            shape.fill(.black)
            if expanded {
                NotchPlayer()
                    .frame(width: model.expandedSize.width - 64)
                    .padding(.top, model.notchSize.height + 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }
}

/// Cover and track on top, then the scrubber, then the controls.
private struct NotchPlayer: View {
    @EnvironmentObject private var controller: PlayerController

    var body: some View {
        let s = controller.snapshot
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    SpotifyApp.open()
                } label: {
                    Group {
                        if let image = controller.artworkImage {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Rectangle().fill(.quaternary)
                        }
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Open Spotify")

                VStack(alignment: .leading, spacing: 2) {
                    Text(s.title)
                        .font(.headline)
                    Text(s.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .truncationMode(.tail)
                .help("\(s.title) — \(s.artist)")

                Spacer(minLength: 0)

                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.variableColor.iterative, isActive: s.isPlaying)
            }
            Scrubber(snapshot: s, inline: true) { position in
                controller.seek(to: position)
            }
            TransportControls(snapshot: s)
        }
    }
}

/// The notch's outline: square top corners that curve out into the menu bar, and rounded bottom corners.
private struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { (topRadius, bottomRadius) = (newValue.first, newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        let t = topRadius, b = bottomRadius
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t), control: CGPoint(x: rect.minX + t, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        path.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY), control: CGPoint(x: rect.minX + t, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b), control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - t, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
