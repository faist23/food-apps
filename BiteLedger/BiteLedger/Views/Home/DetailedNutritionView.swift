//
//  DetailedNutritionView.swift
//  BiteLedger
//
//  Created by Craig Faist on 2/16/26.
//

import SwiftUI
import SwiftData
import BiteLedgerCore

struct DetailedNutritionView: View {
    @Environment(\.dismiss) private var dismiss
    
    let title: String
    let logs: [FoodLog]
    let preferences: UserPreferences?
    
    // MARK: - Totals
    
    private var totalCalories: Double {
        logs.reduce(0) { $0 + $1.caloriesAtLogTime }
    }
    
    private var totalProtein: Double {
        logs.reduce(0) { $0 + $1.proteinAtLogTime }
    }
    
    private var totalCarbs: Double {
        logs.reduce(0) { $0 + $1.carbsAtLogTime }
    }
    
    private var totalFat: Double {
        logs.reduce(0) { $0 + $1.fatAtLogTime }
    }
    
    // MARK: - Macro Calories
    
    private var fatCalories: Double { totalFat * 9 }
    private var carbCalories: Double { totalCarbs * 4 }
    private var proteinCalories: Double { totalProtein * 4 }
    
    private var totalMacroCalories: Double {
        fatCalories + carbCalories + proteinCalories
    }
    
    private var fatPercent: Double {
        totalMacroCalories == 0 ? 0 : fatCalories / totalMacroCalories
    }
    
    private var carbPercent: Double {
        totalMacroCalories == 0 ? 0 : carbCalories / totalMacroCalories
    }
    
    private var proteinPercent: Double {
        totalMacroCalories == 0 ? 0 : proteinCalories / totalMacroCalories
    }
    
    // MARK: - Micronutrient Helper
    
    // Sum from FoodLog cached values (for vitamins/minerals already in mg/mcg)
    private func sumFromLog(_ keyPath: KeyPath<FoodLog, Double?>) -> Double {
        logs.compactMap { $0[keyPath: keyPath] }.reduce(0, +)
    }
    
    // MARK: - FDA Daily Values (based on 2000 calorie diet)
    
    private func fdaDailyValue(for nutrient: String) -> Double? {
        switch nutrient {
        case "Total Fat": return 78
        case "Saturated Fat": return 20
        case "Cholesterol": return 300 // mg
        case "Sodium": return 2300 // mg
        case "Total Carbohydrate": return 275
        case "Dietary Fiber": return 28
        case "Total Sugars": return 50
        case "Protein": return 50
        case "Vitamin A": return 900 // mcg
        case "Vitamin C": return 90 // mg
        case "Vitamin D": return 20 // mcg
        case "Vitamin E": return 15 // mg
        case "Vitamin K": return 120 // mcg
        case "Vitamin B6": return 1.7 // mg
        case "Vitamin B12": return 2.4 // mcg
        case "Folate": return 400 // mcg
        case "Choline": return 550 // mg
        case "Calcium": return 1300 // mg
        case "Iron": return 18 // mg
        case "Potassium": return 4700 // mg
        case "Magnesium": return 420 // mg
        case "Zinc": return 11 // mg
        default: return nil
        }
    }
    
    // Get daily value from user preferences or FDA defaults
    private func dailyValue(for nutrient: Nutrient) -> Double? {
        // First check user preferences
        if let userGoal = preferences?.goals[nutrient.rawValue] {
            return userGoal.targetValue
        }
        
        // Fallback to FDA values
        return fdaDailyValue(for: nutrient.rawValue)
    }
    
    // Calculate percentage of daily value
    private func percentDV(_ value: Double, for label: String) -> Int? {
        guard let dv = fdaDailyValue(for: label), dv > 0 else { return nil }
        return Int((value / dv * 100).rounded())
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // MARK: - Macro Card
                    
                    macroCard
                    
                    // MARK: - Nutrition Facts Label
                    
                    nutrientCard(title: "Nutrition Facts") {
                        nutritionFactsRows
                    }
                }
                .padding()
            }
            .background(Color.surfacePrimary)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.brandAccent)
                }
            }
        }
    }
}

private extension DetailedNutritionView {
    
    var macroCard: some View {
        ElevatedCard(padding: 24, cornerRadius: 24) {
            VStack(spacing: 20) {
                
                // Donut
                ZStack {
                    Circle()
                        .stroke(Color.surfacePrimary, lineWidth: 18)
                    
                    Circle()
                        .trim(from: 0, to: fatPercent)
                        .stroke(Color("MacroFat"),
                                style: StrokeStyle(lineWidth: 18, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    
                    Circle()
                        .trim(from: 0, to: carbPercent)
                        .stroke(Color("MacroCarbs"),
                                style: StrokeStyle(lineWidth: 18, lineCap: .round))
                        .rotationEffect(.degrees(-90 + fatPercent * 360))
                    
                    Circle()
                        .trim(from: 0, to: proteinPercent)
                        .stroke(Color("MacroProtein"),
                                style: StrokeStyle(lineWidth: 18, lineCap: .round))
                        .rotationEffect(.degrees(-90 + (fatPercent + carbPercent) * 360))
                    
                    VStack(spacing: 4) {
                        Text("\(Int(totalCalories))")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        
                        Text("calories")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .frame(width: 140, height: 140)
                
                // Legend
                HStack(spacing: 24) {
                    macroLegend("Fat", fatPercent, "MacroFat")
                    macroLegend("Carbs", carbPercent, "MacroCarbs")
                    macroLegend("Protein", proteinPercent, "MacroProtein")
                }
            }
        }
    }
    
    func macroLegend(_ name: String, _ percent: Double, _ color: String) -> some View {
        VStack(spacing: 4) {
            Circle()
                .fill(Color(color))
                .frame(width: 10, height: 10)
            
            Text(name)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            
            Text("\(Int(percent * 100))%")
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }
}

private extension DetailedNutritionView {
    
    func nutrientCard<Content: View>(
        title: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {

        ElevatedCard(padding: 0, cornerRadius: 20) {

            VStack(alignment: .leading, spacing: 0) {
                // Nutrition Facts Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nutrition Facts")
                        .font(.system(size: 36, weight: .black))
                        .foregroundStyle(Color.textPrimary)
                    
                    // Heavy divider under header
                    Rectangle()
                        .fill(Color.textPrimary)
                        .frame(height: 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                VStack(spacing: 0) {
                    content()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    func nutrientRow(
        _ label: String,
        _ value: Double,
        _ unit: String,
        bold: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            // Label
            Text(label)
                .font(.system(size: 14))
                .fontWeight(bold ? .black : .regular)
            
            Spacer()
            
            // Amount (right-aligned in middle) - more prominent
            Text(formatValue(value) + unit)
                .font(.system(size: 14))
                .fontWeight(bold ? .bold : .regular)
                .frame(minWidth: 60, alignment: .trailing)
            
            // % DV aligned to right - lighter weight (or empty spacer to maintain alignment)
            if let percent = percentDV(value, for: label) {
                Text("\(percent)%")
                    .font(.system(size: 13))
                    .fontWeight(.light)
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 50, alignment: .trailing)
            } else {
                // Empty spacer to maintain alignment when no %DV
                Text("")
                    .frame(width: 50)
            }
        }
        .padding(.vertical, 2)
    }
    
    func formatValue(_ value: Double) -> String {
        if value >= 100 {
            return "\(Int(value))"
        } else if value >= 10 {
            return String(format: "%.1f", value)
        } else {
            return String(format: "%.2f", value)
        }
    }
    
    var nutritionFactsRows: some View {
        VStack(spacing: 0) {
            // Amount per serving label
            Text("Amount per serving")
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            
            // Calories - large and bold
            HStack(alignment: .firstTextBaseline) {
                Text("Calories")
                    .font(.system(size: 32, weight: .black))
                Spacer()
                Text("\(Int(totalCalories))")
                    .font(.system(size: 44, weight: .black))
            }
            .padding(.vertical, 4)
            
            // Heavy divider after calories
            Rectangle()
                .fill(Color.textPrimary)
                .frame(height: 6)
                .padding(.vertical, 4)
            
            // % Daily Value header
            HStack {
                Spacer()
                Text("% Daily Value*")
                    .font(.system(size: 12, weight: .bold))
            }
            .padding(.bottom, 4)
            
            // Thin divider
            Rectangle()
                .fill(Color.textPrimary)
                .frame(height: 1)
            
            // Total Fat
            nutrientRow("Total Fat", totalFat, "g", bold: true)
            thinDivider()
            
            // Saturated Fat (indented)
            if sumFromLog(\.saturatedFatAtLogTime) > 0 {
                indentedNutrientRow("Saturated Fat", sumFromLog(\.saturatedFatAtLogTime), "g")
                thinDivider()
            }

            // Trans Fat (indented)
            if sumFromLog(\.transFatAtLogTime) > 0 {
                indentedNutrientRow("Trans Fat", sumFromLog(\.transFatAtLogTime), "g")
                thinDivider()
            }

            // Monounsaturated Fat (indented)
            if sumFromLog(\.monounsaturatedFatAtLogTime) > 0 {
                indentedNutrientRow("Monounsaturated Fat", sumFromLog(\.monounsaturatedFatAtLogTime), "g")
                thinDivider()
            }

            // Polyunsaturated Fat (indented)
            if sumFromLog(\.polyunsaturatedFatAtLogTime) > 0 {
                indentedNutrientRow("Polyunsaturated Fat", sumFromLog(\.polyunsaturatedFatAtLogTime), "g")
                thinDivider()
            }

            // Cholesterol
            if sumFromLog(\.cholesterolAtLogTime) > 0 {
                nutrientRow("Cholesterol", sumFromLog(\.cholesterolAtLogTime), "mg", bold: true)
                thinDivider()
            }

            // Sodium
            if sumFromLog(\.sodiumAtLogTime) > 0 {
                nutrientRow("Sodium", sumFromLog(\.sodiumAtLogTime), "mg", bold: true)
                thinDivider()
            }

            // Total Carbohydrate
            nutrientRow("Total Carbohydrate", totalCarbs, "g", bold: true)
            thinDivider()

            // Fiber (indented)
            if sumFromLog(\.fiberAtLogTime) > 0 {
                indentedNutrientRow("Dietary Fiber", sumFromLog(\.fiberAtLogTime), "g")
                thinDivider()
            }

            // Sugar (indented)
            if sumFromLog(\.sugarAtLogTime) > 0 {
                indentedNutrientRow("Total Sugars", sumFromLog(\.sugarAtLogTime), "g")
                thinDivider()
            }
            
            // Protein
            nutrientRow("Protein", totalProtein, "g", bold: true)
            
            // Heavy divider before vitamins/minerals
            Rectangle()
                .fill(Color.textPrimary)
                .frame(height: 8)
                .padding(.vertical, 4)
            
            // Vitamins and Minerals section
            VStack(spacing: 0) {
                if sumFromLog(\.vitaminDAtLogTime) > 0 {
                    nutrientRow("Vitamin D", sumFromLog(\.vitaminDAtLogTime), "mcg")
                    thinDivider()
                }

                if sumFromLog(\.calciumAtLogTime) > 0 {
                    nutrientRow("Calcium", sumFromLog(\.calciumAtLogTime), "mg")
                    thinDivider()
                }

                if sumFromLog(\.ironAtLogTime) > 0 {
                    nutrientRow("Iron", sumFromLog(\.ironAtLogTime), "mg")
                    thinDivider()
                }

                if sumFromLog(\.potassiumAtLogTime) > 0 {
                    nutrientRow("Potassium", sumFromLog(\.potassiumAtLogTime), "mg")
                    thinDivider()
                }

                if sumFromLog(\.vitaminAAtLogTime) > 0 {
                    nutrientRow("Vitamin A", sumFromLog(\.vitaminAAtLogTime), "mcg")
                    thinDivider()
                }

                if sumFromLog(\.vitaminCAtLogTime) > 0 {
                    nutrientRow("Vitamin C", sumFromLog(\.vitaminCAtLogTime), "mg")
                    thinDivider()
                }

                if sumFromLog(\.vitaminEAtLogTime) > 0 {
                    nutrientRow("Vitamin E", sumFromLog(\.vitaminEAtLogTime), "mg")
                    thinDivider()
                }

                if sumFromLog(\.vitaminKAtLogTime) > 0 {
                    nutrientRow("Vitamin K", sumFromLog(\.vitaminKAtLogTime), "mcg")
                    thinDivider()
                }

                if sumFromLog(\.vitaminB6AtLogTime) > 0 {
                    nutrientRow("Vitamin B6", sumFromLog(\.vitaminB6AtLogTime), "mg")
                    thinDivider()
                }

                if sumFromLog(\.vitaminB12AtLogTime) > 0 {
                    nutrientRow("Vitamin B12", sumFromLog(\.vitaminB12AtLogTime), "mcg")
                    thinDivider()
                }

                if sumFromLog(\.folateAtLogTime) > 0 {
                    nutrientRow("Folate", sumFromLog(\.folateAtLogTime), "mcg")
                    thinDivider()
                }

                if sumFromLog(\.cholineAtLogTime) > 0 {
                    nutrientRow("Choline", sumFromLog(\.cholineAtLogTime), "mg")
                    thinDivider()
                }

                if sumFromLog(\.magnesiumAtLogTime) > 0 {
                    nutrientRow("Magnesium", sumFromLog(\.magnesiumAtLogTime), "mg")
                    thinDivider()
                }

                if sumFromLog(\.zincAtLogTime) > 0 {
                    nutrientRow("Zinc", sumFromLog(\.zincAtLogTime), "mg")
                    thinDivider()
                }

                if sumFromLog(\.caffeineAtLogTime) > 0 {
                    nutrientRow("Caffeine", sumFromLog(\.caffeineAtLogTime), "mg")
                    thinDivider()
                }

            }
            
            // Remove last divider
            Rectangle()
                .fill(Color.clear)
                .frame(height: 0)
            
            // Heavy divider at bottom
            Rectangle()
                .fill(Color.textPrimary)
                .frame(height: 4)
                .padding(.top, 4)
            
            // FDA Disclaimer
            Text("* The % Daily Value (DV) tells you how much a nutrient in a serving of food contributes to a daily diet. 2,000 calories a day is used for general nutrition advice.")
                .font(.system(size: 9))
                .foregroundStyle(Color.textSecondary)
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    // Helper for thin dividers
    func thinDivider() -> some View {
        Rectangle()
            .fill(Color.textPrimary)
            .frame(height: 1)
    }
    
    // Helper for indented rows (like saturated fat under total fat)
    func indentedNutrientRow(
        _ label: String,
        _ value: Double,
        _ unit: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            // Indented label
            Text(label)
                .font(.system(size: 14))
                .padding(.leading, 20)
            
            Spacer()
            
            // Amount (right-aligned in middle) - more prominent
            Text(formatValue(value) + unit)
                .font(.system(size: 14))
                .frame(minWidth: 60, alignment: .trailing)
            
            // % DV aligned to right - lighter weight (or empty spacer to maintain alignment)
            if let percent = percentDV(value, for: label) {
                Text("\(percent)%")
                    .font(.system(size: 13))
                    .fontWeight(.light)
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 50, alignment: .trailing)
            } else {
                // Empty spacer to maintain alignment when no %DV
                Text("")
                    .frame(width: 50)
            }
        }
        .padding(.vertical, 2)
    }
}

