import Foundation

/// A local music app the widget can display and control. Spotify today; Apple Music can be added as another conformer.
protocol MusicProvider {
    func snapshot() async -> NowPlaying
    func perform(_ command: PlayerCommand) async
    func seek(to position: TimeInterval) async
    func setShuffle(_ enabled: Bool) async
    /// 0–100.
    func setVolume(_ volume: Int) async
}
