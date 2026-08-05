import AVFoundation

/// Plays a synthesized audio file and cleans it up afterwards.
///
/// `zdx speak` only writes a file — it has no playback of its own — so the audio
/// lands in a temp file that belongs to whoever plays it.
@MainActor
final class SpeechPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var file: URL?

    /// Fired when playback ends on its own, so the UI can drop its speaking state.
    var onFinish: (() -> Void)?

    var isPlaying: Bool { player?.isPlaying ?? false }

    func play(_ url: URL) throws {
        stop()

        let player = try AVAudioPlayer(contentsOf: url)
        player.delegate = self
        self.player = player
        file = url
        player.play()
    }

    func stop() {
        player?.stop()
        player = nil
        discardFile()
    }

    private func discardFile() {
        guard let file else { return }
        try? FileManager.default.removeItem(at: file)
        self.file = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.player = nil
            discardFile()
            onFinish?()
        }
    }
}
