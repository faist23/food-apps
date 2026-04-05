//
//  NutritionDashboard.swift
//  BiteLedger
//

import SwiftUI
import BiteLedgerCore

struct NutritionDashboard: View {
    let logs: [FoodLog]
    let preferences: UserPreferences?
    let onTap: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Top row: Calories + Macros (optional) + Protein
            HStack(spacing: 12) {
                NutritionTile(
                    nutrient: .calories,
                    value: totalCalories,
                    goal: goalFor(.calories),
                    showProgressBar: hasGoal(.calories)
                )
                
                if showMacroBalance {
                    MacroBalanceTile(
                        proteinPercent: proteinPercent,
                        carbsPercent: carbsPercent,
                        fatPercent: fatPercent
                    )
                }
                
                NutritionTile(
                    nutrient: .protein,
                    value: totalProtein,
                    goal: goalFor(.protein),
                    showProgressBar: hasGoal(.protein)
                )
            }
            
            // Bottom row: Carbs + Fat + Custom
            HStack(spacing: 12) {
                NutritionTile(
                    nutrient: .carbs,
                    value: totalCarbs,
                    goal: goalFor(.carbs),
                    showProgressBar: hasGoal(.carbs)
                )
                
                NutritionTile(
                    nutrient: .fat,
                    value: totalFat,
                    goal: goalFor(.fat),
                    showProgressBar: hasGoal(.fat)
                )
                
                if let pinnedNutrient = pinnedNutrient {
                    NutritionTile(
                        nutrient: pinnedNutrient,
                        value: valueFor(pinnedNutrient),
                        goal: goalFor(pinnedNutrient),
                        showProgressBar: hasGoal(pinnedNutrient)
                    )
                }
            }
        }
        .onTapGesture {
            onTap()
        }
    }
    
    // MARK: - Computed Properties
    
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
    
    // Macro percentages (for macro balance tile)
    private var fatCalories: Double { totalFat * 9 }
    private var carbCalories: Double { totalCarbs * 4 }
    private var proteinCalories: Double { totalProtein * 4 }
    
    private var totalMacroCalories: Double {
        fatCalories + carbCalories + proteinCalories
    }
    
    private var fatPercent: Double {
        totalMacroCalories == 0 ? 0 : fatCalories / totalMacroCalories
    }
    
    private var carbsPercent: Double {
        totalMacroCalories == 0 ? 0 : carbCalories / totalMacroCalories
    }
    
    private var proteinPercent: Double {
        totalMacroCalories == 0 ? 0 : proteinCalories / totalMacroCalories
    }
    
    private var pinnedNutrient: Nutrient? {
        guard let rawValue = preferences?.pinnedNutrient else { return nil }
        return Nutrient(rawValue: rawValue)
    }
    
    private func valueFor(_ nutrient: Nutrient) -> Double {
        let _: Double
        
        switch nutrient {
        case .calories: return totalCalories
        case .protein: return totalProtein
        case .carbs: return totalCarbs
        case .fat: return totalFat
        case .fiber: return logs.reduce(0) { $0 + ($1.fiberAtLogTime ?? 0) }
        case .sugar: return logs.reduce(0) { $0 + ($1.sugarAtLogTime ?? 0) }
        case .saturatedFat: return logs.reduce(0) { $0 + ($1.saturatedFatAtLogTime ?? 0) }
        case .transFat: return logs.reduce(0) { $0 + ($1.transFatAtLogTime ?? 0) }
        case .monounsaturatedFat: return logs.reduce(0) { $0 + ($1.monounsaturatedFatAtLogTime ?? 0) }
        case .polyunsaturatedFat: return logs.reduce(0) { $0 + ($1.polyunsaturatedFatAtLogTime ?? 0) }
        
        // Nutrients stored in their natural units (mg or mcg) - no conversion needed
        case .sodium: return logs.reduce(0) { $0 + ($1.sodiumAtLogTime ?? 0) }
        case .potassium: return logs.reduce(0) { $0 + ($1.potassiumAtLogTime ?? 0) }
        case .calcium: return logs.reduce(0) { $0 + ($1.calciumAtLogTime ?? 0) }
        case .iron: return logs.reduce(0) { $0 + ($1.ironAtLogTime ?? 0) }
        case .magnesium: return logs.reduce(0) { $0 + ($1.magnesiumAtLogTime ?? 0) }
        case .zinc: return logs.reduce(0) { $0 + ($1.zincAtLogTime ?? 0) }
        case .vitaminC: return logs.reduce(0) { $0 + ($1.vitaminCAtLogTime ?? 0) }
        case .vitaminD: return logs.reduce(0) { $0 + ($1.vitaminDAtLogTime ?? 0) }
        case .vitaminE: return logs.reduce(0) { $0 + ($1.vitaminEAtLogTime ?? 0) }
        case .vitaminB6: return logs.reduce(0) { $0 + ($1.vitaminB6AtLogTime ?? 0) }
        case .choline: return logs.reduce(0) { $0 + ($1.cholineAtLogTime ?? 0) }
        case .caffeine: return logs.reduce(0) { $0 + ($1.caffeineAtLogTime ?? 0) }
        case .cholesterol: return logs.reduce(0) { $0 + ($1.cholesterolAtLogTime ?? 0) }

        // Nutrients stored in mcg - no conversion needed
        case .vitaminA: return logs.reduce(0) { $0 + ($1.vitaminAAtLogTime ?? 0) }
        case .vitaminK: return logs.reduce(0) { $0 + ($1.vitaminKAtLogTime ?? 0) }
        case .vitaminB12: return logs.reduce(0) { $0 + ($1.vitaminB12AtLogTime ?? 0) }
        case .folate: return logs.reduce(0) { $0 + ($1.folateAtLogTime ?? 0) }
        }
    }
    
    private func goalFor(_ nutrient: Nutrient) -> NutrientGoal? {
        guard let preferences = preferences else { return nil }
        return preferences.goals[nutrient.rawValue]
    }
    
    private func hasGoal(_ nutrient: Nutrient) -> Bool {
        preferences?.goals[nutrient.rawValue] != nil
    }
    
    private var showMacroBalance: Bool {
        preferences?.showMacroBalanceTile ?? true
    }
}

// MARK: - Macro Balance Tile

struct MacroBalanceTile: View {
    let proteinPercent: Double
    let carbsPercent: Double
    let fatPercent: Double
    
    var body: some View {
        VStack(spacing: 5) {
            // Macro percentages (no header - keeps tile compact)
            VStack(alignment: .leading, spacing: 4) {
                macroRow("Protein", proteinPercent, "MacroProtein")
                macroRow("Carbs", carbsPercent, "MacroCarbs")
                macroRow("Fat", fatPercent, "MacroFat")
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.dividerSubtle, lineWidth: 1)
        )
        // D-4: VoiceOver — synthesize macro balance summary
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(macroBalanceAccessibilityLabel)
    }

    private var macroBalanceAccessibilityLabel: String {
        "Macro balance: \(Int(proteinPercent * 100))% protein, \(Int(carbsPercent * 100))% carbs, \(Int(fatPercent * 100))% fat"
    }

    private func macroRow(_ name: String, _ percent: Double, _ color: String) -> some View {
        HStack(spacing: 3) {
            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(Color(color))
            
            Spacer()
            
            Text("\(Int(percent * 100))%")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(color))
        }
    }
}

struct NutritionTile: View {
    let nutrient: Nutrient
    let value: Double
    let goal: NutrientGoal?
    let showProgressBar: Bool
    
    var body: some View {
        VStack(spacing: 6) {
            // Label
            Text(nutrient.rawValue.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
            
            // Value
            if nutrient == .calories {
                // Don't show unit for calories since label already says "CALORIES"
                Text("\(formattedValue)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.textPrimary)
            } else {
                // Show unit for other nutrients (e.g., "125 g" for protein)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(formattedValue)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.textPrimary)
                    
                    Text(nutrient.unit)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            
            // Progress bar (only if this is the tracked nutrient with a goal)
            if showProgressBar, let goal = goal {
                progressBar(for: goal)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.dividerSubtle, lineWidth: 1)
        )
        // D-4: VoiceOver — synthesize meaningful label from nutrient + value + goal
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(nutrientAccessibilityLabel)
    }

    private var nutrientAccessibilityLabel: String {
        let nutrientName = nutrient.rawValue
        let valueStr: String
        if nutrient == .calories {
            valueStr = "\(Int(value)) calories"
        } else {
            valueStr = "\(formattedValue) \(nutrient.unit) \(nutrientName)"
        }
        guard let goal else { return valueStr }
        let pct = goal.targetValue > 0 ? Int((value / goal.targetValue) * 100) : 0
        switch goal.goalType {
        case .minimum:
            return "\(valueStr) of \(Int(goal.targetValue)) \(nutrient.unit) goal — \(pct)% complete"
        case .maximum:
            return "\(valueStr) — \(pct)% of \(Int(goal.targetValue)) \(nutrient.unit) limit"
        case .range:
            let max = goal.rangeMax ?? goal.targetValue
            return "\(valueStr) — target \(Int(goal.targetValue))–\(Int(max)) \(nutrient.unit)"
        }
    }

    private var formattedValue: String {
        if value >= 100 {
            return "\(Int(value))"
        } else if value >= 10 {
            return String(format: "%.1f", value)
        } else {
            return String(format: "%.2f", value)
        }
    }
    
    @ViewBuilder
    private func progressBar(for goal: NutrientGoal) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.dividerSubtle)
                    .frame(height: 4)
                
                // Progress
                RoundedRectangle(cornerRadius: 2)
                    .fill(progressColor(for: goal))
                    .frame(width: progressWidth(geometry: geometry, goal: goal), height: 4)
            }
        }
        .frame(height: 4)
    }
    
    private func progressWidth(geometry: GeometryProxy, goal: NutrientGoal) -> CGFloat {
        let percentage: Double
        
        switch goal.goalType {
        case .minimum, .maximum:
            // For min/max, show progress toward the single target
            percentage = value / goal.targetValue
            
        case .range:
            // For range, show progress toward the midpoint of the range
            if let rangeMax = goal.rangeMax {
                let midpoint = (goal.targetValue + rangeMax) / 2
                percentage = value / midpoint
            } else {
                percentage = value / goal.targetValue
            }
        }
        
        return min(geometry.size.width, geometry.size.width * CGFloat(percentage))
    }
    
    private func progressColor(for goal: NutrientGoal) -> Color {
        let percentage = value / goal.targetValue
        
        switch goal.goalType {
        case .minimum:
            // Green when reaching goal, stays green if over
            return percentage >= 1.0 ? .green : Color.brandPrimary
            
        case .maximum:
            // Green → Yellow → Orange → Red as approaching/exceeding limit
            if percentage < 0.7 {
                return .green
            } else if percentage < 0.9 {
                return .yellow
            } else if percentage < 1.0 {
                return .orange
            } else {
                return .orange // Stay orange, not red (less anxiety)
            }
            
        case .range:
            // Range has both min (targetValue) and max (rangeMax)
            // Green when in range, yellow when slightly out, orange when way out
            guard let rangeMax = goal.rangeMax else {
                // Fallback if rangeMax not set
                return percentage >= 1.0 ? .green : .yellow
            }
            
            let rangeMin = goal.targetValue
            
            if value >= rangeMin && value <= rangeMax {
                // Perfect! In range
                return .green
            } else if value < rangeMin {
                // Under target minimum
                let underPercentage = value / rangeMin
                if underPercentage >= 0.8 {
                    return .yellow  // Close to min
                } else {
                    return .orange  // Way under min
                }
            } else {
                // Over target maximum
                let overPercentage = value / rangeMax
                if overPercentage <= 1.2 {
                    return .yellow  // Slightly over max
                } else {
                    return .orange  // Way over max
                }
            }
        }
    }
}
