import Foundation

enum AppGroup {
    /// Set at build time from the signing team; see Config/Base.xcconfig.
    static let id = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? ""
    static let widgetKind = "NowPlayingWidget"
    static let minimalWidgetKind = "NowPlayingMinimalWidget"
    /// A click on the widget goes to the host app, which brings Spotify forward.
    /// Not the login callback's scheme, so the two can't get mixed up.
    static let openSpotifyURL = URL(string: "spotify-widget://open-spotify")!

    static var containerURL: URL {
        let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
