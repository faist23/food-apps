//
//  NutritionSummaryCard.swift
//  BiteLedger
//
//  Created by Craig Faist on 2/16/26.
//


import SwiftUI
import BiteLedgerCore

struct NutritionSummaryCard: View {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    
    var body: some View {
        VStack(spacing: 16) {
            // Large calorie display
            VStack(spacing: 4) {
                Text("\(Int(calories))")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                Text("calories")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            // Macros
            HStack(spacing: 24) {
                MacroView(name: "Protein", amount: protein, unit: "g", color: .blue)
                MacroView(name: "Carbs", amount: carbs, unit: "g", color: .green)
                MacroView(name: "Fat", amount: fat, unit: "g", color: .orange)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct MacroView: View {
    let name: String
    let amount: Double
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(Int(amount))\(unit)")
                .font(.headline)
                .foregroundStyle(color)
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NutritionSummaryCard(
        calories: 1847,
        protein: 98,
        carbs: 203,
        fat: 62
    )
    .padding()
}