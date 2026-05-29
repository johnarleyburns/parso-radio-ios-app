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
            // Single action row: "Maybe later" on the left, the blue Support
            // button hard-right. fixedSize stops "Support" from being squeezed
            // onto two lines (the bug); the Spacer keeps the two apart instead of
            // crowding "Maybe later" against the button.
            HStack(spacing: 12) {
                Button("Maybe later", action: onLater)
                    .font(.subheadline)
                    .fixedSize()
                Spacer(minLength: 12)
                Button("Support", action: onSupport)
                    .font(.subheadline).fontWeight(.semibold)
                    .lineLimit(1)
                    .fixedSize()
                    .buttonStyle(.borderedProminent)
            }
            // De-emphasised, full-width-centered so it never competes with the
            // two primary actions above.
            Button("Don't ask again", action: onNever)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
    }
}
