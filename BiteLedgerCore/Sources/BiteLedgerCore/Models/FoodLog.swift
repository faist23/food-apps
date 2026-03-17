//
//  FoodLog.swift
//  BiteLedger
//
//  Created by Craig Faist on 2/16/26.
//

import SwiftData
import Foundation

// MARK: - FoodLog

@Model
public final class FoodLog {

    // MARK: Identity
    // CloudKit requires all stored properties to be optional or have default values.
    public var id: UUID = UUID()
    public var timestamp: Date = Date()
    public var mealType: MealType = MealType.breakfast

    // MARK: Quantity

    /// Number of servings logged. e.g., 1.5 means 1.5 × the selected ServingSize.
    /// DEPRECATED: Use gramAmount for all new nutrition math. Kept for migration backfill.
    public var quantity: Double = 1

    /// Grams consumed. This is the canonical amount stored in every log entry.
    /// Set once by FoodLog.create() and never recalculated.
    /// Formula: gramAmount = servingSize.gramWeight × quantity (or density estimate when gramWeight is nil)
    public var gramAmount: Double = 0

    /// The numeric amount the user typed in the serving picker (e.g. 3 for "3 tbsp").
    /// Stored for display only — nutrition is always calculated from gramAmount.
    public var loggedAmount: Double? = nil

    /// The unit string the user selected (e.g. "tbsp", "cup", "oz").
    /// Stored for display only — nutrition is always calculated from gramAmount.
    public var loggedUnit: String? = nil

    // MARK: Relationships
    /// The food that was eaten. Nullified (not deleted) if food is removed.
    public var foodItem: FoodItem?

    /// The specific serving size used. nil means the food's default serving was used.
    public var servingSize: ServingSize?

    // MARK: Frozen Nutrition — SET ONCE AT LOG TIME, NEVER RECALCULATED
    //
    // These values are calculated by NutritionCalculator at the moment the user
    // confirms the log entry and are NEVER updated afterward.
    //
    // This ensures that editing a FoodItem later does not rewrite log history.
    // Always read these fields when displaying a logged entry's nutrition.
    // Never call NutritionCalculator on a FoodLog that already exists.

    public var caloriesAtLogTime: Double = 0
    public var proteinAtLogTime: Double = 0
    public var carbsAtLogTime: Double = 0
    public var fatAtLogTime: Double = 0
    public var fiberAtLogTime: Double?
    public var sodiumAtLogTime: Double?
    public var sugarAtLogTime: Double?
    public var saturatedFatAtLogTime: Double?
    public var transFatAtLogTime: Double?
    public var monounsaturatedFatAtLogTime: Double?
    public var polyunsaturatedFatAtLogTime: Double?
    public var cholesterolAtLogTime: Double?
    public var potassiumAtLogTime: Double?
    public var calciumAtLogTime: Double?
    public var ironAtLogTime: Double?
    public var magnesiumAtLogTime: Double?
    public var zincAtLogTime: Double?
    public var vitaminAAtLogTime: Double?
    public var vitaminCAtLogTime: Double?
    public var vitaminDAtLogTime: Double?
    public var vitaminEAtLogTime: Double?
    public var vitaminKAtLogTime: Double?
    public var vitaminB6AtLogTime: Double?
    public var vitaminB12AtLogTime: Double?
    public var folateAtLogTime: Double?
    public var cholineAtLogTime: Double?
    public var caffeineAtLogTime: Double?

    // MARK: Init
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        mealType: MealType,
        quantity: Double,
        gramAmount: Double = 0,
        loggedAmount: Double? = nil,
        loggedUnit: String? = nil,
        foodItem: FoodItem? = nil,
        servingSize: ServingSize? = nil,
        caloriesAtLogTime: Double,
        proteinAtLogTime: Double,
        carbsAtLogTime: Double,
        fatAtLogTime: Double,
        fiberAtLogTime: Double? = nil,
        sodiumAtLogTime: Double? = nil,
        sugarAtLogTime: Double? = nil,
        saturatedFatAtLogTime: Double? = nil,
        transFatAtLogTime: Double? = nil,
        monounsaturatedFatAtLogTime: Double? = nil,
        polyunsaturatedFatAtLogTime: Double? = nil,
        cholesterolAtLogTime: Double? = nil,
        potassiumAtLogTime: Double? = nil,
        calciumAtLogTime: Double? = nil,
        ironAtLogTime: Double? = nil,
        magnesiumAtLogTime: Double? = nil,
        zincAtLogTime: Double? = nil,
        vitaminAAtLogTime: Double? = nil,
        vitaminCAtLogTime: Double? = nil,
        vitaminDAtLogTime: Double? = nil,
        vitaminEAtLogTime: Double? = nil,
        vitaminKAtLogTime: Double? = nil,
        vitaminB6AtLogTime: Double? = nil,
        vitaminB12AtLogTime: Double? = nil,
        folateAtLogTime: Double? = nil,
        cholineAtLogTime: Double? = nil,
        caffeineAtLogTime: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.mealType = mealType
        self.quantity = quantity
        self.gramAmount = gramAmount
        self.loggedAmount = loggedAmount
        self.loggedUnit = loggedUnit
        self.foodItem = foodItem
        self.servingSize = servingSize
        self.caloriesAtLogTime = caloriesAtLogTime
        self.proteinAtLogTime = proteinAtLogTime
        self.carbsAtLogTime = carbsAtLogTime
        self.fatAtLogTime = fatAtLogTime
        self.fiberAtLogTime = fiberAtLogTime
        self.sodiumAtLogTime = sodiumAtLogTime
        self.sugarAtLogTime = sugarAtLogTime
        self.saturatedFatAtLogTime = saturatedFatAtLogTime
        self.transFatAtLogTime = transFatAtLogTime
        self.monounsaturatedFatAtLogTime = monounsaturatedFatAtLogTime
        self.polyunsaturatedFatAtLogTime = polyunsaturatedFatAtLogTime
        self.cholesterolAtLogTime = cholesterolAtLogTime
        self.potassiumAtLogTime = potassiumAtLogTime
        self.calciumAtLogTime = calciumAtLogTime
        self.ironAtLogTime = ironAtLogTime
        self.magnesiumAtLogTime = magnesiumAtLogTime
        self.zincAtLogTime = zincAtLogTime
        self.vitaminAAtLogTime = vitaminAAtLogTime
        self.vitaminCAtLogTime = vitaminCAtLogTime
        self.vitaminDAtLogTime = vitaminDAtLogTime
        self.vitaminEAtLogTime = vitaminEAtLogTime
        self.vitaminKAtLogTime = vitaminKAtLogTime
        self.vitaminB6AtLogTime = vitaminB6AtLogTime
        self.vitaminB12AtLogTime = vitaminB12AtLogTime
        self.folateAtLogTime = folateAtLogTime
        self.cholineAtLogTime = cholineAtLogTime
        self.caffeineAtLogTime = caffeineAtLogTime
    }

    // MARK: Computed Display Helpers

    public var servingLabel: String {
        servingSize?.label ?? foodItem?.defaultServing?.label ?? "1 serving"
    }

    public var quantityDescription: String {
        // Format a Double for display: integer if whole, otherwise up to 2 decimal places,
        // no trailing zeros, no scientific notation.
        func fmt(_ v: Double) -> String {
            if v.truncatingRemainder(dividingBy: 1) == 0 { return String(Int(v)) }
            let s = String(format: "%.2f", v)
            return s.replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
        }

        // If label already includes a number (e.g. "1 cup (42g)", "8 fl oz"), scale it.
        // e.g. quantity=1.5, label="1 cup (42g)" → "1.5 cup (42g)"
        if let firstChar = servingLabel.first, firstChar.isNumber {
            if quantity == 1.0 {
                return servingLabel
            } else if let spaceIdx = servingLabel.firstIndex(of: " "),
                      let labelAmount = Double(servingLabel[servingLabel.startIndex..<spaceIdx]) {
                let unitPart = String(servingLabel[servingLabel.index(after: spaceIdx)...])
                return "\(fmt(labelAmount * quantity)) \(unitPart)"
            } else {
                return "\(fmt(quantity)) \(servingLabel)"
            }
        }

        // Bare unit or named serving (e.g. "cup", "g", "fl oz", "slice").
        if quantity == 1.0 { return servingLabel }
        return "\(fmt(quantity)) \(servingLabel)"
    }
}

// MARK: - FoodLog Factory

extension FoodLog {
    /// Creates a FoodLog and freezes nutrition at creation time.
    /// This is the ONLY way a FoodLog should be created.
    ///
    /// - Parameters:
    ///   - loggedAmount: The numeric amount the user typed (e.g. 3 for "3 tbsp"). Stored for display.
    ///   - loggedUnit:   The unit the user selected (e.g. "tbsp"). Stored for display.
    public static func create(
        mealType: MealType,
        quantity: Double,
        food: FoodItem,
        serving: ServingSize?,
        timestamp: Date = Date(),
        loggedAmount: Double? = nil,
        loggedUnit: String? = nil
    ) -> FoodLog {
        // Resolve gram amount via the calculator's canonical resolution logic.
        let gramAmount = NutritionCalculator.resolveGramAmount(food: food, serving: serving, quantity: quantity)

        // Freeze nutrition using the single gram-based formula.
        let nutrition = NutritionCalculator.calculate(food: food, gramAmount: gramAmount)

        let resolvedServing = serving ?? food.defaultServing

        return FoodLog(
            timestamp: timestamp,
            mealType: mealType,
            quantity: quantity,
            gramAmount: gramAmount,
            loggedAmount: loggedAmount ?? quantity,
            loggedUnit: loggedUnit ?? resolvedServing?.unit,
            foodItem: food,
            servingSize: serving,
            caloriesAtLogTime: nutrition.calories,
            proteinAtLogTime: nutrition.protein,
            carbsAtLogTime: nutrition.carbs,
            fatAtLogTime: nutrition.fat,
            fiberAtLogTime: nutrition.fiber,
            sodiumAtLogTime: nutrition.sodium,
            sugarAtLogTime: nutrition.sugar,
            saturatedFatAtLogTime: nutrition.saturatedFat,
            transFatAtLogTime: nutrition.transFat,
            monounsaturatedFatAtLogTime: nutrition.monounsaturatedFat,
            polyunsaturatedFatAtLogTime: nutrition.polyunsaturatedFat,
            cholesterolAtLogTime: nutrition.cholesterol,
            potassiumAtLogTime: nutrition.potassium,
            calciumAtLogTime: nutrition.calcium,
            ironAtLogTime: nutrition.iron,
            magnesiumAtLogTime: nutrition.magnesium,
            zincAtLogTime: nutrition.zinc,
            vitaminAAtLogTime: nutrition.vitaminA,
            vitaminCAtLogTime: nutrition.vitaminC,
            vitaminDAtLogTime: nutrition.vitaminD,
            vitaminEAtLogTime: nutrition.vitaminE,
            vitaminKAtLogTime: nutrition.vitaminK,
            vitaminB6AtLogTime: nutrition.vitaminB6,
            vitaminB12AtLogTime: nutrition.vitaminB12,
            folateAtLogTime: nutrition.folate,
            cholineAtLogTime: nutrition.choline,
            caffeineAtLogTime: nutrition.caffeine
        )
    }
}
