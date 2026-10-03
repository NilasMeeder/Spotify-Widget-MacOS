import CoreImage.CIFilterBuiltins
import SwiftUI
import WidgetKit

@main
struct SpotifyWidgetBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
        NowPlayingMinimalWidget()
    }
}

struct NowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppGroup.widgetKind, provider: Provider()) { entry in
            NowPlayingView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("What's playing in Spotify, with playback controls.")
        .supportedFamilies([.systemSmall, .systemMedium])
        // The cover is drawn edge to edge as content; views add the margins back themselves.
        .contentMarginsDisabled()
    }
}

/// Now the same as the medium Now Playing widget. Kept registered so widgets already placed from it keep working.
struct NowPlayingMinimalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AppGroup.minimalWidgetKind, provider: Provider()) { entry in
            NowPlayingView(entry: entry)
        }
        .configurationDisplayName("Now Playing (Minimal)")
        .description("What's playing in Spotify, with playback controls.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let snapshot: NowPlaying
    /// Cover art with the scrim baked in, sized to the widget. Nil when there's no artwork.
    let backdrop: NSImage?
    /// From the app's settings.
    var look = WidgetLook()
    /// How far through a scroll loop the title is, when it's too long to fit.
    var marquee: Double = 0
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: .now, snapshot: .placeholder, backdrop: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        let entry = currentEntry(size: context.displaySize)
        completion(context.isPreview && !entry.snapshot.hasTrack ? placeholder(in: context) : entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        let entry = currentEntry(size: context.displaySize)
        let s = entry.snapshot
        let live = s.isPlaying && s.duration > 0 && s.endDate > .now
        var entries = [entry]

        if live {
            // A rough, generous bound on the room beside the controls: margins plus the play button, or all three buttons.
            let reserved: CGFloat = context.family == .systemSmall ? 72 : 140
            entries += marqueeEntries(after: entry, room: context.displaySize.width - reserved)
        }

        // If the host app goes quiet, don't leave a progress bar running past the end of the track.
        if live {
            var ended = s
            ended.status = .paused
            ended.position = s.duration
            ended.capturedAt = s.endDate
            entries.append(NowPlayingEntry(date: s.endDate, snapshot: ended, backdrop: entry.backdrop, look: entry.look))
        }

        // The host app reloads the timeline whenever playback changes.
        completion(Timeline(entries: entries, policy: .never))
    }

    /// Scrolls a title too long for the widget, one step per entry, resting at the start between loops.
    /// `room` only decides whether to schedule scrolling; the view decides whether the title really overflows.
    private func marqueeEntries(after entry: NowPlayingEntry, room: CGFloat) -> [NowPlayingEntry] {
        let s = entry.snapshot
        let font = NSFont.systemFont(ofSize: SmallView.titleSize, weight: .medium)
        let textWidth = (s.title as NSString).size(withAttributes: [.font: font]).width
        guard textWidth > room else { return [] }

        let steps = Marquee.steps(forWidth: textWidth)
        // Stop scheduling eventually on very long tracks; the next playback change reloads the timeline anyway.
        let end = min(s.endDate, entry.date.addingTimeInterval(15 * 60))
        var entries: [NowPlayingEntry] = []
        var loopStart = entry.date.addingTimeInterval(Marquee.pause)
        while loopStart < end {
            for step in 1...steps {
                let date = loopStart.addingTimeInterval(Double(step - 1) * Marquee.stepDuration)
                entries.append(NowPlayingEntry(date: date, snapshot: s, backdrop: entry.backdrop, look: entry.look, marquee: Double(step) / Double(steps)))
            }
            let restDate = loopStart.addingTimeInterval(Double(steps) * Marquee.stepDuration)
            entries.append(NowPlayingEntry(date: restDate, snapshot: s, backdrop: entry.backdrop, look: entry.look))
            loopStart = restDate.addingTimeInterval(Marquee.pause)
        }
        return entries.filter { $0.date < s.endDate }
    }

    private func currentEntry(size: CGSize) -> NowPlayingEntry {
        let snapshot = SharedStore.load()
        let artwork = snapshot.artworkFile.flatMap { NSImage(contentsOf: SharedStore.fileURL($0)) }
        let look = AppSettings.widgetLook
        let backdrop = artwork.flatMap { Backdrop.render($0, size: size, look: look) }
        return NowPlayingEntry(date: .now, snapshot: snapshot, backdrop: backdrop, look: look)
    }
}

/// In the glass style (another app focused) macOS drops the container background and flattens
/// non-image content to a tint, so a SwiftUI gradient over the cover would turn into a white wash.
/// Baking the scrim into a single image keeps the full-bleed look identical in both states.
enum Backdrop {
    static func render(_ artwork: NSImage, size: CGSize, look: WidgetLook = .init(), scale: CGFloat = 2) -> NSImage? {
        guard size.width > 0, size.height > 0,
              let original = artwork.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let cover = filtered(original, look: look),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil,
                  width: Int(size.width * scale),
                  height: Int(size.height * scale),
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        let w = CGFloat(ctx.width), h = CGFloat(ctx.height)
        ctx.setFillColor(CGColor(gray: 0.12, alpha: look.backgroundOpacity))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setAlpha(look.coverOpacity)

        // Aspect-fill, centered.
        let fill = max(w / CGFloat(cover.width), h / CGFloat(cover.height))
        let dw = CGFloat(cover.width) * fill, dh = CGFloat(cover.height) * fill
        ctx.interpolationQuality = .high
        ctx.draw(cover, in: CGRect(x: (w - dw) / 2, y: (h - dh) / 2, width: dw, height: dh))

        // Scrim darkens the bottom where the title and controls sit, at full strength so text stays readable.
        // CG's origin is bottom-left.
        ctx.setAlpha(1)
        let black = { (a: CGFloat) in CGColor(gray: 0, alpha: a) }
        if let scrim = CGGradient(
            colorsSpace: space,
            colors: [black(look.scrimStrength), black(0.15), black(0.05)] as CFArray,
            locations: [0, 0.65, 1]
        ) {
            ctx.drawLinearGradient(scrim, start: .zero, end: CGPoint(x: 0, y: h), options: [])
        }

        return ctx.makeImage().map { NSImage(cgImage: $0, size: size) }
    }

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// Applies greyscale. Returns the image untouched when it's off, skipping Core Image.
    private static func filtered(_ image: CGImage, look: WidgetLook) -> CGImage? {
        guard look.greyscale > 0 else { return image }
        let grey = CIFilter.colorControls()
        grey.inputImage = CIImage(cgImage: image)
        grey.saturation = Float(look.saturation)
        guard let output = grey.outputImage else { return nil }
        return ciContext.createCGImage(output, from: output.extent)
    }
}
