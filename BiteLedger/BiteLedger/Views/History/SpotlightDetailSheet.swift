//
//  SpotlightDetailSheet.swift
//  BiteLedger
//
//  Phase 2, Feature 1: Nutrient Spotlight — drill-down sheet.
//  Shows which foods contributed most to the flagged nutrient this week.
//

import SwiftUI
import BiteLedgerCore

struct SpotlightDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let result: SpotlightResult
    let logs: [FoodLog]

    private var contributors: [FoodContribution] {
        NutrientSpotlightEngine.topContributors(for: result.nutrient, logs: logs)
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: Header section
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.nutrient.spotlightDisplayName)
                            .font(.title2.bold())
                            .foregroundStyle(Color("TextPrimary"))
                        Text("What's driving it this week")
                            .font(.subheadline)
                            .foregroundStyle(Color("TextSecondary"))
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                // MARK: Food rows
                if contributors.isEmpty {
                    Section {
                        Text("No food data for this week.")
                            .font(.subheadline)
                            .foregroundStyle(Color("TextSecondary"))
                    }
                } else {
                    Section {
                        ForEach(Array(contributors.enumerated()), id: \.offset) { _, contribution in
                            HStack {
                                Text(contribution.foodName)
                                    .font(.subheadline)
                                    .foregroundStyle(Color("TextPrimary"))
                                    .lineLimit(1)
                                Spacer()
                                Text(formattedAmount(contribution))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(Color("TextSecondary"))
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                // MARK: Footer
                Section {
                    Text("\(result.daysAboveThreshold) of 7 days above goal")
                        .font(.footnote)
                        .foregroundStyle(Color("TextTertiary"))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.insetGrouped)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color("TextTertiary"))
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func formattedAmount(_ contribution: FoodContribution) -> String {
        let unit = contribution.unit
        let amount = contribution.totalAmount
        if unit == "mg" {
            return "\(Int(amount.rounded()))mg"
        } else if unit == "g" {
            return "\(Int(amount.rounded()))g"
        } else if unit == "cal" {
            return "\(Int(amount.rounded()))cal"
        } else {
            return String(format: "%.1f\(unit)", amount)
        }
    }
}
