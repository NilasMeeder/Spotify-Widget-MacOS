import AppKit
import ImageIO

/// Downloads album art, shrinks it to widget-safe size, and keeps only the current track's file.
actor ArtworkCache {
    private var current: (trackID: String, file: String)?
    /// The download for the most recently requested track. Callers for that track share it; a request for another track
    /// supersedes it, so a slow download for a track skipped past can't overwrite or delete the newer one.
    private var inFlight: (trackID: String, id: UUID, task: Task<String?, Never>)?

    func localFile(trackID: String, remoteURL: String) async -> String? {
        if let current, current.trackID == trackID { return current.file }
        if let inFlight, inFlight.trackID == trackID { return await inFlight.task.value }

        let id = UUID()
        let task = Task.detached { await Self.download(trackID: trackID, remoteURL: remoteURL) }
        inFlight = (trackID, id, task)
        let name = await task.value

        guard inFlight?.id == id else {
            if let name, name != current?.file {
                try? FileManager.default.removeItem(at: SharedStore.fileURL(name))
            }
            return nil
        }
        inFlight = nil
        guard let name else { return nil }

        if let old = current, old.file != name {
            try? FileManager.default.removeItem(at: SharedStore.fileURL(old.file))
        }
        current = (trackID, name)
        return name
    }

    /// Returns the written file's name.
    private static func download(trackID: String, remoteURL: String) async -> String? {
        guard let url = URL(string: remoteURL),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let jpeg = downscaledJPEG(data, maxPixels: 640)
        else { return nil }

        let name = "artwork-\(trackID.replacingOccurrences(of: ":", with: "_")).jpg"
        do {
            try jpeg.write(to: SharedStore.fileURL(name), options: .atomic)
        } catch {
            return nil
        }
        return name
    }

    private static func downscaledJPEG(_ data: Data, maxPixels: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}
