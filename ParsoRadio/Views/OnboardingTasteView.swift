import SwiftUI

struct OnboardingChip: Identifiable {
    let id: String
    let label: String
    let icon: String
    let collectionIDs: [String]
    let creatorSeed: String?
    let subjectSeed: String?

    init(id: String, label: String, icon: String, collectionIDs: [String] = [],
         creatorSeed: String? = nil, subjectSeed: String? = nil) {
        self.id = id
        self.label = label
        self.icon = icon
        self.collectionIDs = collectionIDs
        self.creatorSeed = creatorSeed
        self.subjectSeed = subjectSeed
    }

    static let all: [OnboardingChip] = [
        OnboardingChip(id: "piano", label: "Piano", icon: "pianokeys",
                       collectionIDs: ["tedjonespiano"], subjectSeed: "piano"),
        OnboardingChip(id: "bach", label: "Bach & Baroque", icon: "music.quarternote.3",
                       collectionIDs: [],
                       creatorSeed: "(Bach OR Handel OR Vivaldi)",
                       subjectSeed: "classical"),
        OnboardingChip(id: "jazz", label: "Jazz", icon: "music.mic",
                       collectionIDs: ["sfjazz", "cujazz", "davidwnivenjazz"]),
        OnboardingChip(id: "spanish-guitar", label: "Spanish Guitar", icon: "guitars",
                       collectionIDs: ["aadamjacobs"], subjectSeed: "guitar"),
        OnboardingChip(id: "classical", label: "Classical", icon: "music.note",
                       collectionIDs: ["russian_classical_collection"],
                       subjectSeed: "classical"),
        OnboardingChip(id: "world", label: "World & Folk", icon: "globe",
                       collectionIDs: ["musica-campesina", "music-of-the-world-istanbul",
                                       "voa-music-time-in-africa"]),
        OnboardingChip(id: "reggae", label: "Reggae & Dub", icon: "waveform",
                       collectionIDs: ["crucialriddm_music"]),
        OnboardingChip(id: "classic-lps", label: "Classic LPs", icon: "record.circle",
                       collectionIDs: ["vinyl_bostonpubliclibrary", "vinyl_robert-haber-records"]),
        OnboardingChip(id: "live-radio", label: "Live Radio", icon: "radio",
                       collectionIDs: ["imcradio"]),
        OnboardingChip(id: "opera", label: "Opera", icon: "theatermasks",
                       collectionIDs: ["vinyl_frank-defreytas-memoria-opera"]),
    ]
}

struct OnboardingTasteView: View {
    @EnvironmentObject var deps: AppDependencies
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    let isEditing: Bool

    @State private var selectedIDs: Set<String> = []
    @State private var isSeeding = false
    @State private var errorText: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15)
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [Color(red: 0.42, green: 0.20, blue: 0.80),
                                                            Color(red: 0.10, green: 0.22, blue: 0.65)]),
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 54, height: 54)
                            .shadow(color: Color(red: 0.29, green: 0.12, blue: 0.59).opacity(0.7),
                                    radius: 10, x: 0, y: 4)
                        Image(systemName: "sparkles")
                            .font(.title3)
                            .foregroundStyle(.white)
                    }
                    .padding(.bottom, 16)
                    .accessibilityHidden(true)

                    Text("What do you\nlike to hear?")
                        .font(.system(size: 26, weight: .heavy, design: .default))
                        .lineSpacing(2)
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)

                Text("Pick a few. We'll fill your Made for You shelf right away \u{2014} and it keeps learning as you listen.")
                    .font(.system(size: 14.5))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(OnboardingChip.all) { chip in
                            Button {
                                if selectedIDs.contains(chip.id) {
                                    selectedIDs.remove(chip.id)
                                } else {
                                    selectedIDs.insert(chip.id)
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: chip.icon)
                                        .font(.system(size: 16))
                                        .frame(width: 30, height: 30)
                                        .background(selectedIDs.contains(chip.id)
                                            ? Color.white.opacity(0.22)
                                            : Color(.systemGray6))
                                        .clipShape(RoundedRectangle(cornerRadius: 9))
                                        .foregroundStyle(selectedIDs.contains(chip.id)
                                            ? .white : Color(red: 0.42, green: 0.20, blue: 0.80))
                                    Text(chip.label)
                                        .font(.system(size: 13.5, weight: .semibold))
                                        .foregroundStyle(selectedIDs.contains(chip.id) ? .white : .primary)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(12)
                                .frame(minHeight: 54)
                                .background(selectedIDs.contains(chip.id)
                                    ? AnyShapeStyle(LinearGradient(
                                        gradient: Gradient(colors: [Color(red: 0.42, green: 0.20, blue: 0.80),
                                                                     Color(red: 0.10, green: 0.22, blue: 0.65)]),
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                                    : AnyShapeStyle(Color(.systemBackground)))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(selectedIDs.contains(chip.id)
                                    ? nil
                                    : RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color(.separator), lineWidth: 0.5))
                                .overlay(alignment: .topTrailing) {
                                    if selectedIDs.contains(chip.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundStyle(.white)
                                            .padding(8)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selectedIDs.contains(chip.id) ? .isSelected : [])
                            .accessibilityLabel(chip.label)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }

                Spacer(minLength: 0)

                VStack(spacing: 11) {
                    Button {
                        Task { await buildShelf() }
                    } label: {
                        HStack(spacing: 7) {
                            if isSeeding {
                                ProgressView().tint(.white)
                            } else {
                                Text("Build my shelf")
                                Image(systemName: "arrow.right")
                            }
                        }
                        .font(.system(size: 16.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(LinearGradient(
                            gradient: Gradient(colors: [Color(red: 0.42, green: 0.20, blue: 0.80),
                                                         Color(red: 0.10, green: 0.22, blue: 0.65)]),
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: Color(red: 0.29, green: 0.12, blue: 0.59).opacity(0.75),
                                radius: 11, x: 0, y: 5)
                    }
                    .disabled(isSeeding || selectedIDs.isEmpty)
                    .accessibilityHint("Generates your personalized recommendations from selected styles")

                    Button(isEditing ? "Cancel" : "Skip for now") {
                        hasCompletedOnboarding = true
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(red: 0.42, green: 0.20, blue: 0.80))

                    Label("Stays on your device \u{00B7} no account, no tracking",
                          systemImage: "lock.shield")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .toolbar(isEditing ? .visible : .hidden, for: .navigationBar)
            .navigationTitle(isEditing ? "What you like" : "")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(!hasCompletedOnboarding)
    }

    private func buildShelf() async {
        isSeeding = true
        errorText = nil
        defer { isSeeding = false }

        let chips = OnboardingChip.all.filter { selectedIDs.contains($0.id) }
        let archiveService = deps.archiveService
        let tasteStore = TasteProfileStore(db: deps.db)

        for chip in chips {
            do {
                let queryParts: [String] = chip.collectionIDs.map { "collection:\($0)" }
                let query = queryParts.joined(separator: " OR ")
                if !query.isEmpty {
                    let tracks = try await fetchWithTimeout(archiveService, query: query)
                    for track in tracks {
                        await tasteStore.seedFromTrack(track, channel: nil,
                                                        boost: RecommendationConstants.onboardingSeedWeight)
                    }
                }
                if let creator = chip.creatorSeed {
                    await tasteStore.upsertTerm(bucket: "music", axis: "creator", term: creator.lowercased(),
                                                  increment: RecommendationConstants.onboardingSeedWeight)
                }
                if let subject = chip.subjectSeed {
                    await tasteStore.upsertTerm(bucket: "music", axis: "subject", term: subject.lowercased(),
                                                  increment: RecommendationConstants.onboardingSeedWeight)
                }
            } catch {
                if chip.collectionIDs.isEmpty { continue }
            }
        }

        hasCompletedOnboarding = true
        dismiss()
    }

    private func fetchWithTimeout(_ service: InternetArchiveService, query: String) async throws -> [Track] {
        try await withThrowingTaskGroup(of: [Track].self) { group in
            group.addTask { try await service.fetchTracks(iaQuery: query, matchTags: ["for-you"]) }
            group.addTask {
                try await Task.sleep(nanoseconds: 15_000_000_000)
                return []
            }
            let result = try await group.next() ?? []
            group.cancelAll()
            return result
        }
    }
}

struct OnboardingGateModifier: ViewModifier {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                if !hasCompletedOnboarding {
                    showOnboarding = true
                }
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingTasteView(isEditing: false)
            }
    }
}
