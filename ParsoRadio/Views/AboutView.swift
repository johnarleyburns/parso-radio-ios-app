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

    // MARK: - Privacy policy

    private var privacyPolicy: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text("Privacy Policy")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
                Link("View Online", destination: URL(string: "https://parso.guru/privacy")!)
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
