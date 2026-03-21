//
//  BiteLedgerTests.swift
//  BiteLedgerTests
//

import XCTest
import BiteLedgerCore
@testable import BiteLedger

// MARK: - NutritionCalculator Tests

final class NutritionCalculatorTests: XCTestCase {

    // MARK: - Helpers

    private func makeFood(
        calories: Double, protein: Double = 0, carbs: Double = 0, fat: Double = 0,
        fiber: Double? = nil, sodium: Double? = nil
    ) -> FoodItem {
        let food = FoodItem(
            name: "Test Food", source: "test", nutritionMode: .per100g,
            calories: calories, protein: protein, carbs: carbs, fat: fat,
            fiber: fiber, sodium: sodium
        )
        return food
    }

    private func makeLog(
        calories: Double, protein: Double = 0, carbs: Double = 0, fat: Double = 0,
        sodium: Double? = nil, daysAgo: Int = 0
    ) -> FoodLog {
        let cal = Calendar.current
        let date = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: Date()))!
        return FoodLog(
            timestamp: date,
            mealType: .lunch,
            quantity: 1,
            caloriesAtLogTime: calories,
            proteinAtLogTime: protein,
            carbsAtLogTime: carbs,
            fatAtLogTime: fat,
            sodiumAtLogTime: sodium
        )
    }

    // MARK: - calculate(food:gramAmount:)

    func testCalculate_scalesByGramFactor() {
        // 200 cal per 100g × 150g factor = 300 cal
        let food = makeFood(calories: 200, protein: 10, carbs: 20, fat: 5)
        let result = NutritionCalculator.calculate(food: food, gramAmount: 150)
        XCTAssertEqual(result.calories, 300, accuracy: 0.001)
        XCTAssertEqual(result.protein,   15, accuracy: 0.001)
        XCTAssertEqual(result.carbs,     30, accuracy: 0.001)
        XCTAssertEqual(result.fat,      7.5, accuracy: 0.001)
    }

    func testCalculate_exactHundredGrams_returnsNutritionDirectly() {
        let food = makeFood(calories: 350, protein: 22, carbs: 15, fat: 18)
        let result = NutritionCalculator.calculate(food: food, gramAmount: 100)
        XCTAssertEqual(result.calories, 350, accuracy: 0.001)
        XCTAssertEqual(result.protein,   22, accuracy: 0.001)
    }

    func testCalculate_zeroGramAmount_returnsZero() {
        let food = makeFood(calories: 200, protein: 10, carbs: 20, fat: 5)
        let result = NutritionCalculator.calculate(food: food, gramAmount: 0)
        XCTAssertEqual(result.calories, 0)
        XCTAssertEqual(result.protein,  0)
        XCTAssertEqual(result.carbs,    0)
        XCTAssertEqual(result.fat,      0)
    }

    func testCalculate_optionalNutrients_scaledWhenPresent() {
        let food = makeFood(calories: 100, fiber: 10, sodium: 400)
        let result = NutritionCalculator.calculate(food: food, gramAmount: 200)
        XCTAssertEqual(result.fiber!,   20, accuracy: 0.001)
        XCTAssertEqual(result.sodium!, 800, accuracy: 0.001)
    }

    func testCalculate_nilOptionalNutrients_remainNil() {
        // fiber and sodium not passed → stay nil
        let food = makeFood(calories: 100)
        let result = NutritionCalculator.calculate(food: food, gramAmount: 100)
        XCTAssertNil(result.fiber)
        XCTAssertNil(result.sodium)
    }

    func testCalculate_fractionalGrams() {
        let food = makeFood(calories: 400)
        let result = NutritionCalculator.calculate(food: food, gramAmount: 50)
        XCTAssertEqual(result.calories, 200, accuracy: 0.001)
    }

    // MARK: - fromLog(_:)

    func testFromLog_returnsFrozenValues() {
        let log = makeLog(calories: 350, protein: 25, carbs: 42, fat: 11, sodium: 820)
        let result = NutritionCalculator.fromLog(log)
        XCTAssertEqual(result.calories, 350)
        XCTAssertEqual(result.protein,   25)
        XCTAssertEqual(result.carbs,     42)
        XCTAssertEqual(result.fat,       11)
        XCTAssertEqual(result.sodium,   820)
    }

    func testFromLog_nilOptionalNutrients_remainNil() {
        let log = makeLog(calories: 200, protein: 10, carbs: 20, fat: 5)
        // sodium not passed → nil
        let result = NutritionCalculator.fromLog(log)
        XCTAssertNil(result.sodium)
        XCTAssertNil(result.fiber)
    }

    // MARK: - dailyTotal(logs:)

    func testDailyTotal_sumsMultipleLogs() {
        let log1 = makeLog(calories: 300, protein: 20, carbs: 40, fat: 8)
        let log2 = makeLog(calories: 200, protein: 15, carbs: 25, fat: 6)
        let result = NutritionCalculator.dailyTotal(logs: [log1, log2])
        XCTAssertEqual(result.calories, 500)
        XCTAssertEqual(result.protein,   35)
        XCTAssertEqual(result.carbs,     65)
        XCTAssertEqual(result.fat,       14)
    }

    func testDailyTotal_emptyLogs_returnsZero() {
        let result = NutritionCalculator.dailyTotal(logs: [])
        XCTAssertEqual(result.calories, 0)
        XCTAssertEqual(result.protein,  0)
    }

    func testDailyTotal_singleLog_equalsFromLog() {
        let log = makeLog(calories: 600, protein: 30, carbs: 80, fat: 15)
        let total  = NutritionCalculator.dailyTotal(logs: [log])
        let single = NutritionCalculator.fromLog(log)
        XCTAssertEqual(total.calories, single.calories)
        XCTAssertEqual(total.protein,  single.protein)
    }

    // MARK: - rollingAverage(logs:days:nutrient:)

    func testRollingAverage_emptyLogs_returnsEmpty() {
        let result = NutritionCalculator.rollingAverage(logs: [], nutrient: .calories)
        XCTAssertTrue(result.isEmpty)
    }

    func testRollingAverage_singleDay_returnsItself() {
        let log = makeLog(calories: 2000)
        let result = NutritionCalculator.rollingAverage(logs: [log], days: 7, nutrient: .calories)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].average, 2000, accuracy: 0.001)
    }

    func testRollingAverage_twoDays_correctAccumulation() {
        // Day -1: 1000 cal, Day 0: 3000 cal.
        // Day 0 avg (7-day window) = (1000 + 3000) / 2 = 2000
        let log1 = makeLog(calories: 1000, daysAgo: 1)
        let log2 = makeLog(calories: 3000, daysAgo: 0)
        let result = NutritionCalculator.rollingAverage(logs: [log1, log2], days: 7, nutrient: .calories)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].average, 1000, accuracy: 0.001)
        XCTAssertEqual(result[1].average, 2000, accuracy: 0.001)
    }

    func testRollingAverage_gapDay_denominatorUsesLoggedDaysOnly() {
        // Logs on day -2 (1500 cal) and day 0 (500 cal) — gap on day -1.
        // Day -2 avg = 1500/1 = 1500 (just itself).
        // Day 0 avg = (1500 + 500) / 2 = 1000 (denominator = 2 logged days, not 3 calendar days).
        let log1 = makeLog(calories: 1500, daysAgo: 2)
        let log2 = makeLog(calories: 500,  daysAgo: 0)
        let result = NutritionCalculator.rollingAverage(logs: [log1, log2], days: 7, nutrient: .calories)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].average, 1500, accuracy: 0.001)
        XCTAssertEqual(result[1].average, 1000, accuracy: 0.001)
    }

    func testRollingAverage_proteinNutrient() {
        let log = FoodLog(mealType: .breakfast, quantity: 1,
                          caloriesAtLogTime: 500, proteinAtLogTime: 80,
                          carbsAtLogTime: 0, fatAtLogTime: 0)
        // Note: timestamp defaults to Date() which is fine for single-day rolling average test
        let result = NutritionCalculator.rollingAverage(logs: [log], days: 7, nutrient: .protein)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].average, 80, accuracy: 0.001)
    }

    func testRollingAverage_sortedAscendingByDate() {
        let log1 = makeLog(calories: 1000, daysAgo: 2)
        let log2 = makeLog(calories: 2000, daysAgo: 0)
        let result = NutritionCalculator.rollingAverage(logs: [log1, log2], days: 7, nutrient: .calories)
        XCTAssertEqual(result.count, 2)
        XCTAssertLessThan(result[0].date, result[1].date)
    }
}

// MARK: - USDA dataType branching tests (test plan items 1-3)

final class USDAToProductInfoTests: XCTestCase {

    // Helpers

    private func makeEnergyNutrient(kcal: Double) -> USDANutrientDetail {
        USDANutrientDetail(
            nutrient: USDANutrientInfo(id: 1008, number: "208", name: "Energy", unitName: "kcal"),
            amount: kcal
        )
    }

    private func makeDetail(dataType: String, servingSize: Double? = nil, kcalPer100g: Double = 400) -> USDAFoodDetail {
        USDAFoodDetail(
            fdcId: 99999,
            description: "Test \(dataType) Food",
            dataType: dataType,
            foodNutrients: [makeEnergyNutrient(kcal: kcalPer100g)],
            servingSize: servingSize,
            householdServingFullText: servingSize != nil ? "1 serving" : nil
        )
    }

    // Test 1: Branded Foods populate *Serving fields using servingSize
    func testUSDABrandedFoodToProductInfo_hasServingFields() {
        let detail = makeDetail(dataType: "Branded", servingSize: 30.0, kcalPer100g: 400)
        let product = detail.toProductInfo()

        let nutriments = product.nutriments
        XCTAssertNotNil(nutriments?.energyKcalServing, "Branded food must have energyKcalServing")
        // 400 kcal/100g × (30g / 100) = 120 kcal/serving
        XCTAssertEqual(nutriments?.energyKcalServing?.value ?? 0, 120, accuracy: 0.01)
        XCTAssertEqual(product.dataType, "Branded")
    }

    // Test 2: Foundation foods must keep all *Serving fields nil
    func testUSDAFoundationFoodToProductInfo_servingFieldsNil() {
        let detail = makeDetail(dataType: "Foundation")
        let product = detail.toProductInfo()

        let nutriments = product.nutriments
        XCTAssertNil(nutriments?.energyKcalServing, "Foundation food must NOT have energyKcalServing")
        XCTAssertNil(nutriments?.proteinsServing)
        XCTAssertNil(nutriments?.carbohydratesServing)
        XCTAssertNil(nutriments?.fatServing)
        XCTAssertNil(nutriments?.fiberServing)
        XCTAssertNil(nutriments?.sodiumServing)
    }

    // Test 3: SR Legacy foods must keep all *Serving fields nil (regression guard)
    func testUSDASRLegacyFoodToProductInfo_servingFieldsNil() {
        let detail = makeDetail(dataType: "SR Legacy")
        let product = detail.toProductInfo()

        let nutriments = product.nutriments
        XCTAssertNil(nutriments?.energyKcalServing, "SR Legacy food must NOT have energyKcalServing")
        XCTAssertNil(nutriments?.proteinsServing)
        XCTAssertNil(nutriments?.carbohydratesServing)
        XCTAssertNil(nutriments?.fatServing)
        XCTAssertNil(nutriments?.fiberServing)
        XCTAssertNil(nutriments?.sodiumServing)
    }
}

// MARK: - Micro-celebration flag tests (test plan items 4-5)

final class MicroCelebrationFlagTests: XCTestCase {

    // Test 4: New install (nil flag) — verify flag starts nil and can be set to true
    func testMicroCelebration_firesOnFirstLog() {
        let prefs = UserPreferences()
        // Fresh install: flag must be nil
        XCTAssertNil(prefs.hasSeenFirstLogCelebration, "Fresh install: hasSeenFirstLogCelebration must be nil")

        // Simulate the TodayView guard: fires only when nil
        let shouldFire = prefs.hasSeenFirstLogCelebration == nil
        XCTAssertTrue(shouldFire, "Celebration should fire when flag is nil")

        // Mark as seen
        prefs.hasSeenFirstLogCelebration = true
        XCTAssertEqual(prefs.hasSeenFirstLogCelebration, true)
    }

    // Test 5: Flag already set — verify guard prevents double-trigger
    func testMicroCelebration_doesNotFireTwice() {
        let prefs = UserPreferences()
        prefs.hasSeenFirstLogCelebration = true

        // Simulate the TodayView guard
        let shouldFire = prefs.hasSeenFirstLogCelebration == nil
        XCTAssertFalse(shouldFire, "Celebration must NOT fire when flag is already true")
    }
}
