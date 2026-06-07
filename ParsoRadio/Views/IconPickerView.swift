import SwiftUI

struct IconPickerView: View {
    @Binding var selectedIcon: String
    let channelId: String
    let chStore: CustomChannelsStore
    @Environment(\.dismiss) private var dismiss

    static let allIcons: [(String, String)] = [
        // Music
        ("music.note", "Music Note"), ("music.quarternote.3", "Notes"),
        ("guitars.fill", "Guitars"), ("pianokeys", "Piano"),
        ("headphones", "Headphones"), ("speaker.wave.3", "Speaker"),
        // Star / favorites
        ("star.fill", "Star"), ("star.circle.fill", "Star Circle"),
        ("heart.fill", "Heart"), ("crown.fill", "Crown"),
        // Nature
        ("leaf.fill", "Leaf"), ("tree.fill", "Tree"),
        ("mountain.2", "Mountain"), ("water.waves", "Waves"),
        ("flame.fill", "Flame"), ("leaf.arrow.circlepath", "Recycle"),
        // Books / Education
        ("book.fill", "Book"), ("books.vertical.fill", "Books"),
        ("text.book.closed.fill", "Textbook"), ("book.pages.fill", "Pages"),
        ("character.book.closed", "Character"), ("graduationcap.fill", "Graduation"),
        // Science
        ("atom", "Atom"), ("flask.fill", "Flask"),
        ("brain.head.profile", "Brain"), ("microscope", "Microscope"),
        // People
        ("person.fill", "Person"), ("person.2.fill", "People"),
        ("person.3.fill", "Group"), ("figure.walk", "Walking"),
        ("figure.mind.and.body", "Yoga"), ("rectangle.3.group", "Users"),
        // Places
        ("house.fill", "House"), ("building.2.fill", "Buildings"),
        ("globe.americas", "Americas"), ("globe.europe.africa.fill", "Europe/Africa"),
        ("globe.asia.australia.fill", "Asia/Australia"), ("tent.fill", "Tent"),
        // Tech / Audio
        ("radio.fill", "Radio"), ("antenna.radiowaves.left.and.right", "Antenna"),
        ("ear.badge.waveform", "Ear Waveform"), ("wifi", "WiFi"),
        ("mic.fill", "Mic"), ("waveform", "Waveform"),
        // Objects
        ("clock.fill", "Clock"), ("cup.and.saucer.fill", "Tea"),
        ("theatermasks.fill", "Theater"), ("paintpalette.fill", "Palette"),
        ("camera.fill", "Camera"), ("photo.fill", "Photo"),
        // Fun / Misc
        ("sun.max.fill", "Sun"), ("moon.stars.fill", "Moon & Stars"),
        ("cloud.fill", "Cloud"), ("bolt.fill", "Bolt"),
        ("bell.fill", "Bell"), ("tag.fill", "Tag"),
    ]

    let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Self.allIcons, id: \.0) { icon, name in
                        VStack(spacing: 4) {
                            Image(systemName: icon)
                                .font(.title2)
                                .foregroundStyle(selectedIcon == icon ? .white : .primary)
                                .frame(width: 44, height: 44)
                                .background(
                                    selectedIcon == icon
                                        ? Color.accentColor
                                        : Color(.secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 10))
                            Text(name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .onTapGesture {
                            selectedIcon = icon
                            chStore.updateIcon(chId: channelId, newIcon: icon)
                            dismiss()
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
