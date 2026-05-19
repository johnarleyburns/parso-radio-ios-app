import SwiftUI
import AVFoundation

// A muted, aspect-fill, infinitely-looping local video used as the screen
// backdrop for ambient-loop channels. Muted so it never touches the audio
// session — the ambient WAV keeps playing through AudioPlayerService.
//
// `horizontalAnchor` controls which part of the over-wide video is kept when
// it's cropped to fill: 0 = left edge, 0.5 = centre (default), 1 = right edge.
struct LoopingVideoView: UIViewRepresentable {
    let url: URL
    var horizontalAnchor: CGFloat = 0.5
    var isPlaying: Bool = true

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        LoopingPlayerUIView(url: url, horizontalAnchor: horizontalAnchor)
    }

    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {
        uiView.horizontalAnchor = horizontalAnchor
        uiView.update(url: url)
        uiView.setPlaying(isPlaying)
    }

    static func dismantleUIView(_ uiView: LoopingPlayerUIView, coordinator: ()) {
        uiView.teardown()
    }
}

final class LoopingPlayerUIView: UIView {
    override class var layerClass: AnyClass { CALayer.self }

    private let playerLayer = AVPlayerLayer()
    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var currentURL: URL?
    private var videoAspect: CGFloat?     // width / height, once known

    var horizontalAnchor: CGFloat = 0.5 {
        didSet { if horizontalAnchor != oldValue { setNeedsLayout() } }
    }

    init(url: URL, horizontalAnchor: CGFloat) {
        self.horizontalAnchor = horizontalAnchor
        super.init(frame: .zero)
        clipsToBounds = true
        layer.addSublayer(playerLayer)
        playerLayer.videoGravity = .resizeAspectFill
        setup(url: url)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        clipsToBounds = true
        layer.addSublayer(playerLayer)
        playerLayer.videoGravity = .resizeAspectFill
    }

    func update(url: URL) {
        guard url != currentURL else { return }
        teardown()
        setup(url: url)
    }

    // Mirror audio play/pause so the backdrop freezes when paused.
    func setPlaying(_ playing: Bool) {
        guard let qp = queuePlayer else { return }
        if playing {
            if qp.timeControlStatus != .playing { qp.play() }
        } else {
            qp.pause()
        }
    }

    private func setup(url: URL) {
        currentURL = url
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let qp = AVQueuePlayer()
        qp.isMuted = true
        qp.actionAtItemEnd = .advance
        looper = AVPlayerLooper(player: qp, templateItem: item)
        playerLayer.player = qp
        queuePlayer = qp
        qp.play()

        // Learn the natural size so the crop can be anchored precisely.
        Task { [weak self] in
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let size = try? await track.load(.naturalSize),
                  let tf = try? await track.load(.preferredTransform)
            else { return }
            let r = size.applying(tf)
            let w = abs(r.width), h = abs(r.height)
            guard w > 0, h > 0 else { return }
            await MainActor.run {
                self?.videoAspect = w / h
                self?.setNeedsLayout()
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds
        guard b.width > 0, b.height > 0 else { return }
        guard let aspect = videoAspect else {
            // Aspect unknown yet → plain centred fill.
            playerLayer.frame = b
            return
        }
        // Build an aspect-correct rect that covers the view, then slide it so
        // the chosen edge is the part that remains visible (host clips).
        let viewAspect = b.width / b.height
        var f = b
        if aspect > viewAspect {
            // Video wider than the view → overflow horizontally; anchor X.
            let w = b.height * aspect
            f = CGRect(x: (b.width - w) * horizontalAnchor, y: 0,
                       width: w, height: b.height)
        } else {
            // Video taller → overflow vertically; keep vertically centred.
            let h = b.width / aspect
            f = CGRect(x: 0, y: (b.height - h) * 0.5,
                       width: b.width, height: h)
        }
        playerLayer.frame = f
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
