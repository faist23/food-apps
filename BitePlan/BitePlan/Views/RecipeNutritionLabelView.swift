//
//  RecipeNutritionLabelView.swift
//  BitePlan
//

import SwiftUI
import BiteLedgerCore

struct RecipeNutritionLabelView: View {
    @Environment(\.dismiss) private var dismiss

    let recipeName: String
    let servings: Double
    let perServing: NutritionCalculator.Result

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    labelCard
                }
                .padding()
            }
            .navigationTitle("Nutrition Facts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Label card

    private var labelCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Nutrition Facts")
                    .font(.system(size: 36, weight: .black))
                Text("\(Int(servings)) servings per recipe")
                    .font(.system(size: 13))
                HStack {
                    Text("Serving size").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("1 serving").font(.system(size: 13, weight: .semibold))
                }
                heavyDivider(height: 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            VStack(spacing: 0) {
                // Amount per serving / Calories
                Text("Amount per serving")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)

                HStack(alignment: .firstTextBaseline) {
                    Text("Calories").font(.system(size: 32, weight: .black))
                    Spacer()
                    Text("\(Int(perServing.calories))").font(.system(size: 44, weight: .black))
                }
                .padding(.vertical, 4)

                heavyDivider(height: 6).padding(.vertical, 4)

                // % DV header
                HStack {
                    Spacer()
                    Text("% Daily Value*").font(.system(size: 12, weight: .bold))
                }
                .padding(.bottom, 4)

                thinDivider()

                // Macros
                row("Total Fat", perServing.fat, "g", bold: true)
                thinDivider()

                if let v = perServing.saturatedFat, v > 0 {
                    indentedRow("Saturated Fat", v, "g")
                    thinDivider()
                }
                if let v = perServing.transFat, v > 0 {
                    indentedRow("Trans Fat", v, "g")
                    thinDivider()
                }
                if let v = perServing.cholesterol, v > 0 {
                    row("Cholesterol", v, "mg", bold: true)
                    thinDivider()
                }
                if let v = perServing.sodium, v > 0 {
                    row("Sodium", v, "mg", bold: true)
                    thinDivider()
                }

                row("Total Carbohydrate", perServing.carbs, "g", bold: true)
                thinDivider()

                if let v = perServing.fiber, v > 0 {
                    indentedRow("Dietary Fiber", v, "g")
                    thinDivider()
                }
                if let v = perServing.sugar, v > 0 {
                    indentedRow("Total Sugars", v, "g")
                    thinDivider()
                }

                row("Protein", perServing.protein, "g", bold: true)

                // Heavy divider before vitamins
                heavyDivider(height: 8).padding(.vertical, 4)

                // Vitamins / minerals (only show non-zero)
                Group {
                    if let v = perServing.vitaminD, v > 0 { row("Vitamin D", v, "mcg"); thinDivider() }
                    if let v = perServing.calcium, v > 0 { row("Calcium", v, "mg"); thinDivider() }
                    if let v = perServing.iron, v > 0 { row("Iron", v, "mg"); thinDivider() }
                    if let v = perServing.potassium, v > 0 { row("Potassium", v, "mg"); thinDivider() }
                    if let v = perServing.vitaminA, v > 0 { row("Vitamin A", v, "mcg"); thinDivider() }
                    if let v = perServing.vitaminC, v > 0 { row("Vitamin C", v, "mg"); thinDivider() }
                    if let v = perServing.magnesium, v > 0 { row("Magnesium", v, "mg"); thinDivider() }
                    if let v = perServing.zinc, v > 0 { row("Zinc", v, "mg"); thinDivider() }
                }

                heavyDivider(height: 4).padding(.top, 4)

                Text("* The % Daily Value (DV) tells you how much a nutrient in a serving contributes to a daily diet. 2,000 calories a day is used for general nutrition advice.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        )
    }

    // MARK: - Row builders

    private func row(_ label: String, _ value: Double, _ unit: String, bold: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(.system(size: 14))
                .fontWeight(bold ? .black : .regular)
            Spacer()
            Text(fmt(value) + unit)
                .font(.system(size: 14))
                .fontWeight(bold ? .bold : .regular)
                .frame(minWidth: 60, alignment: .trailing)
            dvText(value, for: label)
        }
        .padding(.vertical, 2)
    }

    private func indentedRow(_ label: String, _ value: Double, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(.system(size: 14))
                .padding(.leading, 20)
            Spacer()
            Text(fmt(value) + unit)
                .font(.system(size: 14))
                .frame(minWidth: 60, alignment: .trailing)
            dvText(value, for: label)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func dvText(_ value: Double, for label: String) -> some View {
        if let pct = percentDV(value, for: label) {
            Text("\(pct)%")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
        } else {
            Text("").frame(width: 50)
        }
    }

    // MARK: - Dividers

    private func heavyDivider(height: CGFloat) -> some View {
        Rectangle().fill(Color.primary).frame(height: height)
    }

    private func thinDivider() -> some View {
        Rectangle().fill(Color.primary).frame(height: 1)
    }

    // MARK: - Helpers

    private func fmt(_ v: Double) -> String {
        if v >= 100 { return "\(Int(v))" }
        else if v >= 10 { return String(format: "%.1f", v) }
        else { return String(format: "%.2f", v) }
    }

    private func percentDV(_ value: Double, for label: String) -> Int? {
        let dv: Double
        switch label {
        case "Total Fat":          dv = 78
        case "Saturated Fat":      dv = 20
        case "Cholesterol":        dv = 300
        case "Sodium":             dv = 2300
        case "Total Carbohydrate": dv = 275
        case "Dietary Fiber":      dv = 28
        case "Total Sugars":       dv = 50
        case "Protein":            dv = 50
        case "Vitamin D":          dv = 20
        case "Calcium":            dv = 1300
        case "Iron":               dv = 18
        case "Potassium":          dv = 4700
        case "Vitamin A":          dv = 900
        case "Vitamin C":          dv = 90
        case "Magnesium":          dv = 420
        case "Zinc":               dv = 11
        default: return nil
        }
        guard dv > 0 else { return nil }
        return Int((value / dv * 100).rounded())
    }
}
