import SwiftUI

/// The contribution ask — a dismissible bottom card (never a full-screen
/// interstitial, never over the player controls). Three actions per the plan:
/// Support / Maybe later / Don't ask again.
struct ContributionToast: View {
    let onSupport: () -> Void
    let onLater: () -> Void
    let onNever: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enjoying Lorewave?")
                .font(.headline)
            Text("It's free and ad-free. A contribution helps keep it that way — and we give 10% to the Internet Archive.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Don't ask again", action: onNever)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Maybe later", action: onLater)
                    .font(.subheadline)
                Button("Support", action: onSupport)
                    .font(.subheadline).fontWeight(.semibold)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
    }
}
