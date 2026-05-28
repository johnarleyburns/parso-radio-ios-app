import SwiftUI

/// First-launch gate: Terms of Service + Privacy Policy acceptance.
/// Shown once; persisted via @AppStorage("tosAccepted").
/// interactiveDismissDisabled prevents swipe-to-dismiss.
struct TermsView: View {
    @Binding var isPresented: Bool

    @State private var termsAgreed = false
    @State private var hasScrolledToBottom = false
    @State private var showDeclineAlert = false

    private var canProceed: Bool { termsAgreed && hasScrolledToBottom }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        tosHeader
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .padding(.bottom, 24)

                        Divider()

                        tosBody
                            .padding(.horizontal, 20)
                            .padding(.vertical, 20)

                        // Sentinel: becomes visible when user reaches the bottom.
                        Color.clear
                            .frame(height: 1)
                            .onAppear { hasScrolledToBottom = true }
                            .padding(.bottom, 8)
                    }
                }

                Divider()

                actionFooter
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Color(.systemBackground))
            }
            .navigationTitle("Terms of Service")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(true)
        .alert("Cannot Continue", isPresented: $showDeclineAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You must agree to the Terms of Service to use Lorewave. To decline, close the app.")
        }
    }

    // MARK: - Header

    private var tosHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LinearGradient(
                            colors: [Color(red: 0.42, green: 0.20, blue: 0.80),
                                     Color(red: 0.10, green: 0.22, blue: 0.65)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 56, height: 56)
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Lorewave")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("End User License Agreement")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Licensor: Parso Consulting · info@parso.guru")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Body

    private var tosBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            tosSection(
                title: "Acknowledgement",
                body: """
Parso Consulting ("Licensor") and you ("End-User") acknowledge that this End User License Agreement ("EULA") is concluded between Licensor and End-User only, and not with Apple Inc. ("Apple"). Licensor, not Apple, is solely responsible for the Licensed Application ("Lorewave") and its content.

This EULA may not provide for usage rules for Lorewave that are in conflict with the Apple Media Services Terms and Conditions as of the date you download Lorewave.
"""
            )

            tosSection(
                title: "Scope of License",
                body: """
Licensor grants you a non-transferable, non-exclusive, non-sublicensable license to install and use Lorewave on any Apple-branded products that you own or control. You may not distribute or make Lorewave available over a network where it could be used by multiple devices at the same time. You may not copy (except as permitted by this license), reverse-engineer, disassemble, attempt to derive the source code of, modify, or create derivative works of Lorewave.
"""
            )

            tosSection(
                title: "Content",
                body: """
Lorewave streams audio content from the Internet Archive (archive.org) and the Free Music Archive (freemusicarchive.org). All streamed content is public-domain or licensed under Creative Commons. Licensor does not produce or own this content and is not responsible for its accuracy or availability.
"""
            )

            tosSection(
                title: "No Warranty",
                body: """
To the maximum extent permitted by applicable law, Lorewave is provided "AS IS" and "AS AVAILABLE," with all faults and without warranty of any kind. Licensor disclaims all warranties, express or implied, including implied warranties of merchantability, fitness for a particular purpose, and non-infringement.
"""
            )

            tosSection(
                title: "Limitation of Liability",
                body: """
To the extent not prohibited by law, Licensor shall not be liable for any incidental, special, indirect, or consequential damages arising out of or related to your use or inability to use Lorewave.
"""
            )

            tosSection(
                title: "Privacy",
                body: """
Lorewave does not collect, store, transmit, or share any personal information. Playback position for spoken-word channels is stored locally on your device only. No analytics, tracking, or account is required. See the full Privacy Policy in Settings → About.
"""
            )

            tosSection(
                title: "Maintenance and Support",
                body: """
Licensor is solely responsible for providing maintenance and support for Lorewave. Apple has no obligation to furnish any maintenance or support. Contact: info@parso.guru
"""
            )

            tosSection(
                title: "Third-Party Beneficiary",
                body: """
Apple and Apple's subsidiaries are third-party beneficiaries of this EULA. Upon your acceptance, Apple will have the right to enforce this EULA against you as a third-party beneficiary.
"""
            )

            tosSection(
                title: "Legal Compliance",
                body: """
You represent that you are not located in a country subject to a U.S. Government embargo and are not listed on any U.S. Government list of prohibited or restricted parties.
"""
            )

            tosSection(
                title: "Contact",
                body: "Parso Consulting · info@parso.guru"
            )
        }
    }

    // MARK: - Footer

    private var actionFooter: some View {
        VStack(spacing: 12) {
            if !hasScrolledToBottom {
                Text("Scroll to the bottom to review the full agreement.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                termsAgreed.toggle()
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: termsAgreed ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundStyle(termsAgreed ? Color.accentColor : Color(.systemGray))
                        .animation(.easeInOut(duration: 0.15), value: termsAgreed)
                        .accessibilityHidden(true)
                    Text("I have read and agree to the Terms of Service and End User License Agreement.")
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isToggle)
            .accessibilityValue(termsAgreed ? "Checked" : "Not checked")

            Button {
                UserDefaults.standard.set(true, forKey: "tosAccepted")
                isPresented = false
            } label: {
                Text("Agree & Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canProceed ? Color.accentColor : Color(.systemFill))
                    .foregroundStyle(canProceed ? .white : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!canProceed)

            Button {
                showDeclineAlert = true
            } label: {
                Text("Decline")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helper

    private func tosSection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(body)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    TermsView(isPresented: .constant(true))
}
