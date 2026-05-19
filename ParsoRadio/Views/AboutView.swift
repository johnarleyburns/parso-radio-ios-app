import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    appHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 28)

                    Divider()

                    credits
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)

                    Divider()

                    copyright
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)

                    Divider()

                    privacyPolicy
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - App header

    private var appHeader: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.42, green: 0.20, blue: 0.80),
                                 Color(red: 0.10, green: 0.22, blue: 0.65)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 72, height: 72)
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Parso Music")
                    .font(.title2)
                    .fontWeight(.bold)

                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                   let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                    Text("Version \(version) (\(build))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Link("© 2026 Parso Consulting", destination: URL(string: "https://www.parso.guru")!)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Credits / attribution

    private var credits: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Audio & Video Credits")
                .font(.title3)
                .fontWeight(.bold)

            Text("All ambient loop sounds are CC0 (public domain).")
                .font(.footnote)
                .foregroundStyle(.secondary)

            creditRow(title: "Rainy Day", author: "speakwithanimals",
                      license: "CC0 (Public Domain)",
                      url: "https://freesound.org/people/speakwithanimals/sounds/525046/")
            creditRow(title: "Flowing Water", author: "eardeer",
                      license: "CC0 (Public Domain)",
                      url: "https://freesound.org/people/eardeer/sounds/443869/")
            creditRow(title: "Ocean Waves", author: "Nox_Sound",
                      license: "CC0 (Public Domain)",
                      url: "https://freesound.org/people/Nox_Sound/sounds/829629/")

            Text("Ambient background videos provided by Mixkit (Mixkit Free License). All streamed music and audiobooks are public-domain or Creative Commons licensed; the source and license are shown for every track.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func creditRow(title: String, author: String,
                           license: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(title) — \(author)")
                .font(.footnote)
                .fontWeight(.semibold)
            HStack(spacing: 6) {
                Text(license)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link("Source", destination: URL(string: url)!)
                    .font(.caption)
            }
        }
    }

    // MARK: - Copyright / DMCA

    private var copyright: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Copyright & DMCA")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
                Link("Report", destination: URL(string:
                    "mailto:info@parso.guru?subject=DMCA%20%2F%20Copyright%20Report")!)
                    .font(.subheadline)
            }

            policySection(
                title: "We host nothing",
                body: "Parso Radio does not upload, host, or store any audio. It only streams works that the source repositories — the Internet Archive, the Free Music Archive, and Freesound — publish as public domain or under Creative Commons licenses. The source and license are shown for every track."
            )

            policySection(
                title: "Reporting infringing content",
                body: "If you are a rights holder (or authorized to act for one) and believe a track reachable through the App infringes your copyright, email info@parso.guru with the subject \"DMCA / Copyright Report\" and include:\n\n1. Identification of the copyrighted work you claim is infringed.\n2. The track title and/or source identifier shown in the App (and the channel/search it appeared in) so we can locate it.\n3. Your name, address, phone, and email.\n4. A statement that you have a good-faith belief the use is not authorized by the rights holder, its agent, or the law.\n5. A statement, made under penalty of perjury, that the information in your notice is accurate and that you are the copyright owner or authorized to act on the owner's behalf.\n6. Your physical or electronic signature."
            )

            policySection(
                title: "Our process",
                body: "We investigate every properly submitted report promptly. If infringement is verified, we disable the link to that material in the App as soon as practicable and may exclude the offending source item. Sources that repeatedly surface infringing material may be removed entirely. If you believe content was disabled in error, you may submit a counter-notice to the same address and we will review it."
            )

            policySection(
                title: "Contact",
                body: "Copyright agent: Parso Consulting — info@parso.guru. We aim to acknowledge valid notices within a few business days."
            )
        }
    }

    // MARK: - Privacy policy

    private var privacyPolicy: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text("Privacy Policy")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
                Link("View Online", destination: URL(string: "https://parso.guru/parso-radio-privacy")!)
                    .font(.subheadline)
            }

            Text("Effective Date: May 1, 2026")
                .font(.caption)
                .foregroundStyle(.secondary)

            policySection(
                title: "Overview",
                body: "Parso Consulting (\"we,\" \"our,\" or \"us\") operates the mobile application Parso Music (the \"App\") available on the Apple App Store. This Privacy Policy describes how we handle information in compliance with App Store requirements."
            )

            policySection(
                title: "Information Collection and Use",
                body: "We do not collect, store, transmit, or share any personal information or user data through the App. Specifically:\n\n• No account or login is required\n• No personal identifiers are collected\n• No location data is collected\n• No usage analytics or tracking data is collected\n• No listening history is transmitted to us\n\nPlayback position for spoken-word channels is stored locally on your device only, so you can resume where you left off. This data never leaves your device."
            )

            policySection(
                title: "Third-Party Content",
                body: "The App streams audio from the Internet Archive (archive.org) and the Free Music Archive (freemusicarchive.org). These are independent services with their own privacy policies. We do not control their data practices. The content streamed is public-domain or Creative Commons licensed."
            )

            policySection(
                title: "Data Sharing",
                body: "Because we do not collect any data, we do not share any information with third parties."
            )

            policySection(
                title: "Apple App Store Compliance",
                body: "The App does not collect data as defined under Apple's App Privacy requirements. The App does not track users across apps or websites. No App Tracking Transparency (ATT) permission is required. The App uses no third-party SDKs that collect data."
            )

            policySection(
                title: "Children's Privacy",
                body: "Parso Music is designed to be appropriate for all ages, including children. We do not knowingly collect any personal information from any user, including children under the age of 13."
            )

            policySection(
                title: "Changes to This Policy",
                body: "We may update this Privacy Policy from time to time. Any changes will be reflected in the App or the App Store listing."
            )

            policySection(
                title: "Contact",
                body: "If you have any questions about this Privacy Policy, please contact us at info@parso.guru."
            )

            Divider()

            Text("Parso Music streams public-domain and Creative Commons licensed audio. No copyrighted content is stored or distributed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    private func policySection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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
    AboutView()
}
