//
//  BiteLedgerApp.swift
//  BiteLedger
//
//  Created by Craig Faist on 2/16/26.
//

import SwiftUI
import SwiftData
import CoreData
import BiteLedgerCore

@main
struct BiteLedgerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            FoodItem.self,
            FoodLog.self,
            ServingSize.self,
            UserPreferences.self,
            Recipe.self,
            RecipeIngredient.self,
            CanonicalFood.self,
            ServingConversion.self,
            FallbackSource.self,
        ])

        // Store in the shared App Group container so RecipeCard can access the same
        // food library. Both targets must have the App Group capability enabled in
        // Xcode → Signing & Capabilities → + App Groups → group.com.ridepro.biteledger.
        //
        // cloudKitDatabase: .none — CloudKit capability in entitlements would cause
        // SwiftData to attempt CloudKit integration unless explicitly disabled here.
        //
        // NOTE: First launch after this change will create a fresh store at the new
        // App Group path. Export your data (Settings → Export) before updating, then
        // re-import (Settings → Import CSV) after.
        let groupID = "group.com.ridepro.biteledger"
        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            fatalError("""
                App Group '\(groupID)' is not configured.
                In Xcode: select the BiteLedger target → Signing & Capabilities
                → + Capability → App Groups → add group.com.ridepro.biteledger.
                """)
        }
        let storeURL = containerURL.appendingPathComponent("biteledger.store")
        do {
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            SafeContentView(modelContainer: sharedModelContainer)
        }
        .modelContainer(sharedModelContainer)
    }
}

struct SafeContentView: View {
    let modelContainer: ModelContainer
    @State private var seedingProgress: (current: Int, total: Int)? = nil

    var body: some View {
        ZStack {
            ContentView()
                .task {
                    await backfillServingUnits(container: modelContainer)
                    await backfillStaleLogs(container: modelContainer)
                    await backfillServingAmounts(container: modelContainer)
                    await normalizeExistingPerServingFoods(container: modelContainer)
                    await backfillFoodLogGramAmounts(container: modelContainer)
                    await fixLoseItGramUnitFoods(container: modelContainer)
                    await IngredientSeeder.seedIfNeeded(container: modelContainer) { current, total in
                        seedingProgress = (current, total)
                    }
                    seedingProgress = nil
                    await CanonicalFoodSeeder.seedIfNeeded(container: modelContainer)
                }

            if let progress = seedingProgress {
                IngredientSeedingOverlay(current: progress.current, total: progress.total)
            }
        }
    }
}

private struct IngredientSeedingOverlay: View {
    let current: Int
    let total: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView(value: Double(current), total: Double(max(total, 1)))
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .frame(width: 240)
                Text("Building ingredient database…")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("\(current) of \(total)")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}

/// Backfill for servings whose `unit` field is stale after a label edit.
///
/// When FoodItemEditorView changed a serving label from "g" to e.g. "1 cup" but
/// didn't update the `unit` field, `unit` stays "g" while `gramWeight` is now 42.
/// `FoodLogEditView.resolvedQuantity` then reads `unit="g"` and thinks the serving
/// is still gram-based, returning the raw gram count (60) as serving count → 9,600 cal.
///
/// Fix:
/// 1. Update `serving.unit` to match the parsed label.
/// 2. If logs stored quantity as grams (1 serving = 1g), rescale to new serving count.
///
/// Safe to run on every launch — the condition (unit="g" AND gramWeight>1 AND
/// label parses to non-gram) is false after the fix, so subsequent runs are no-ops.
@MainActor
private func backfillStaleLogs(container: ModelContainer) async {
    let context = container.mainContext
    do {
        let allServings = try context.fetch(FetchDescriptor<ServingSize>())
        let stale = allServings.filter { serving in
            // Must have unit="g" (gram) — indicates a gram-based origin
            guard serving.unit == ServingUnit.gram.rawValue,
                  let gw = serving.gramWeight, gw > 1 else { return false }
            // Label must parse to a non-gram unit — label was edited away from "g"
            let parsedUnit = ServingSizeParser.parse(serving.label)?.unit
                          ?? ServingSizeParser.parseUnit(serving.label)
            return parsedUnit != nil && parsedUnit != .gram && parsedUnit != .serving
        }
        guard !stale.isEmpty else { return }

        for serving in stale {
            guard let newGW = serving.gramWeight, newGW > 1 else { continue }
            let parsedUnit = ServingSizeParser.parse(serving.label)?.unit
                          ?? ServingSizeParser.parseUnit(serving.label)
            if let pu = parsedUnit {
                serving.unit = pu.rawValue
            }
            // Rescale any FoodLog.quantity that was stored as grams
            let servingId = serving.id
            let logs = try context.fetch(FetchDescriptor<FoodLog>(
                predicate: #Predicate { $0.servingSize?.id == servingId }
            ))
            for log in logs {
                log.quantity = log.quantity / newGW
            }
        }
        try context.save()
        print("✅ backfillStaleLogs: fixed \(stale.count) serving(s)")
    } catch {
        print("⚠️ backfillStaleLogs failed: \(error)")
    }
}

/// One-time migration: converts all perServing FoodItems to per100g in place.
///
/// Resolution order for gramWeightPerServing:
///   1. defaultServing.gramWeight (actual gram weight set at import time)
///   2. Density table estimate from unit + food name (volume foods)
///   3. 100g nominal — values unchanged, serving gramWeight set to 100
///
/// Safe to run on every launch — skips foods already in per100g mode.
/// Must run BEFORE backfillFoodLogGramAmounts so servings have gramWeight set.
@MainActor
private func normalizeExistingPerServingFoods(container: ModelContainer) async {
    let context = container.mainContext
    do {
        let foods = try context.fetch(FetchDescriptor<FoodItem>())
        let perServingFoods = foods.filter { $0.nutritionMode == .perServing }
        guard !perServingFoods.isEmpty else { return }

        for food in perServingFoods {
            let defaultServing = food.defaultServing

            // Determine effective gram weight
            let gramWeight: Double?
            if let gw = defaultServing?.gramWeight, gw > 0 {
                gramWeight = gw
            } else if let unitStr = defaultServing?.unit,
                      let su = ServingUnit.fromAbbreviation(unitStr),
                      su != .serving, su != .container {
                let amount = defaultServing?.amount ?? 1.0
                let density = ServingUnit.densityFor(foodType: FoodType.infer(from: food.name))
                let estimated = su.toGrams(amount: amount, density: density)
                gramWeight = estimated > 0 ? estimated : nil
            } else {
                gramWeight = nil  // will use 100g nominal
            }

            let effectiveGrams = gramWeight ?? 100.0
            food.normalizeToPerHundredGrams(gramWeightPerServing: gramWeight)

            // Ensure all servings for this food have gramWeight set
            if let serving = defaultServing, serving.gramWeight == nil {
                serving.gramWeight = effectiveGrams
            }
        }
        try context.save()
        print("✅ normalizeExistingPerServingFoods: normalized \(perServingFoods.count) food(s)")
    } catch {
        print("⚠️ normalizeExistingPerServingFoods failed: \(error)")
    }
}

/// Backfill `ServingSize.amount` from the label parser for all records where amount == 1.0.
/// Idempotent — parser result of 1.0 leaves the field unchanged.
/// Runs on every launch but is a no-op after all records are correct.
@MainActor
private func backfillServingAmounts(container: ModelContainer) async {
    let context = container.mainContext
    do {
        let servings = try context.fetch(FetchDescriptor<ServingSize>())
        var changed = 0
        for serving in servings {
            if let parsed = ServingSizeParser.parse(serving.label),
               parsed.amount != serving.amount {
                serving.amount = parsed.amount
                changed += 1
            }
        }
        if changed > 0 {
            try context.save()
            print("✅ backfillServingAmounts: updated \(changed) serving(s)")
        }
    } catch {
        print("⚠️ backfillServingAmounts failed: \(error)")
    }
}

/// Backfill `FoodLog.gramAmount` for logs created before schema V3.
/// Uses quantity × servingSize.gramWeight. Falls back to 100g/serving for no-gram foods.
/// Safe to run on every launch — skips logs where gramAmount is already non-zero.
@MainActor
private func backfillFoodLogGramAmounts(container: ModelContainer) async {
    let context = container.mainContext
    do {
        let logs = try context.fetch(FetchDescriptor<FoodLog>())
        let unset = logs.filter { $0.gramAmount == 0 }
        guard !unset.isEmpty else { return }
        for log in unset {
            let resolvedServing = log.servingSize ?? log.foodItem?.defaultServing
            if let gw = resolvedServing?.gramWeight {
                log.gramAmount = log.quantity * gw
            } else {
                // No gram data — try density-based estimate from unit
                let unitStr = resolvedServing?.unit ?? log.loggedUnit
                let servingUnit = unitStr.flatMap { ServingUnit.fromAbbreviation($0) }
                if let su = servingUnit {
                    let amount = resolvedServing?.amount ?? log.loggedAmount ?? 1.0
                    let density = ServingUnit.densityFor(
                        foodType: FoodType.infer(from: log.foodItem?.name ?? "")
                    )
                    log.gramAmount = su.toGrams(amount: amount * log.quantity, density: density)
                } else {
                    log.gramAmount = log.quantity * 100
                }
            }
            // Also backfill loggedAmount/loggedUnit if missing
            if log.loggedAmount == nil { log.loggedAmount = log.quantity }
            if log.loggedUnit == nil { log.loggedUnit = resolvedServing?.unit }
        }
        try context.save()
        print("✅ backfillFoodLogGramAmounts: set gramAmount on \(unset.count) log(s)")
    } catch {
        print("⚠️ backfillFoodLogGramAmounts failed: \(error)")
    }
}

/// One-time backfill: populate `unit` on ServingSize records created before schema V2.
/// Safe to run on every launch — skips records that already have a unit set.
@MainActor
private func backfillServingUnits(container: ModelContainer) async {
    let context = container.mainContext
    do {
        let servings = try context.fetch(
            FetchDescriptor<ServingSize>(
                predicate: #Predicate { $0.unit == nil }
            )
        )
        guard !servings.isEmpty else { return }
        for serving in servings {
            if let parsed = ServingSizeParser.parse(serving.label),
               parsed.unit != .serving {
                serving.unit = parsed.unit.rawValue
            } else if let unit = ServingSizeParser.parseUnit(serving.label) {
                serving.unit = unit.rawValue
            }
        }
        try context.save()
        print("✅ Backfilled unit on \(servings.count) ServingSize records")
    } catch {
        print("⚠️ backfillServingUnits failed: \(error)")
    }
}

/// One-time fix for LoseIt-imported foods whose per-100g nutrition is stored at the wrong scale.
///
/// Root cause: the LoseIt importer divided total calories by the logged quantity to get
/// cal-per-1-unit, then called normalizeToPerHundredGrams(nil) which used factor=1.0,
/// treating cal/gram as cal/100g.  Result for "80g oatmeal, 300 cal":
///   calPer1 = 300/80 = 3.75  →  stored as 3.75 cal/100g  (should be 375 cal/100g)
///
/// This function also restores gramWeight=nil servings so FoodLogEditView stops using
/// the density-estimation fallback and uses the real gram weight instead.
///
/// Safe to run on every launch — skips foods whose calories are already in range.
@MainActor
private func fixLoseItGramUnitFoods(container: ModelContainer) async {
    let context = container.mainContext
    do {
        // Only look at LoseIt-imported foods
        let foods = try context.fetch(
            FetchDescriptor<FoodItem>(
                predicate: #Predicate { $0.source.contains("LoseIt") }
            )
        )
        guard !foods.isEmpty else { return }

        var nutritionFixed = 0
        var gramWeightFixed = 0

        for food in foods {
            guard let serving = food.defaultServing ?? food.servingSizes.first else { continue }
            let unitStr = serving.unit ?? ""

            // --- Nutrition scale fix (gram and oz units only) ---
            // If calories < 10 the value is per-1-gram (or per-1-oz), not per-100g.
            // Most real foods are > 10 cal/100g; wrong values are typically 0.1–9.
            let scaleFactor: Double
            switch unitStr {
            case "gram", "g":
                scaleFactor = food.calories < 10 ? 100.0 : 1.0
                if scaleFactor != 1.0 {
                    serving.gramWeight = 1.0   // 1 gram serving = 1g (not the 100g nominal)
                }
            case "oz", "ounce":
                scaleFactor = food.calories < 10 ? (100.0 / 28.3495) : 1.0
                if scaleFactor != 1.0 {
                    serving.gramWeight = 28.3495
                }
            default:
                scaleFactor = 1.0
            }

            if scaleFactor != 1.0 {
                food.calories           *= scaleFactor
                food.protein            *= scaleFactor
                food.carbs              *= scaleFactor
                food.fat                *= scaleFactor
                food.fiber               = food.fiber.map           { $0 * scaleFactor }
                food.sugar               = food.sugar.map           { $0 * scaleFactor }
                food.saturatedFat        = food.saturatedFat.map    { $0 * scaleFactor }
                food.transFat            = food.transFat.map        { $0 * scaleFactor }
                food.polyunsaturatedFat  = food.polyunsaturatedFat.map { $0 * scaleFactor }
                food.monounsaturatedFat  = food.monounsaturatedFat.map { $0 * scaleFactor }
                food.sodium              = food.sodium.map          { $0 * scaleFactor }
                food.cholesterol         = food.cholesterol.map     { $0 * scaleFactor }
                food.potassium           = food.potassium.map       { $0 * scaleFactor }
                food.calcium             = food.calcium.map         { $0 * scaleFactor }
                food.iron                = food.iron.map            { $0 * scaleFactor }
                food.magnesium           = food.magnesium.map       { $0 * scaleFactor }
                food.zinc                = food.zinc.map            { $0 * scaleFactor }
                food.vitaminA            = food.vitaminA.map        { $0 * scaleFactor }
                food.vitaminC            = food.vitaminC.map        { $0 * scaleFactor }
                food.vitaminD            = food.vitaminD.map        { $0 * scaleFactor }
                food.vitaminE            = food.vitaminE.map        { $0 * scaleFactor }
                food.vitaminK            = food.vitaminK.map        { $0 * scaleFactor }
                food.vitaminB6           = food.vitaminB6.map       { $0 * scaleFactor }
                food.vitaminB12          = food.vitaminB12.map      { $0 * scaleFactor }
                food.folate              = food.folate.map          { $0 * scaleFactor }
                food.choline             = food.choline.map         { $0 * scaleFactor }
                food.caffeine            = food.caffeine.map        { $0 * scaleFactor }
                nutritionFixed += 1
            }

            // --- gramWeight restore for all volume-unit servings with nil gramWeight ---
            // Without a gramWeight anchor, FoodLogEditView falls back to density estimation,
            // which gives wrong calories for cup/tablespoon/teaspoon servings.
            // Restoring gramWeight=100 (the nominal the LoseIt importer intended) fixes this.
            if serving.gramWeight == nil && scaleFactor == 1.0 {
                serving.gramWeight = 100.0
                gramWeightFixed += 1
            }
        }

        if nutritionFixed > 0 || gramWeightFixed > 0 {
            try context.save()
            print("✅ fixLoseItGramUnitFoods: fixed nutrition on \(nutritionFixed) food(s), gramWeight on \(gramWeightFixed) serving(s)")
        }
    } catch {
        print("⚠️ fixLoseItGramUnitFoods failed: \(error)")
    }
}
