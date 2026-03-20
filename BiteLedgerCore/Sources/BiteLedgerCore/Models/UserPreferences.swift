//
//  UserPreferences.swift
//  BiteLedger
//

import Foundation
import SwiftData

@Model
public class UserPreferences {
    public var pinnedNutrient: String? // Nutrient raw value for 5th dashboard slot
    public var goalsData: Data? // Encoded [String: NutrientGoal]
    public var showMacroBalanceTile: Bool? // Show macro balance tile on dashboard (nil = true)

    // Streak cache — recomputed once per calendar day, then served from here
    public var cachedStreak: Int = 0
    public var streakCachedDate: Date? = nil

    // E-1: Startup backfill completion flags (nil = not yet run; true = done)
    public var hasBackfilledServingUnits: Bool?
    public var hasBackfilledStaleLogs: Bool?
    public var hasBackfilledServingAmounts: Bool?
    public var hasNormalizedPerServingFoods: Bool?
    public var hasBackfilledGramAmounts: Bool?
    public var hasFixedLoseItGramUnits: Bool?

    // NEW-1: Weekly share card — tracks which ISO week the last card was generated
    public var lastShareCardGeneratedWeek: Date?

    public init(pinnedNutrient: String? = nil, goalsData: Data? = nil, showMacroBalanceTile: Bool? = nil) {
        self.pinnedNutrient = pinnedNutrient
        self.goalsData = goalsData
        self.showMacroBalanceTile = showMacroBalanceTile
    }
    
    // Helper computed property for goals
    public var goals: [String: NutrientGoal] {
        get {
            guard let data = goalsData else { return [:] }
            return (try? JSONDecoder().decode([String: NutrientGoal].self, from: data)) ?? [:]
        }
        set {
            goalsData = try? JSONEncoder().encode(newValue)
        }
    }
    
    // Get all nutrients that have goals set
    public var activeGoalNutrients: [Nutrient] {
        goals.keys.compactMap { Nutrient(rawValue: $0) }
    }
}

// Goal configuration for a nutrient
public struct NutrientGoal: Codable {
    public var targetValue: Double
    public var goalType: GoalType
    public var rangeMax: Double? // For range goals

    public init(targetValue: Double, goalType: GoalType, rangeMax: Double? = nil) {
        self.targetValue = targetValue
        self.goalType = goalType
        self.rangeMax = rangeMax
    }
}

public enum GoalType: String, Codable, CaseIterable {
    case minimum = "At Least" // e.g., protein, fiber
    case maximum = "No More Than" // e.g., sodium, sugar
    case range = "Target Range" // e.g., calories
}

// Comprehensive nutrient enum
public enum Nutrient: String, CaseIterable, Codable, Identifiable {
    // Macronutrients (always shown on dashboard)
    case calories = "Calories"
    case protein = "Protein"
    case carbs = "Carbs"
    case fat = "Fat"
    
    // Additional macros
    case fiber = "Fiber"
    case sugar = "Sugar"
    case saturatedFat = "Saturated Fat"
    case transFat = "Trans Fat"
    case monounsaturatedFat = "Monounsaturated Fat"
    case polyunsaturatedFat = "Polyunsaturated Fat"
    case cholesterol = "Cholesterol"
    
    // Minerals
    case sodium = "Sodium"
    case potassium = "Potassium"
    case calcium = "Calcium"
    case iron = "Iron"
    case magnesium = "Magnesium"
    case zinc = "Zinc"
    
    // Vitamins
    case vitaminA = "Vitamin A"
    case vitaminC = "Vitamin C"
    case vitaminD = "Vitamin D"
    case vitaminE = "Vitamin E"
    case vitaminK = "Vitamin K"
    case vitaminB6 = "Vitamin B6"
    case vitaminB12 = "Vitamin B12"
    case folate = "Folate"
    case choline = "Choline"
    
    // Special
    case caffeine = "Caffeine"
    
    public var id: String { rawValue }
    
    public var unit: String {
        switch self {
        case .calories:
            return "cal"
        case .sodium, .potassium, .calcium, .vitaminC, .vitaminD, .iron, .magnesium, .zinc, .caffeine, .cholesterol:
            return "mg"
        case .vitaminA, .vitaminK, .folate, .vitaminB12:
            return "mcg"
        case .vitaminE, .vitaminB6, .choline:
            return "mg"
        default:
            return "g"
        }
    }
    
    public var category: NutrientCategory {
        switch self {
        case .calories, .protein, .carbs, .fat:
            return .macros
        case .fiber, .sugar, .saturatedFat, .transFat, .monounsaturatedFat, .polyunsaturatedFat, .cholesterol:
            return .additionalMacros
        case .sodium, .potassium, .calcium, .iron, .magnesium, .zinc:
            return .minerals
        case .vitaminA, .vitaminC, .vitaminD, .vitaminE, .vitaminK, .vitaminB6, .vitaminB12, .folate, .choline:
            return .vitamins
        case .caffeine:
            return .special
        }
    }
    
    // E-3: Default goal value for this nutrient (single source of truth — no duplication in views)
    public var defaultGoalValue: Double {
        switch self {
        case .calories: return 2000
        case .protein: return 150
        case .carbs: return 250
        case .fat: return 65
        case .fiber: return 30
        case .sugar: return 50
        case .sodium: return 2300
        case .saturatedFat: return 20
        case .cholesterol: return 300
        case .potassium: return 3500
        case .calcium: return 1000
        case .iron: return 18
        case .vitaminC: return 90
        case .vitaminD: return 20
        case .caffeine: return 400
        default: return 100
        }
    }

    // Default goal type for this nutrient
    public var defaultGoalType: GoalType {
        switch self {
        case .protein, .fiber, .vitaminA, .vitaminC, .vitaminD, .calcium, .iron, .potassium:
            return .minimum
        case .sodium, .sugar, .saturatedFat, .transFat, .cholesterol, .caffeine:
            return .maximum
        case .calories, .carbs:
            return .range
        default:
            return .maximum
        }
    }
}

public enum NutrientCategory {
    case macros
    case additionalMacros
    case minerals
    case vitamins
    case special
}

// Helper to get pinnable nutrients (excludes the big 4)
extension Nutrient {
    public static var pinnableNutrients: [Nutrient] {
        allCases.filter { ![$0].contains(where: { [.calories, .protein, .carbs, .fat].contains($0) }) }
    }
}
