//
//  NutrientSpotlightCard.swift
//  BiteLedger
//
//  Phase 2, Feature 1: Nutrient Spotlight — HistoryView card surface.
//  Shows up to 2 qualifying spotlight nutrients with their days-above counts.
//  Caller must pass a non-empty results array.
//

import SwiftUI
import BiteLedgerCore

struct NutrientSpotlightCard: View {
    /// Non-empty. Caller guards isEmpty before rendering.
    let results: [SpotlightResult]

    var body: some View {
        ElevatedCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {

                // MARK: Header
                Text("THIS WEEK'S SPOTLIGHT")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color("TextSecondary"))
                    .tracking(1)

                // MARK: Observation
                Text(results[0].message)
                    .font(.body)
                    .foregroundStyle(Color("TextPrimary"))

                // MARK: Curiosity prompt
                Text(NutrientSpotlightEngine.curiosityPrompt)
                    .font(.body.italic())
                    .foregroundStyle(Color("TextSecondary"))

                // MARK: Nutrient rows (up to 2)
                VStack(spacing: 0) {
                    ForEach(Array(results.prefix(2).enumerated()), id: \.offset) { index, result in
                        if index > 0 {
                            Color("DividerSubtle")
                                .frame(height: 1)
                        }
                        HStack {
                            Text(result.nutrient.spotlightDisplayName)
                                .font(.subheadline)
                                .foregroundStyle(Color("TextPrimary"))
                            Spacer()
                            Text("\(result.daysAboveThreshold) of 7 days")
                                .font(.caption)
                                .foregroundStyle(Color("TextTertiary"))
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NutrientSpotlightCard(results: [
        SpotlightResult(nutrient: .sodium, daysAboveThreshold: 5),
        SpotlightResult(nutrient: .saturatedFat, daysAboveThreshold: 3)
    ])
    .padding()
}
