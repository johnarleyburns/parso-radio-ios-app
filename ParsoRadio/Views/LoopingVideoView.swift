import SwiftUI
import AVFoundation

// A muted, aspect-fill, infinitely-looping local video used as the screen
// backdrop for ambient-loop channels. Muted so it never touches the audio
// session — the ambient WAV keeps playing through AudioPlayerService.
struct LoopingVideoView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        LoopingPlayerUIView(url: url)
    }

    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {
        uiView.update(url: url)
    }

    static func dismantleUIView(_ uiView: LoopingPlayerUIView, coordinator: ()) {
        uiView.teardown()
    }
}

final class LoopingPlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var currentURL: URL?

    init(url: URL) {
        super.init(frame: .zero)
        setup(url: url)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func update(url: URL) {
        guard url != currentURL else { return }
        teardown()
        setup(url: url)
    }

    private func setup(url: URL) {
        currentURL = url
        let item = AVPlayerItem(url: url)
        let qp = AVQueuePlayer()
        qp.isMuted = true
        qp.actionAtItemEnd = .advance
        looper = AVPlayerLooper(player: qp, templateItem: item)
        playerLayer.player = qp
        playerLayer.videoGravity = .resizeAspectFill
        queuePlayer = qp
        qp.play()
    }

    func teardown() {
        queuePlayer?.pause()
        looper?.disableLooping()
        looper = nil
        playerLayer.player = nil
        queuePlayer = nil
        currentURL = nil
    }
}
