import Foundation
#if canImport(DeclaredAgeRange)
import DeclaredAgeRange
#endif
#if canImport(UIKit)
import UIKit
#endif
import SwiftUI

enum AgeBracket: String, Equatable, Sendable {
    case child   // under 13
    case teen    // 13–17
    case adult   // 18+
    case unknown // declined, unavailable, or error
}

/// Privacy-preserving age triage using Apple's Declared Age Range API
/// (iOS 18+). On iOS 17 the API is unavailable — we default to the
/// safety-first "unknown" bracket which boots into Kids Mode, with a
/// math-puzzle parental gate to upgrade.
///
/// One-shot: after the check completes, the result is persisted. Subsequent
/// launches skip the API call entirely.
@MainActor
final class AgeAssuranceService: ObservableObject {
    static let shared = AgeAssuranceService()

    private enum Key {
        static let bracket   = "ageAssurance.bracket"
        static let completed = "ageAssurance.completed"
    }

    private let defaults: UserDefaults
    @Published private(set) var bracket: AgeBracket

    var needsCheck: Bool { !defaults.bool(forKey: Key.completed) }
    var isChild: Bool { bracket == .child }
    var requiresKidsMode: Bool { bracket == .child || bracket == .unknown }
    var requiresTrackingDisabled: Bool { bracket == .teen }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.bool(forKey: Key.completed),
           let raw = defaults.string(forKey: Key.bracket),
           let b = AgeBracket(rawValue: raw) {
            bracket = b
        } else {
            bracket = .unknown
        }
    }

    func performCheck() async {
        #if canImport(DeclaredAgeRange)
        if #available(iOS 26.0, *) {
            await performDeclaredRangeCheck()
        } else {
            storeResult(.unknown)
        }
        #else
        storeResult(.unknown)
        #endif
    }

    /// Manual override via parental gate (math puzzle).
    /// Promotes the bracket to .teen so the user can access the 13+ catalog.
    func overrideToTeen() {
        storeResult(.teen)
    }

    #if canImport(DeclaredAgeRange)
    @available(iOS 26.0, *)
    private func performDeclaredRangeCheck() async {
        #if canImport(UIKit)
        // The Declared Age Range API was introduced in iOS 26.
        // Once the API stabilizes, replace this with the actual call.
        // Expected pattern (subject to change):
        //   let response = try await AgeRangeService.shared.requestAgeRange(ageGates: 13, in: rootVC)
        //   switch response.status { ... }
        storeResult(.unknown)
        #else
        storeResult(.unknown)
        #endif
    }
    #endif

    private func storeResult(_ b: AgeBracket) {
        bracket = b
        defaults.set(b.rawValue, forKey: Key.bracket)
        defaults.set(true, forKey: Key.completed)
    }

    // MARK: - Test support

    /// Override for testing purposes only.
    func _testSet(checkDone: Bool) {
        if !checkDone {
            defaults.removeObject(forKey: Key.completed)
            defaults.removeObject(forKey: Key.bracket)
            bracket = .unknown
        }
    }
}
