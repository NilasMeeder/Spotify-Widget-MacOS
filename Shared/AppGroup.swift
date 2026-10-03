import Foundation

enum AppGroup {
    static let id = "YB8CN9L39G.com.kiran.spotifywidget"
    static let widgetKind = "NowPlayingWidget"
    static let minimalWidgetKind = "NowPlayingMinimalWidget"

    static var containerURL: URL {
        let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
