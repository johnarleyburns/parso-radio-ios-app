import SwiftUI

/// Full-screen cover shown on first launch while the Declared Age Range API
/// resolves. Non-dismissible — the user must wait for the check to complete
/// (typically < 1 second). On iOS 17 or if the check fails/declines, a
/// "Defaulting to Kids Mode" fallback is shown with a math-puzzle gate to
/// upgrade.
struct AgeGateView: View {
    @Binding var isPresented: Bool
    let onComplete: () -> Void

    @StateObject private var service = AgeAssuranceService.shared
    @State private var showFallback = false
    @State private var parentGateAnswer = ""
    @State private var parentGateError = false
    @State private var mathA = 0
    @State private var mathB = 0

    var body: some View {
        VStack(spacing: 24) {
            if showFallback {
                fallbackView
            } else {
                checkingView
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .task {
            await service.performCheck()
            if service.requiresKidsMode && !service.needsCheck {
                // Unknown or child — show fallback with parental upgrade option
                showFallback = true
            } else {
                // Teen or adult — proceed
                isPresented = false
                onComplete()
            }
        }
    }

    private var checkingView: some View {
        VStack(spacing: 24) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            ProgressView()
                .scaleEffect(1.2)
            Text("Setting up your experience…")
                .font(.headline)
            Text("Lorewave uses privacy-preserving age assurance to provide the right experience for your age group.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var fallbackView: some View {
        VStack(spacing: 20) {
            Image(systemName: "shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Welcome to Lorewave")
                .font(.title2.bold())

            Text("To protect young listeners, we're starting you in Kids Mode — a safe space with curated children's stories and songs. No personal data is collected.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider().padding(.vertical, 4)

            Text("Adult or Teen?")
                .font(.headline)

            Text("Solve this to unlock the full classic literature catalog:")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Image(systemName: "function")
                    .foregroundStyle(.secondary)
                Text("\(mathA) + \(mathB) =")
                    .font(.title3.monospacedDigit())
                TextField("?", text: $parentGateAnswer)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .multilineTextAlignment(.center)
            }

            if parentGateError {
                Text("That's not right — try again.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("Unlock Full Catalog") {
                verifyParentalGate()
            }
            .buttonStyle(.borderedProminent)
            .disabled(parentGateAnswer.isEmpty)

            Button("Stay in Kids Mode") {
                // User explicitly stays in Kids Mode → proceed with child bracket
                isPresented = false
                onComplete()
            }
            .font(.subheadline)
        }
        .onAppear {
            mathA = Int.random(in: 7...19)
            mathB = Int.random(in: 3...11)
        }
    }

    private func verifyParentalGate() {
        guard let answer = Int(parentGateAnswer), answer == mathA + mathB else {
            parentGateError = true
            parentGateAnswer = ""
            return
        }
        service.overrideToTeen()
        isPresented = false
        onComplete()
    }
}
