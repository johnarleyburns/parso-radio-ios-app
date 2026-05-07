import SwiftUI

// FM-style ordering: popular genres in the middle, niche at the edges.
// Index 0 is leftmost on the dial; the notch/pointer indicates the current channel.
private let dialOrder: [String] = [
    // ── Left edge (niche) ──────────────────────────────────────────────
    "greek-philosophy",
    "chinese-philosophy",
    "history-talks",
    "chinese-history",
    "greek-history",
    "classic-lit",
    "french-lit",
    "spanish-lit",
    "french-kids",
    "spanish-kids",
    "childrens-books",
    // ── Left-center ───────────────────────────────────────────────────
    "mystery",
    "science-fiction",
    "experimental",
    "ambient",
    "study-focus",
    "soft-cafe",
    "bach-vivaldi-strings",
    "chopin-rachmaninoff-piano",
    "classical",
    // ── Center (popular) ─────────────────────────────────────────────
    "jazz-bar",
    "blues",
    "rock",        // index 22 — start here
    "pop",
    "hip-hop",
    // ── Right-center ─────────────────────────────────────────────────
    "electronic",
    "world-music",
    "folk",
    "country",
    "instrumental",
    // ── Right edge (niche) ────────────────────────────────────────────
    "spanish-guitar",
]

private var dialChannels: [Channel] {
    dialOrder.compactMap { id in Channel.defaults.first { $0.id == id } }
}

struct DialHomeView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @State private var selectedIndex: Int = 22    // rock — center of the dial
    @State private var showGuide = false
    @State private var showPlayer = false

    private let channels: [Channel] = dialChannels

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    RadioDial(
                        channelCount: channels.count,
                        selectedIndex: $selectedIndex
                    )
                    .frame(height: 200)
                    .sensoryFeedback(.selection, trigger: selectedIndex)

                    channelPanel
                        .padding(.horizontal, 20)
                        .padding(.top, 28)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))

                if playerVM.currentTrack != nil {
                    miniPlayer
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Parso Radio")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showGuide = true
                    } label: {
                        Label("Radio Guide", systemImage: "list.bullet")
                    }
                }
            }
            .sheet(isPresented: $showGuide) {
                ChannelListView()
                    .environmentObject(playerVM)
            }
            .navigationDestination(isPresented: $showPlayer) {
                if selectedIndex < channels.count {
                    PlayerView(channel: channels[selectedIndex])
                }
            }
        }
        .animation(.spring(duration: 0.3), value: playerVM.currentTrack != nil)
    }

    // MARK: - Channel info panel

    private var channelPanel: some View {
        let channel = selectedIndex < channels.count ? channels[selectedIndex] : nil
        return Group {
            if let ch = channel {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(categoryGradient(for: ch.category))
                            .frame(width: 56, height: 56)
                            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                        Image(systemName: ch.icon)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(ch.name)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Text(ch.category)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        showPlayer = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.circle.fill")
                            Text("Tune In")
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(categoryGradient(for: ch.category), in: Capsule())
                    }
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .id(ch.id)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
        }
        .animation(.spring(duration: 0.28), value: selectedIndex)
    }

    // MARK: - Mini player

    private var miniPlayer: some View {
        Button {
            if let ch = playerVM.currentChannel,
               let idx = channels.firstIndex(where: { $0.id == ch.id }) {
                selectedIndex = idx
                showPlayer = true
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(categoryGradient(for: playerVM.currentChannel?.category ?? ""))
                        .frame(width: 44, height: 44)
                    Image(systemName: playerVM.currentChannel?.icon ?? "music.note")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(playerVM.currentTrack?.title ?? "")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(playerVM.currentTrack?.artist ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if playerVM.isLoading {
                    ProgressView()
                        .frame(width: 44, height: 44)
                } else {
                    Button {
                        playerVM.togglePlayPause()
                    } label: {
                        Image(systemName: playerVM.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Radio Dial

struct RadioDial: View {
    let channelCount: Int
    @Binding var selectedIndex: Int

    private let tickSpacing: CGFloat = 20     // pixels between tick marks
    private let visibleHalf: CGFloat = 12     // ticks visible on each side of center

    @State private var dragOffset: CGFloat = 0
    @State private var baseOffset: CGFloat = 0

    private func indexFor(offset: CGFloat) -> Int {
        let raw = Int((offset / tickSpacing).rounded())
        return max(0, min(channelCount - 1, raw))
    }

    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            let midY = geo.size.height * 0.5

            ZStack {
                // Tick marks drawn as a Canvas for performance
                Canvas { context, size in
                    let currentOffset = dragOffset / tickSpacing

                    for i in 0..<channelCount {
                        let tickPos = CGFloat(i) - currentOffset
                        guard abs(tickPos) <= visibleHalf + 1 else { continue }

                        let x = cx + tickPos * tickSpacing
                        let alpha = max(0.0, 1.0 - abs(tickPos) / visibleHalf)
                        let isMajor = (i == selectedIndex)

                        // Taller tick at center, shorter toward edges
                        let maxH: CGFloat = isMajor ? 36 : 16
                        let minH: CGFloat = isMajor ? 36 : 6
                        let tickH = max(minH, maxH - abs(tickPos) * 1.5)

                        let color: Color = isMajor
                            ? Color.accentColor.opacity(Double(alpha))
                            : Color.primary.opacity(Double(alpha) * 0.5)

                        let rect = CGRect(x: x - 1.5, y: midY - tickH / 2, width: 3, height: tickH)
                        context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(color))
                    }

                    // Baseline
                    let lineY = midY + 22
                    context.fill(
                        Path(CGRect(x: 0, y: lineY, width: size.width, height: 1)),
                        with: .color(.primary.opacity(0.08))
                    )
                }

                // Fixed center pointer
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2, height: 44)
                        .cornerRadius(1)
                    DialPointerTriangle()
                        .fill(Color.accentColor)
                        .frame(width: 10, height: 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .allowsHitTesting(false)
            }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        // Drag right → content slides right → lower-index channel appears
                        let newOffset = baseOffset - value.translation.width
                        let clamped = max(0, min(CGFloat(channelCount - 1) * tickSpacing, newOffset))
                        dragOffset = clamped
                        let newIdx = indexFor(offset: clamped)
                        if newIdx != selectedIndex {
                            selectedIndex = newIdx
                        }
                    }
                    .onEnded { _ in
                        let snapped = CGFloat(selectedIndex) * tickSpacing
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            dragOffset = snapped
                        }
                        baseOffset = snapped
                    }
            )
        }
        .onAppear {
            let snap = CGFloat(selectedIndex) * tickSpacing
            dragOffset = snap
            baseOffset = snap
        }
    }
}

private struct DialPointerTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.closeSubpath()
        }
    }
}

#Preview {
    DialHomeView()
        .environmentObject(PlayerViewModel(
            db: try! DatabaseService(path: ":memory:"),
            archiveService: InternetArchiveService(),
            fmaService: FMAService(),
            queueManager: QueueManager(db: try! DatabaseService(path: ":memory:")),
            audioPlayer: AudioPlayerService(),
            downloadManager: DownloadManager(db: try! DatabaseService(path: ":memory:"))
        ))
}
