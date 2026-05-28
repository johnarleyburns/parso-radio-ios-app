import Foundation
import Network
import Combine

/// Lightweight reachability so playback can fail FAST and clearly when offline
/// (airplane mode, hikes) instead of timing out ~10 s and mishandling the
/// fallback. Plain class (not @MainActor) so the singleton initialises off any
/// actor; `isOnline` is always published on the main queue for safe UI binding.
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isOnline = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "guru.parso.networkmonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = (path.status == .satisfied)
            DispatchQueue.main.async { self?.isOnline = online }
        }
        monitor.start(queue: queue)
    }
}
