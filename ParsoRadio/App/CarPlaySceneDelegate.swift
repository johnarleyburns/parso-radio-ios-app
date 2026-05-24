import CarPlay
import UIKit

/// CarPlay entry point. Mirrors the phone's channel browser as CarPlay list
/// templates and drives the SAME shared `PlayerViewModel` (see
/// `ParsoMusicApp.sharedPlayerVM`), so the audio session and Now-Playing state
/// stay unified across the phone and the car.
///
/// GATED — requires the `com.apple.developer.carplay-audio` entitlement to be
/// GRANTED by Apple (Developer portal) + a regenerated provisioning profile.
/// Until then the CarPlay scene won't launch on a head unit and a Release build
/// that ships the entitlement won't sign. This file lives on the
/// `carplay-support` branch; do not merge to `main` before the grant. CARPLAY.md
/// has the full checklist. Untested beyond `swiftc -parse` (no local iOS
/// toolchain; CI only builds `main`) — CI validates it at merge time.
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?

    // Driving-friendly category order (subset of the phone's menu).
    private static let categoryOrder = [
        "For You", "Curated", "Audiobooks", "Lectures", "Contemporary", "News", "Ambient",
    ]

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        interfaceController.setRootTemplate(makeRootTemplate(), animated: false, completion: nil)
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        self.interfaceController = nil
    }

    // Root list = the categories that actually have channels, in order.
    private func makeRootTemplate() -> CPListTemplate {
        let present = Self.categoryOrder.filter { cat in
            Channel.defaults.contains { $0.category == cat }
        }
        let items: [CPListItem] = present.map { category in
            let item = CPListItem(text: category, detailText: nil)
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, completion in
                self?.pushChannels(for: category)
                completion()
            }
            return item
        }
        return CPListTemplate(title: "Parso Music", sections: [CPListSection(items: items)])
    }

    // Second level = the channels in a category. Tapping one starts it and pushes
    // the system Now-Playing template.
    private func pushChannels(for category: String) {
        let channels = Channel.defaults.filter { $0.category == category }
        let items: [CPListItem] = channels.map { channel in
            let item = CPListItem(text: channel.name,
                                  detailText: nil,
                                  image: UIImage(systemName: channel.icon))
            item.handler = { [weak self] _, completion in
                self?.play(channel: channel, then: completion)
            }
            return item
        }
        let template = CPListTemplate(title: category, sections: [CPListSection(items: items)])
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    private func play(channel: Channel, then completion: @escaping () -> Void) {
        let ic = interfaceController
        Task { @MainActor in
            await ParsoMusicApp.sharedPlayerVM.load(channel: channel)
            ic?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
            completion()
        }
    }
}
