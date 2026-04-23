//
//  CookingModeView.swift
//  BiteRecipe
//
//  Full-screen cooking mode. Dark background with cream text for kitchen legibility.
//  Screen stays awake while cooking. Resets isIdleTimerDisabled on any dismiss path.
//
//  Navigation: swipe left/right + explicit Back/Next buttons.
//  Timer detection: scans each step for "N minutes/hours/seconds", shows Set Timer button.
//  Completion: swipe/tap past last step reveals completion card.
//

import SwiftUI
import UIKit
import BiteLedgerCore

// MARK: - TimerDetector

/// Scans step text for time patterns and returns the largest duration in seconds.
struct TimerDetector {
    private static let pattern = try! NSRegularExpression(
        pattern: #"\b(\d+)\s*(minutes?|hours?|seconds?)\b"#,
        options: .caseInsensitive
    )

    /// Returns the largest detected duration in seconds, or nil if none found.
    static func largestSeconds(in text: String) -> Int? {
        let range = NSRange(text.startIndex..., in: text)
        let matches = pattern.matches(in: text, range: range)
        guard !matches.isEmpty else { return nil }

        var largest = 0
        for match in matches {
            guard match.numberOfRanges == 3,
                  let numRange = Range(match.range(at: 1), in: text),
                  let unitRange = Range(match.range(at: 2), in: text),
                  let value = Int(text[numRange])
            else { continue }

            let unit = text[unitRange].lowercased()
            let seconds: Int
            if unit.hasPrefix("hour") {
                seconds = value * 3600
            } else if unit.hasPrefix("second") {
                seconds = value
            } else {
                seconds = value * 60  // minutes
            }
            largest = max(largest, seconds)
        }
        return largest > 0 ? largest : nil
    }

    /// Returns a human-readable label for the detected duration (e.g. "3 min", "1 hr 30 min").
    static func label(for seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) sec" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rem = minutes % 60
        return rem == 0 ? "\(hours) hr" : "\(hours) hr \(rem) min"
    }
}

// MARK: - CookingModeView

struct CookingModeView: View {
    let recipe: Recipe
    @Environment(\.dismiss) private var dismiss

    // Step index. steps.count == step index pointing at completion card.
    @State private var currentStep: Int = 0
    @State private var dragOffset: CGFloat = 0

    private var steps: [String] { recipe.directions }
    private var isComplete: Bool { currentStep >= steps.count }

    // MARK: Body

    var body: some View {
        ZStack {
            Color("CookingModeSurface").ignoresSafeArea()

            if isComplete {
                completionCard
            } else {
                stepView
            }
        }
        .onAppear {
            // Keep screen on while cooking.
            // isIdleTimerDisabled is a global flag — always reset in all dismiss paths.
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            // Reset when app backgrounds (e.g. phone call) — guard against battery drain.
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Re-enable when app returns to foreground (only if still in cooking mode).
            if !isComplete {
                UIApplication.shared.isIdleTimerDisabled = true
            }
        }
    }

    // MARK: - Step View

    private var stepView: some View {
        VStack(spacing: 0) {
            // Header: progress + exit
            HStack {
                Text("Step \(currentStep + 1) of \(steps.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color("CookingModeText").opacity(0.6))
                    .accessibilityLabel("Step \(currentStep + 1) of \(steps.count)")
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color("CookingModeText").opacity(0.6))
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Exit cooking mode")
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()
                .background(Color("CookingModeText").opacity(0.15))

            // Step content — scrollable for long steps / large Dynamic Type
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(steps[currentStep])
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(Color("CookingModeText"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isStaticText)

                    // Timer button — shown only when a duration is detected in the step
                    if let seconds = TimerDetector.largestSeconds(in: steps[currentStep]) {
                        timerButton(seconds: seconds)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }

            Divider()
                .background(Color("CookingModeText").opacity(0.15))

            // Navigation: Back / Next
            HStack(spacing: 12) {
                Button {
                    advance(by: -1)
                } label: {
                    Label("Back", systemImage: "arrow.left")
                        .font(.headline)
                        .foregroundStyle(Color("CookingModeText").opacity(currentStep == 0 ? 0.3 : 1))
                        .frame(minWidth: 80, minHeight: 44)
                }
                .disabled(currentStep == 0)
                .accessibilityLabel("Previous step")

                Spacer()

                Button {
                    advance(by: 1)
                } label: {
                    Label("Next", systemImage: "arrow.right")
                        .labelStyle(.titleAndIcon)
                        .font(.headline)
                        .foregroundStyle(Color("CookingModeText"))
                        .frame(minWidth: 80, minHeight: 44)
                }
                .accessibilityLabel(currentStep == steps.count - 1 ? "Finish cooking" : "Next step")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    if value.translation.width < -40 { advance(by: 1) }
                    if value.translation.width > 40 { advance(by: -1) }
                }
        )
    }

    // MARK: - Completion Card

    private var completionCard: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.brandAccent)

                Text("You cooked it!")
                    .font(.title.bold())
                    .foregroundStyle(Color("CookingModeText"))

                Text(recipe.name)
                    .font(.title3)
                    .foregroundStyle(Color("CookingModeText").opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Divider()
                .background(Color("CookingModeText").opacity(0.15))

            VStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandAccent)
                // v1.2 slot: [Log to BiteLedger] button will appear here
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    // Swipe right from completion goes back to last step
                    if value.translation.width > 40 { advance(by: -1) }
                }
        )
    }

    // MARK: - Timer Button

    private func timerButton(seconds: Int) -> some View {
        let label = TimerDetector.label(for: seconds)
        return Button {
            openTimer(seconds: seconds)
        } label: {
            Label("Set Timer: \(label)", systemImage: "timer")
                .font(.headline)
                .foregroundStyle(Color("CookingModeText"))
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.vertical, 4)
                .background(Color("CookingModeText").opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityLabel("Set timer for \(label)")
    }

    private func openTimer(seconds: Int) {
        let minutes = max(1, (seconds + 59) / 60)
        // Try iCloud Shortcuts deep link first; fall back to a banner copy button via alert.
        // In v1.1 we open the Shortcuts app timer — no in-app countdown (deferred to v1.2).
        if let url = URL(string: "shortcuts://run-shortcut?name=Timer"),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = URL(string: "clock-app://"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
        // Non-URL fallback: UIPasteboard copy so user can paste into any timer app.
        UIPasteboard.general.string = "\(minutes)"
    }

    // MARK: - Navigation

    private func advance(by delta: Int) {
        let next = currentStep + delta
        guard next >= 0, next <= steps.count else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            currentStep = next
        }
        if next >= steps.count {
            // Reached completion card — screen can now idle.
            UIApplication.shared.isIdleTimerDisabled = false
        } else {
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }
}
