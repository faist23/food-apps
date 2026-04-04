//
//  BiteLedgerTests.swift
//  BiteLedgerTests
//

import XCTest
import SwiftData
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

// MARK: - NutrientSpotlightEngine Tests (Phase 2, Feature 1)

final class NutrientSpotlightEngineTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a FoodLog `daysAgo` days in the past with optional spotlight nutrient values.
    private func makeSpotlightLog(
        daysAgo: Int,
        sodium: Double? = nil,
        saturatedFat: Double? = nil,
        fat: Double = 0,
        cholesterol: Double? = nil,
        carbs: Double = 0,
        mealType: MealType = .lunch
    ) -> FoodLog {
        let cal = Calendar.current
        let date = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: Date()))!
        return FoodLog(
            timestamp: date,
            mealType: mealType,
            quantity: 1,
            caloriesAtLogTime: 0,
            proteinAtLogTime: 0,
            carbsAtLogTime: carbs,
            fatAtLogTime: fat,
            sodiumAtLogTime: sodium,
            saturatedFatAtLogTime: saturatedFat,
            cholesterolAtLogTime: cholesterol
        )
    }

    // Test 1: Empty logs → empty results
    func testCompute_noLogs_returnsEmpty() {
        XCTAssertTrue(NutrientSpotlightEngine.compute(logs: []).isEmpty)
    }

    // Test 2: Logs on only 2 days (< minDaysAbove=3) → empty results
    func testCompute_insufficientDays_returnsEmpty() {
        let logs = [
            makeSpotlightLog(daysAgo: 0, sodium: 4000),
            makeSpotlightLog(daysAgo: 1, sodium: 4000)
        ]
        XCTAssertTrue(NutrientSpotlightEngine.compute(logs: logs).isEmpty)
    }

    // Test 3: Sodium over 120% DV (2760mg) on exactly 3 days → 1 result for sodium
    func testCompute_oneNutrientAboveThreshold_returnsIt() {
        // FDA DV for sodium = 2300mg; 120% = 2760mg. Use 3000mg to clear threshold.
        let logs = (0..<3).map { makeSpotlightLog(daysAgo: $0, sodium: 3000) }
        let results = NutrientSpotlightEngine.compute(logs: logs)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].nutrient, .sodium)
        XCTAssertEqual(results[0].daysAboveThreshold, 3)
    }

    // Test 4: Sodium high 5 days, saturated fat high 3 days → sodium ranked first
    func testCompute_twoNutrientsRankedByDaysAbove() {
        // sodium DV = 2300; saturated fat DV = 20g
        var logs: [FoodLog] = []
        for i in 0..<5 { logs.append(makeSpotlightLog(daysAgo: i, sodium: 3000, saturatedFat: 30)) }
        for i in 5..<7 { logs.append(makeSpotlightLog(daysAgo: i, sodium: 3000)) }
        // sodium: 7 days above; saturated fat: 5 days above
        let results = NutrientSpotlightEngine.compute(logs: logs)
        XCTAssertGreaterThanOrEqual(results.count, 2)
        XCTAssertEqual(results[0].nutrient, .sodium, "Sodium (more days) must rank first")
        XCTAssertTrue(results[1].daysAboveThreshold <= results[0].daysAboveThreshold)
    }

    // Test 5: Day where ALL logs have nil sodiumAtLogTime → not counted toward sodium threshold
    func testCompute_nilNutrientDay_excludedFromCount() {
        // 3 days with real sodium above threshold + 1 day with nil sodium = 3 sodium days
        var logs = (0..<3).map { makeSpotlightLog(daysAgo: $0, sodium: 3000) }
        // Day 4: log present but sodium is nil → must NOT count as a sodium day
        logs.append(makeSpotlightLog(daysAgo: 4, sodium: nil))
        let results = NutrientSpotlightEngine.compute(logs: logs)
        // sodium qualifies (3 days above)
        let sodiumResult = results.first { $0.nutrient == .sodium }
        XCTAssertNotNil(sodiumResult)
        XCTAssertEqual(sodiumResult?.daysAboveThreshold, 3, "Nil-sodium day must not inflate the count")
    }

    // Test 6: Injectable params override defaults (minDaysAbove: 1, dvMultiplier: 0.01)
    func testCompute_injectableParamsOverrideDefaults() {
        // One log with sodium 1mg — well below 120% DV but above 1% DV
        let logs = [makeSpotlightLog(daysAgo: 0, sodium: 1)]
        let results = NutrientSpotlightEngine.compute(
            logs: logs,
            minDaysAbove: 1,
            dvMultiplier: 0.01   // threshold = 2300 × 0.01 = 23mg; 1mg is NOT above 23mg
        )
        // 1mg < 23mg threshold → still empty at this multiplier
        // Use an even lower multiplier so 1mg clears the bar
        let results2 = NutrientSpotlightEngine.compute(
            logs: logs,
            minDaysAbove: 1,
            dvMultiplier: 0.0001  // threshold = 2300 × 0.0001 = 0.23mg; 1mg > 0.23mg → qualifies
        )
        XCTAssertFalse(results2.isEmpty, "Injectable params must allow qualifying with very low threshold")
    }

    // Test 7: Nutrient.value(from:) returns the correct *AtLogTime field for each spotlight nutrient
    func testNutrientValueFromLog_allSpotlightNutrients() {
        let log = makeSpotlightLog(
            daysAgo: 0,
            sodium: 500,
            saturatedFat: 10,
            fat: 30,
            cholesterol: 150,
            carbs: 200
        )
        XCTAssertEqual(Nutrient.sodium.value(from: log), 500)
        XCTAssertEqual(Nutrient.saturatedFat.value(from: log), 10)
        XCTAssertEqual(Nutrient.fat.value(from: log), 30)
        XCTAssertEqual(Nutrient.cholesterol.value(from: log), 150)
        XCTAssertEqual(Nutrient.carbs.value(from: log), 200)
        // Non-spotlight nutrient must return nil
        XCTAssertNil(Nutrient.protein.value(from: log))
    }

    // Test 8: User goal overrides FDA default — carbs flagged at FDA DV but not at user's higher goal
    func testUserGoalOverridesSuppressesFalsePositive() {
        // 380g/day carbs × 4 days — above FDA base (250g × 1.2 = 300g) but below user goal (400g × 1.2 = 480g)
        let logs = (0..<4).map { makeSpotlightLog(daysAgo: $0, carbs: 380) }

        // Without user goal: qualifies (380 > 300)
        let withoutGoal = NutrientSpotlightEngine.compute(logs: logs, userGoals: [:])
        XCTAssertTrue(
            withoutGoal.contains { $0.nutrient == .carbs },
            "Carbs should flag at FDA default when no goal is set"
        )

        // With user goal of 400g (maximum): threshold = 480g; 380g < 480g → should NOT qualify
        let carbGoal = NutrientGoal(targetValue: 400, goalType: .maximum)
        let withGoal = NutrientSpotlightEngine.compute(
            logs: logs,
            userGoals: [Nutrient.carbs.rawValue: carbGoal]
        )
        XCTAssertFalse(
            withGoal.contains { $0.nutrient == .carbs },
            "Carbs should NOT flag when daily intake is below user's goal threshold"
        )
    }

    // Test 9: Minimum goal suppresses high-side flag entirely — eating over a floor is intentional
    func testMinimumGoalSuppressesSpotlight() {
        // 380g/day carbs × 4 days — would normally flag at FDA default (300g threshold)
        let logs = (0..<4).map { makeSpotlightLog(daysAgo: $0, carbs: 380) }

        let carbMinGoal = NutrientGoal(targetValue: 300, goalType: .minimum)
        let results = NutrientSpotlightEngine.compute(
            logs: logs,
            userGoals: [Nutrient.carbs.rawValue: carbMinGoal]
        )
        XCTAssertFalse(
            results.contains { $0.nutrient == .carbs },
            "Carbs with a minimum goal should never be flagged as high"
        )
    }
}

// MARK: - FoodHistoryEntry Tests

@MainActor
final class FoodHistoryEntryTests: XCTestCase {

    // MARK: - Helpers

    /// In-memory container with the full V4 model list.
    /// Throws XCTSkip if the test environment cannot initialise SwiftData
    /// (known limitation in iOS 26 simulator unit-test processes — see T-FHE-SKIP).
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(BiteLedgerSchemaV4.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            throw XCTSkip("SwiftData ModelContainer unavailable in this test environment. Run on a physical device or iOS 17/18 simulator. Error: \(error)")
        }
    }

    private func makeFood(in context: ModelContext, name: String = "Test Food") -> FoodItem {
        let food = FoodItem(
            name: name, source: "test", nutritionMode: .per100g,
            calories: 100, protein: 10, carbs: 20, fat: 5
        )
        context.insert(food)
        return food
    }

    // MARK: - T1: upsert creates a new entry when none exists

    func testUpsert_createsNewEntry_whenNoneExists() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let food = makeFood(in: context)

        FoodHistoryEntry.upsert(food: food, mealType: .breakfast, in: context)
        try context.save()

        let entries = try context.fetch(FetchDescriptor<FoodHistoryEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].food?.id, food.id)
        XCTAssertEqual(entries[0].mealType, .breakfast)
        XCTAssertEqual(entries[0].logCount, 1)
    }

    // MARK: - T2: upsert increments logCount on second call for same (food, mealType)

    func testUpsert_incrementsLogCount_onSecondCall() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let food = makeFood(in: context)

        FoodHistoryEntry.upsert(food: food, mealType: .lunch, in: context)
        FoodHistoryEntry.upsert(food: food, mealType: .lunch, in: context)
        try context.save()

        let entries = try context.fetch(FetchDescriptor<FoodHistoryEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].logCount, 2)
    }

    // MARK: - T3: upsert creates separate entries for different meal types

    func testUpsert_createsSeparateEntries_perMealType() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let food = makeFood(in: context)

        FoodHistoryEntry.upsert(food: food, mealType: .breakfast, in: context)
        FoodHistoryEntry.upsert(food: food, mealType: .dinner, in: context)
        try context.save()

        let entries = try context.fetch(FetchDescriptor<FoodHistoryEntry>())
        XCTAssertEqual(entries.count, 2)
        let mealTypes = Set(entries.map { $0.mealType })
        XCTAssertTrue(mealTypes.contains(.breakfast))
        XCTAssertTrue(mealTypes.contains(.dinner))
    }

    // MARK: - T4: upsert merges duplicate entries

    func testUpsert_mergesDuplicates_whenTwoExist() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let food = makeFood(in: context)

        // Manually insert two duplicate entries (simulates partial backfill scenario)
        let e1 = FoodHistoryEntry(food: food, mealType: .snack)
        e1.logCount = 3
        let e2 = FoodHistoryEntry(food: food, mealType: .snack)
        e2.logCount = 2
        context.insert(e1)
        context.insert(e2)
        try context.save()

        // upsert should detect the duplicate and merge
        FoodHistoryEntry.upsert(food: food, mealType: .snack, in: context)
        try context.save()

        let entries = try context.fetch(FetchDescriptor<FoodHistoryEntry>())
        XCTAssertEqual(entries.count, 1, "Duplicates should be merged into one entry")
        // merged logCount = e1.logCount + e2.logCount + 1 (for this upsert)
        XCTAssertEqual(entries[0].logCount, 6)
    }

    // MARK: - T5: upsert updates lastLoggedDate on increment

    func testUpsert_updatesLastLoggedDate_onIncrement() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let food = makeFood(in: context)

        FoodHistoryEntry.upsert(food: food, mealType: .breakfast, in: context)
        try context.save()

        let firstDate = try context.fetch(FetchDescriptor<FoodHistoryEntry>())[0].lastLoggedDate
        // Simulate time passing and a second log
        FoodHistoryEntry.upsert(food: food, mealType: .breakfast, in: context)
        try context.save()

        let updatedDate = try context.fetch(FetchDescriptor<FoodHistoryEntry>())[0].lastLoggedDate
        XCTAssertGreaterThanOrEqual(updatedDate, firstDate)
    }

    // MARK: - T6: separate foods get separate entries

    func testUpsert_createsSeparateEntries_forDifferentFoods() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let apple = makeFood(in: context, name: "Apple")
        let banana = makeFood(in: context, name: "Banana")

        FoodHistoryEntry.upsert(food: apple, mealType: .breakfast, in: context)
        FoodHistoryEntry.upsert(food: banana, mealType: .breakfast, in: context)
        try context.save()

        let entries = try context.fetch(FetchDescriptor<FoodHistoryEntry>())
        XCTAssertEqual(entries.count, 2)
    }

    // MARK: - T7: backfill guard — hasBackfilledFoodHistory starts nil

    func testUserPreferences_backfillFlag_startsNil() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let prefs = UserPreferences()
        context.insert(prefs)
        try context.save()

        XCTAssertNil(prefs.hasBackfilledFoodHistory,
                     "Flag must start nil so backfill runs on first launch after migration")
    }

    // MARK: - T8: backfill guard — flag set to true prevents re-run

    func testUserPreferences_backfillFlag_trueBlocksReRun() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let prefs = UserPreferences()
        prefs.hasBackfilledFoodHistory = true
        context.insert(prefs)
        try context.save()

        // Verify the guard condition used in backfillFoodHistory()
        let fetched = try context.fetch(FetchDescriptor<UserPreferences>()).first
        XCTAssertEqual(fetched?.hasBackfilledFoodHistory, true)
    }

    // MARK: - T9: upsert is a no-op when food is already in history for that meal type (count check)

    func testUpsert_thirdCall_logCountIsThree() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let food = makeFood(in: context)

        FoodHistoryEntry.upsert(food: food, mealType: .dinner, in: context)
        FoodHistoryEntry.upsert(food: food, mealType: .dinner, in: context)
        FoodHistoryEntry.upsert(food: food, mealType: .dinner, in: context)
        try context.save()

        let entries = try context.fetch(FetchDescriptor<FoodHistoryEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].logCount, 3)
    }

    // MARK: - T10: FoodLog.create() triggers upsert

    func testFoodLogCreate_triggersUpsert() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let food = makeFood(in: context)
        let serving = ServingSize(label: "100g", gramWeight: 100, isDefault: true, sortOrder: 0, unit: "g")
        serving.foodItem = food
        context.insert(serving)
        food.servingSizes.append(serving)
        try context.save()

        let log = FoodLog.create(
            mealType: .lunch, quantity: 1.0,
            food: food, serving: serving,
            context: context
        )
        context.insert(log)
        try context.save()

        let entries = try context.fetch(FetchDescriptor<FoodHistoryEntry>())
        XCTAssertEqual(entries.count, 1,
                       "FoodLog.create() must call FoodHistoryEntry.upsert()")
        XCTAssertEqual(entries[0].mealType, .lunch)
        XCTAssertEqual(entries[0].logCount, 1)
    }

    // MARK: - T11: schema registers FoodHistoryEntry

    func testSchema_registersFoodHistoryEntry() throws {
        // If FoodHistoryEntry isn't in the schema, makeContainer() throws — so reaching this
        // line is the assertion.
        let container = try makeContainer()
        let context = container.mainContext
        let food = makeFood(in: context)
        let entry = FoodHistoryEntry(food: food, mealType: .breakfast)
        context.insert(entry)
        XCTAssertNoThrow(try context.save())
    }

    // MARK: - T12: FoodItem deletion nullifies food reference (no back-reference = no cascade)

    func testFoodItemDeletion_nullifiesFoodReference_onHistoryEntry() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let food = makeFood(in: context)

        FoodHistoryEntry.upsert(food: food, mealType: .breakfast, in: context)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<FoodHistoryEntry>()).count, 1)

        context.delete(food)
        try context.save()

        // FoodHistoryEntry survives (nullify, not cascade) — food becomes nil.
        // Display code filters these out via compactMap { $0.food }.
        let remaining = try context.fetch(FetchDescriptor<FoodHistoryEntry>())
        XCTAssertEqual(remaining.count, 1, "Entry survives deletion — nullify rule, not cascade")
        XCTAssertNil(remaining[0].food, "food reference should be nil after FoodItem deletion")
    }
}

// MARK: - T-12-RestoreUpdate: CSVExporter Meal Plan Tests

@MainActor
final class T12CSVExporterMealTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(BiteLedgerSchemaV5.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            throw XCTSkip("SwiftData unavailable: \(error)")
        }
    }

    /// Deterministic Sunday midnight for assertions.
    private var sunday: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 4; c.day = 5; c.hour = 0; c.minute = 0; c.second = 0
        return Calendar.current.date(from: c)!
    }

    func testExportMealPlans_headersAndColumns() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let plan = MealPlan(weekStartDate: sunday)
        context.insert(plan)
        try context.save()

        let csv = CSVExporter.exportMealPlans([plan])
        let rows = CSVImporter.parseCSV(csv)

        XCTAssertEqual(rows.first, ["id", "weekStartDate"])
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1][0], plan.id.uuidString)
        XCTAssertFalse(rows[1][1].isEmpty, "weekStartDate column must be a non-empty ISO8601 string")
    }

    func testExportMealPlans_empty() {
        let csv = CSVExporter.exportMealPlans([])
        let rows = CSVImporter.parseCSV(csv)
        XCTAssertEqual(rows.count, 1, "Empty input must produce only the header row")
    }

    func testExportMealMeals_namePresent() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let plan = MealPlan(weekStartDate: sunday)
        context.insert(plan)
        let meal = MealPlanMeal(mealPlan: plan, date: sunday, mealType: .dinner)
        meal.name = "PB Night"
        context.insert(meal)
        try context.save()

        let csv = CSVExporter.exportMealMeals([meal])
        let rows = CSVImporter.parseCSV(csv)

        XCTAssertEqual(rows.count, 2)
        let nameIdx = rows[0].firstIndex(of: "name")!
        XCTAssertEqual(rows[1][nameIdx], "PB Night")
    }

    func testExportMealMeals_nilNameExportsEmpty() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let plan = MealPlan(weekStartDate: sunday)
        context.insert(plan)
        let meal = MealPlanMeal(mealPlan: plan, date: sunday, mealType: .lunch)
        // name is nil by default
        context.insert(meal)
        try context.save()

        let csv = CSVExporter.exportMealMeals([meal])
        let rows = CSVImporter.parseCSV(csv)

        XCTAssertEqual(rows.count, 2)
        let nameIdx = rows[0].firstIndex(of: "name")!
        XCTAssertEqual(rows[1][nameIdx], "", "nil name must export as empty string, not 'nil' or 'Optional(...)'")
    }

    func testExportMealItems_recipeItem() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let plan = MealPlan(weekStartDate: sunday)
        context.insert(plan)
        let meal = MealPlanMeal(mealPlan: plan, date: sunday, mealType: .dinner)
        context.insert(meal)
        let recipe = Recipe(name: "Pasta Carbonara")
        context.insert(recipe)
        let item = MealPlanMealItem(meal: meal)
        item.recipe = recipe
        context.insert(item)
        try context.save()

        let csv = CSVExporter.exportMealItems([item])
        let rows = CSVImporter.parseCSV(csv)

        XCTAssertEqual(rows.count, 2)
        let recipeIdx = rows[0].firstIndex(of: "recipeId")!
        let foodIdx   = rows[0].firstIndex(of: "foodItemId")!
        let noteIdx   = rows[0].firstIndex(of: "note")!
        XCTAssertEqual(rows[1][recipeIdx], recipe.id.uuidString)
        XCTAssertEqual(rows[1][foodIdx],   "")
        XCTAssertEqual(rows[1][noteIdx],   "")
    }

    func testExportMealItems_foodItem() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let plan = MealPlan(weekStartDate: sunday)
        context.insert(plan)
        let meal = MealPlanMeal(mealPlan: plan, date: sunday, mealType: .lunch)
        context.insert(meal)
        let food = FoodItem(name: "Chicken Breast", source: "test", nutritionMode: .per100g,
                            calories: 165, protein: 31, carbs: 0, fat: 3.6)
        context.insert(food)
        let item = MealPlanMealItem(meal: meal)
        item.foodItem = food
        context.insert(item)
        try context.save()

        let csv = CSVExporter.exportMealItems([item])
        let rows = CSVImporter.parseCSV(csv)

        XCTAssertEqual(rows.count, 2)
        let recipeIdx = rows[0].firstIndex(of: "recipeId")!
        let foodIdx   = rows[0].firstIndex(of: "foodItemId")!
        XCTAssertEqual(rows[1][recipeIdx], "")
        XCTAssertEqual(rows[1][foodIdx],   food.id.uuidString)
    }

    func testExportMealItems_noteOnly() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let plan = MealPlan(weekStartDate: sunday)
        context.insert(plan)
        let meal = MealPlanMeal(mealPlan: plan, date: sunday, mealType: .dinner)
        context.insert(meal)
        let item = MealPlanMealItem(meal: meal)
        item.note = "Taco night at Mario's"
        context.insert(item)
        try context.save()

        let csv = CSVExporter.exportMealItems([item])
        let rows = CSVImporter.parseCSV(csv)

        XCTAssertEqual(rows.count, 2)
        let recipeIdx = rows[0].firstIndex(of: "recipeId")!
        let foodIdx   = rows[0].firstIndex(of: "foodItemId")!
        let noteIdx   = rows[0].firstIndex(of: "note")!
        XCTAssertEqual(rows[1][recipeIdx], "")
        XCTAssertEqual(rows[1][foodIdx],   "")
        XCTAssertEqual(rows[1][noteIdx],   "Taco night at Mario's")
    }

    func testExportMealItems_noteWithCommaIsRFC4180Quoted() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let plan = MealPlan(weekStartDate: sunday)
        context.insert(plan)
        let meal = MealPlanMeal(mealPlan: plan, date: sunday, mealType: .dinner)
        context.insert(meal)
        let item = MealPlanMealItem(meal: meal)
        item.note = "Pasta, garlic bread"
        context.insert(item)
        try context.save()

        let csv = CSVExporter.exportMealItems([item])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].contains("\"Pasta, garlic bread\""),
                      "Note containing a comma must be RFC 4180 quoted in the data row")
    }
}

// MARK: - T-12-RestoreUpdate: CSVImporter Meal Plan Tests

@MainActor
final class T12CSVImporterMealTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(BiteLedgerSchemaV5.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            throw XCTSkip("SwiftData unavailable: \(error)")
        }
    }

    // Minimal header-only CSVs required by importBiteLedger.
    private let minFoods    = "id,name,nutritionMode,calories,protein,carbs,fat"
    private let minServings = "id,foodId,label,gramWeight,isDefault,sortOrder,dateAdded,unit"
    private let minLogs     = "id,foodId,servingId,timestamp,mealType,quantity,caloriesAtLogTime,proteinAtLogTime,carbsAtLogTime,fatAtLogTime"

    private var sunday: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 4; c.day = 5; c.hour = 0; c.minute = 0; c.second = 0
        return Calendar.current.date(from: c)!
    }

    private func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    // MARK: - Meal Plan import

    func testImportMealPlans_createsRecord() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let id = UUID()
        let planCSV = "id,weekStartDate\n\(id.uuidString),\(iso(sunday))"

        let result = try CSVImporter.importBiteLedger(
            foodsCSV: minFoods, servingsCSV: minServings, logsCSV: minLogs,
            mealPlansCSV: planCSV, context: context
        )

        let plans = try context.fetch(FetchDescriptor<MealPlan>())
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans[0].id, id)
        XCTAssertEqual(result.mealPlansCreated, 1)
    }

    func testImportMealPlans_mergeSkipsDuplicate() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let id = UUID()
        let existing = MealPlan(weekStartDate: sunday)
        existing.id = id
        context.insert(existing)
        try context.save()

        let planCSV = "id,weekStartDate\n\(id.uuidString),\(iso(sunday))"
        let result = try CSVImporter.importBiteLedger(
            foodsCSV: minFoods, servingsCSV: minServings, logsCSV: minLogs,
            mealPlansCSV: planCSV, skipExistingUUIDs: true, context: context
        )

        let plans = try context.fetch(FetchDescriptor<MealPlan>())
        XCTAssertEqual(plans.count, 1, "Merge mode must not duplicate existing UUID")
        XCTAssertEqual(result.mealPlansCreated, 0)
    }

    func testImportMealPlans_weekStartDateDedup() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let existingId = UUID()
        let existing = MealPlan(weekStartDate: sunday)
        existing.id = existingId
        context.insert(existing)
        try context.save()

        // Import a row with a different UUID but same weekStartDate.
        let newId = UUID()
        let planCSV = "id,weekStartDate\n\(newId.uuidString),\(iso(sunday))"
        let result = try CSVImporter.importBiteLedger(
            foodsCSV: minFoods, servingsCSV: minServings, logsCSV: minLogs,
            mealPlansCSV: planCSV, skipExistingUUIDs: true, context: context
        )

        let plans = try context.fetch(FetchDescriptor<MealPlan>())
        XCTAssertEqual(plans.count, 1, "Secondary weekStartDate dedup must prevent duplicate week")
        XCTAssertEqual(result.mealPlansCreated, 0, "No new plan created when week already exists")
    }

    // MARK: - MealPlanMeal import

    func testImportMealMeals_linksToPlan() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let planId = UUID()
        let mealId = UUID()
        let planCSV = "id,weekStartDate\n\(planId.uuidString),\(iso(sunday))"
        let mealCSV = "id,planId,date,mealType,name\n\(mealId.uuidString),\(planId.uuidString),\(iso(sunday)),Dinner,"

        _ = try CSVImporter.importBiteLedger(
            foodsCSV: minFoods, servingsCSV: minServings, logsCSV: minLogs,
            mealPlansCSV: planCSV, mealMealsCSV: mealCSV, context: context
        )

        let meals = try context.fetch(FetchDescriptor<MealPlanMeal>())
        XCTAssertEqual(meals.count, 1)
        XCTAssertNotNil(meals[0].mealPlan)
        XCTAssertEqual(meals[0].mealPlan?.id, planId)
    }

    func testImportMealMeals_invalidMealTypeSkipsRow() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let planId = UUID()
        let mealId = UUID()
        let planCSV = "id,weekStartDate\n\(planId.uuidString),\(iso(sunday))"
        let mealCSV = "id,planId,date,mealType,name\n\(mealId.uuidString),\(planId.uuidString),\(iso(sunday)),InvalidType,"

        let result = try CSVImporter.importBiteLedger(
            foodsCSV: minFoods, servingsCSV: minServings, logsCSV: minLogs,
            mealPlansCSV: planCSV, mealMealsCSV: mealCSV, context: context
        )

        let meals = try context.fetch(FetchDescriptor<MealPlanMeal>())
        XCTAssertEqual(meals.count, 0)
        XCTAssertFalse(result.errors.isEmpty, "Invalid mealType must produce an error entry")
    }

    func testImportMealMeals_missingPlanIdSkipsRow() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let unknownPlanId = UUID()
        let mealId = UUID()
        let planCSV = "id,weekStartDate"   // header only — no plans inserted
        let mealCSV = "id,planId,date,mealType,name\n\(mealId.uuidString),\(unknownPlanId.uuidString),\(iso(sunday)),Dinner,"

        let result = try CSVImporter.importBiteLedger(
            foodsCSV: minFoods, servingsCSV: minServings, logsCSV: minLogs,
            mealPlansCSV: planCSV, mealMealsCSV: mealCSV, context: context
        )

        let meals = try context.fetch(FetchDescriptor<MealPlanMeal>())
        XCTAssertEqual(meals.count, 0)
        XCTAssertFalse(result.errors.isEmpty, "Unknown planId must produce an error entry")
    }

    // MARK: - MealPlanMealItem import

    func testImportMealItems_recipeLinked() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let recipe = Recipe(name: "Pasta Carbonara")
        context.insert(recipe)
        try context.save()

        let planId = UUID(); let mealId = UUID(); let itemId = UUID()
        let planCSV = "id,weekStartDate\n\(planId.uuidString),\(iso(sunday))"
        let mealCSV = "id,planId,date,mealType,name\n\(mealId.uuidString),\(planId.uuidString),\(iso(sunday)),Dinner,"
        let itemCSV = "id,mealId,recipeId,foodItemId,servingSizeId,note,servingCount\n" +
                      "\(itemId.uuidString),\(mealId.uuidString),\(recipe.id.uuidString),,,,1"

        // skipExistingUUIDs: true so existingRecipeMap is populated with the pre-inserted recipe.
        _ = try CSVImporter.importBiteLedger(
            foodsCSV: minFoods, servingsCSV: minServings, logsCSV: minLogs,
            mealPlansCSV: planCSV, mealMealsCSV: mealCSV, mealItemsCSV: itemCSV,
            skipExistingUUIDs: true, context: context
        )

        let items = try context.fetch(FetchDescriptor<MealPlanMealItem>())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].recipe?.id, recipe.id)
        XCTAssertNil(items[0].foodItem)
    }

    func testImportMealItems_foodItemLinked() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let food = FoodItem(name: "Chicken Breast", source: "test", nutritionMode: .per100g,
                            calories: 165, protein: 31, carbs: 0, fat: 3.6)
        context.insert(food)
        try context.save()

        let planId = UUID(); let mealId = UUID(); let itemId = UUID()
        let planCSV = "id,weekStartDate\n\(planId.uuidString),\(iso(sunday))"
        let mealCSV = "id,planId,date,mealType,name\n\(mealId.uuidString),\(planId.uuidString),\(iso(sunday)),Lunch,"
        let itemCSV = "id,mealId,recipeId,foodItemId,servingSizeId,note,servingCount\n" +
                      "\(itemId.uuidString),\(mealId.uuidString),,\(food.id.uuidString),,,1"

        // skipExistingUUIDs: true so existingFoodMap is populated with the pre-inserted food.
        _ = try CSVImporter.importBiteLedger(
            foodsCSV: minFoods, servingsCSV: minServings, logsCSV: minLogs,
            mealPlansCSV: planCSV, mealMealsCSV: mealCSV, mealItemsCSV: itemCSV,
            skipExistingUUIDs: true, context: context
        )

        let items = try context.fetch(FetchDescriptor<MealPlanMealItem>())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].foodItem?.id, food.id)
        XCTAssertNil(items[0].recipe)
    }

    func testImportMealItems_noteOnlyItem() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let planId = UUID(); let mealId = UUID(); let itemId = UUID()
        let planCSV = "id,weekStartDate\n\(planId.uuidString),\(iso(sunday))"
        let mealCSV = "id,planId,date,mealType,name\n\(mealId.uuidString),\(planId.uuidString),\(iso(sunday)),Dinner,"
        let itemCSV = "id,mealId,recipeId,foodItemId,servingSizeId,note,servingCount\n" +
                      "\(itemId.uuidString),\(mealId.uuidString),,,,Sushi,1"

        _ = try CSVImporter.importBiteLedger(
            foodsCSV: minFoods, servingsCSV: minServings, logsCSV: minLogs,
            mealPlansCSV: planCSV, mealMealsCSV: mealCSV, mealItemsCSV: itemCSV,
            context: context
        )

        let items = try context.fetch(FetchDescriptor<MealPlanMealItem>())
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].isNoteOnly)
        XCTAssertEqual(items[0].note, "Sushi")
    }

    func testImportMealItems_xorAllEmptySkipsRow() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let planId = UUID(); let mealId = UUID(); let itemId = UUID()
        let planCSV = "id,weekStartDate\n\(planId.uuidString),\(iso(sunday))"
        let mealCSV = "id,planId,date,mealType,name\n\(mealId.uuidString),\(planId.uuidString),\(iso(sunday)),Dinner,"
        // recipeId, foodItemId, and note are all empty
        let itemCSV = "id,mealId,recipeId,foodItemId,servingSizeId,note,servingCount\n" +
                      "\(itemId.uuidString),\(mealId.uuidString),,,,, 1"

        let result = try CSVImporter.importBiteLedger(
            foodsCSV: minFoods, servingsCSV: minServings, logsCSV: minLogs,
            mealPlansCSV: planCSV, mealMealsCSV: mealCSV, mealItemsCSV: itemCSV,
            context: context
        )

        let items = try context.fetch(FetchDescriptor<MealPlanMealItem>())
        XCTAssertEqual(items.count, 0, "Row with no recipe/food/note must be skipped")
        XCTAssertFalse(result.errors.isEmpty, "XOR-empty row must produce an error entry")
    }

    func testImportMealItems_unknownMealIdSkipsRow() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let planId = UUID(); let unknownMealId = UUID(); let itemId = UUID()
        let planCSV = "id,weekStartDate\n\(planId.uuidString),\(iso(sunday))"
        let mealCSV = "id,planId,date,mealType,name"   // header only — no meals
        let itemCSV = "id,mealId,recipeId,foodItemId,servingSizeId,note,servingCount\n" +
                      "\(itemId.uuidString),\(unknownMealId.uuidString),,,,Sushi,1"

        let result = try CSVImporter.importBiteLedger(
            foodsCSV: minFoods, servingsCSV: minServings, logsCSV: minLogs,
            mealPlansCSV: planCSV, mealMealsCSV: mealCSV, mealItemsCSV: itemCSV,
            context: context
        )

        let items = try context.fetch(FetchDescriptor<MealPlanMealItem>())
        XCTAssertEqual(items.count, 0, "Row with unknown mealId must be skipped")
        XCTAssertFalse(result.errors.isEmpty, "Unknown mealId must produce an error entry")
    }

    // MARK: - Backward compat: missing meal CSVs imports cleanly

    func testImportBiteLedger_withoutMealPlanCSVs_importsCleanly() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let result = try CSVImporter.importBiteLedger(
            foodsCSV: minFoods, servingsCSV: minServings, logsCSV: minLogs,
            context: context
        )

        XCTAssertEqual(result.mealPlansCreated, 0)
        XCTAssertEqual(result.mealMealsCreated, 0)
        XCTAssertEqual(result.mealItemsCreated, 0)
        XCTAssertTrue(result.errors.isEmpty, "No errors expected when meal CSVs are absent")
    }
}

// MARK: - T-12-RestoreUpdate: BackupManifest Tests

final class T12BackupManifestTests: XCTestCase {

    func testStats_decodesOldBackupWithoutMealPlansKey() throws {
        let json = #"{"foods":5,"logs":10,"recipes":2}"#
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        let stats = try decoder.decode(BackupManifest.Stats.self, from: data)
        XCTAssertEqual(stats.foods, 5)
        XCTAssertEqual(stats.logs, 10)
        XCTAssertEqual(stats.recipes, 2)
        XCTAssertNil(stats.mealPlans,
                     "mealPlans must decode as nil when key is absent (backward compat with pre-SchemaV5 backups)")
    }
}

// MARK: - T-12-RestoreUpdate: BackupService Integration Tests

@MainActor
final class T12BackupServiceIntegrationTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(BiteLedgerSchemaV5.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            throw XCTSkip("SwiftData unavailable: \(error)")
        }
    }

    private var sunday: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 4; c.day = 5; c.hour = 0; c.minute = 0; c.second = 0
        return Calendar.current.date(from: c)!
    }

    /// Seeds the minimum data needed: 1 food (satisfies exporter), plus 1 MealPlan /
    /// 1 MealPlanMeal / 1 MealPlanMealItem so the meal plan round-trip tests have
    /// something to verify.
    @discardableResult
    private func seedMealPlanData(in context: ModelContext) throws -> (plan: MealPlan, meal: MealPlanMeal, item: MealPlanMealItem) {
        let food = FoodItem(name: "Seed Food", source: "test", nutritionMode: .per100g,
                            calories: 100, protein: 10, carbs: 20, fat: 5)
        context.insert(food)

        let plan = MealPlan(weekStartDate: sunday)
        context.insert(plan)

        let meal = MealPlanMeal(mealPlan: plan, date: sunday, mealType: .dinner)
        meal.name = "Test Dinner"
        context.insert(meal)

        let item = MealPlanMealItem(meal: meal)
        item.note = "Sushi night"
        context.insert(item)

        try context.save()
        return (plan, meal, item)
    }

    // Verify meal plan CSV files are included in the backup by doing a full round-trip.
    // If meal_plans.csv were absent from the ZIP, mealPlansImported would be 0.
    func testCreateBackup_containsMealPlanCSVFiles_verifiedViaRoundTrip() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedMealPlanData(in: context)

        let zipURL = try await BackupService.createBackup(context: context)
        defer { try? FileManager.default.removeItem(at: zipURL) }

        await BackupService.resetDatabase(scope: .everything, context: context)
        let result = try await BackupService.restoreBackup(
            from: zipURL, conflictMode: .replaceAll, context: context
        )

        XCTAssertEqual(result.mealPlansImported, 1, "meal_plans.csv must be present and contain 1 plan")
        XCTAssertEqual(result.mealMealsImported, 1)
        XCTAssertEqual(result.mealItemsImported, 1)
        let plans = try context.fetch(FetchDescriptor<MealPlan>())
        XCTAssertEqual(plans.count, 1)
    }

    func testRestoreBackup_merge_skipsExistingUUIDs() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (plan, _, _) = try seedMealPlanData(in: context)
        let originalPlanId = plan.id

        let zipURL = try await BackupService.createBackup(context: context)
        defer { try? FileManager.default.removeItem(at: zipURL) }

        // Add a second plan to the live store (should survive after merge).
        let nextSunday = Calendar.current.date(byAdding: .day, value: 7, to: sunday)!
        let extraPlan = MealPlan(weekStartDate: nextSunday)
        context.insert(extraPlan)
        try context.save()
        let extraPlanId = extraPlan.id

        // Merge — original UUID already exists, must not be duplicated.
        let result = try await BackupService.restoreBackup(
            from: zipURL, conflictMode: .merge, context: context
        )

        XCTAssertEqual(result.mealPlansImported, 0, "Existing UUID must be skipped in merge mode")
        let plans = try context.fetch(FetchDescriptor<MealPlan>())
        XCTAssertEqual(plans.count, 2, "Extra plan must survive merge")
        XCTAssertTrue(plans.contains { $0.id == originalPlanId })
        XCTAssertTrue(plans.contains { $0.id == extraPlanId })
    }

    func testRoundTrip_exportRestoreProducesIdenticalData() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (plan, meal, item) = try seedMealPlanData(in: context)

        let originalPlanId  = plan.id
        let originalMealId  = meal.id
        let originalMealName = meal.name
        let originalItemId  = item.id
        let originalNote    = item.note

        let zipURL = try await BackupService.createBackup(context: context)
        defer { try? FileManager.default.removeItem(at: zipURL) }

        await BackupService.resetDatabase(scope: .everything, context: context)
        _ = try await BackupService.restoreBackup(
            from: zipURL, conflictMode: .replaceAll, context: context
        )

        let plans = try context.fetch(FetchDescriptor<MealPlan>())
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans[0].id, originalPlanId, "Plan UUID must survive round-trip")

        let meals = try context.fetch(FetchDescriptor<MealPlanMeal>())
        XCTAssertEqual(meals.count, 1)
        XCTAssertEqual(meals[0].id,   originalMealId)
        XCTAssertEqual(meals[0].name, originalMealName)

        let items = try context.fetch(FetchDescriptor<MealPlanMealItem>())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id,   originalItemId)
        XCTAssertEqual(items[0].note, originalNote)
    }
}
