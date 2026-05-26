//
//  IngredientSeeder.swift
//  BiteLedgerCore
//
//  Seeds ~510 common recipe ingredients. On user devices, reads from a bundled
//  `ingredients.json` resource (instant, no network). On the developer's first run
//  (when the bundle resource is absent), falls back to the USDA API and then exports
//  a JSON snapshot to the documents directory — copy that file into the Xcode project
//  as a bundle resource to eliminate the API round-trip for all future users.
//
//  To force a re-seed: bump `currentVersion` and regenerate the JSON.
//

import SwiftData
import Foundation

// MARK: - Public API

public enum IngredientSeeder {

    /// Bump to force a full re-seed on the next launch (also regenerates the bundle JSON).
    public static let currentVersion = "usda_seed_v4"

    /// Seeds common recipe ingredients. Safe to call on every launch — no-op after first run.
    /// `onProgress` is called on the main actor with (completedCount, totalCount).
    @MainActor
    public static func seedIfNeeded(
        container: ModelContainer,
        onProgress: (@MainActor (_ current: Int, _ total: Int) -> Void)? = nil
    ) async {
        let context = container.mainContext

        let allFoods = (try? context.fetch(FetchDescriptor<FoodItem>())) ?? []
        let alreadySeeded = allFoods.contains { $0.source == currentVersion }
        if alreadySeeded {
            // Patch: insert staple foods absent from the original seed without re-seeding
            // everything (a full re-seed would nullify all existing recipe ingredient links).
            patchMissingStaples(context: context, existingFoods: allFoods)
            return
        }

        // Remove previous seed foods so there are no stale duplicates.
        // IMPORTANT: ServingSize has no declared inverse to RecipeIngredient, so SwiftData
        // cannot auto-nullify RecipeIngredient.servingSize when a ServingSize is cascade-deleted.
        // Explicitly break those references BEFORE deletion to prevent the "model instance was
        // invalidated" fatal error.
        let old = allFoods.filter {
            $0.source.hasPrefix("built_in") ||
            ($0.source.hasPrefix("usda_seed") && $0.source != currentVersion)
        }
        if !old.isEmpty {
            let oldServingIDs = Set(old.flatMap { $0.servingSizes.map { $0.persistentModelID } })
            let allIngredients = (try? context.fetch(FetchDescriptor<RecipeIngredient>())) ?? []
            for ing in allIngredients where ing.servingSize.map({ oldServingIDs.contains($0.persistentModelID) }) ?? false {
                ing.servingSize = nil
            }
            let allLogs = (try? context.fetch(FetchDescriptor<FoodLog>())) ?? []
            for log in allLogs where log.servingSize.map({ oldServingIDs.contains($0.persistentModelID) }) ?? false {
                log.servingSize = nil
            }
            old.forEach { context.delete($0) }
            try? context.save()
        }

        // Fast path: read from bundled JSON resource inside BiteLedgerCore package
        if let bundleURL = Bundle.module.url(forResource: "ingredients", withExtension: "json"),
           let data = try? Data(contentsOf: bundleURL),
           let bundle = try? JSONDecoder().decode(SeedBundle.self, from: data),
           bundle.version == currentVersion {
            await seedFromBundle(bundle, context: context, onProgress: onProgress)
            print("✅ IngredientSeeder \(currentVersion): seeded \(bundle.ingredients.count) ingredients from bundle")
            return
        }

        // Slow path: fetch from USDA API (developer first run)
        print("ℹ️ IngredientSeeder: no bundle found — fetching from USDA API (developer first run)")
        var exported: [SeedItem] = []
        await seedFromUSDA(context: context, onProgress: onProgress, collected: &exported)

        // Auto-export JSON so developer can copy it into the bundle
        exportBundleJSON(SeedBundle(version: currentVersion, ingredients: exported))
        print("✅ IngredientSeeder \(currentVersion): seeded \(exported.count) ingredients from USDA — bundle exported to Documents")
    }
}

// MARK: - Staple Patch

/// Inserts common ingredients that were missing from an already-seeded version.
/// Safe to call on every launch: checks by name before inserting, never deletes anything.
/// This avoids a version bump (which would nullify all existing recipe ingredient links).
@MainActor
private func patchMissingStaples(context: ModelContext, existingFoods: [FoodItem]) {
    struct Staple {
        let name: String
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let sodium: Double?
        let servings: [(label: String, grams: Double, isDefault: Bool, amount: Double, unit: String)]
    }

    let staples: [Staple] = [
        // Baking soda (sodium bicarbonate): ~27.4% sodium by weight, zero calories.
        // USDA FoodData Central: "Leavening agents, baking soda"
        Staple(name: "Baking Soda", calories: 0, protein: 0, carbs: 0, fat: 0, sodium: 27360, servings: [
            ("1/4 tsp", 1.15, true,  0.25, "tsp"),
            ("1/2 tsp", 2.3,  false, 0.5,  "tsp"),
            ("3/4 tsp", 3.45, false, 0.75, "tsp"),
            ("1 tsp",   4.6,  false, 1.0,  "tsp"),
            ("1 tbsp",  13.8, false, 1.0,  "tbsp"),
        ]),
    ]

    let existingNames = Set(existingFoods.map { $0.name.lowercased() })
    var didInsert = false

    for staple in staples {
        guard !existingNames.contains(staple.name.lowercased()) else { continue }
        let food = FoodItem(
            name: staple.name,
            source: IngredientSeeder.currentVersion,
            nutritionMode: .per100g,
            calories: staple.calories,
            protein: staple.protein,
            carbs: staple.carbs,
            fat: staple.fat,
            sodium: staple.sodium
        )
        context.insert(food)
        for (i, sv) in staple.servings.enumerated() {
            let s = ServingSize(
                label: sv.label,
                gramWeight: sv.grams,
                isDefault: sv.isDefault,
                sortOrder: i,
                unit: sv.unit,
                amount: sv.amount
            )
            s.foodItem = food
            context.insert(s)
        }
        didInsert = true
    }
    if didInsert { try? context.save() }
}

// MARK: - Codable Bundle Types

private struct SeedBundle: Codable {
    let version: String
    let ingredients: [SeedItem]
}

private struct SeedItem: Codable {
    let name: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double?
    let sugar: Double?
    let saturatedFat: Double?
    let sodium: Double?
    let cholesterol: Double?
    let potassium: Double?
    let calcium: Double?
    let iron: Double?
    let vitaminA: Double?
    let vitaminC: Double?
    let servings: [SeedServing]
}

private struct SeedServing: Codable {
    let label: String
    let gramWeight: Double?
    let unit: String?
    let amount: Double
    let isDefault: Bool
}

// MARK: - Seed from Bundle (fast path)

@MainActor
private func seedFromBundle(
    _ bundle: SeedBundle,
    context: ModelContext,
    onProgress: (@MainActor (Int, Int) -> Void)?
) async {
    let total = bundle.ingredients.count
    onProgress?(0, total)
    for (i, item) in bundle.ingredients.enumerated() {
        let food = FoodItem(
            name:         item.name,
            source:       IngredientSeeder.currentVersion,
            nutritionMode: .per100g,
            calories:     item.calories,
            protein:      item.protein,
            carbs:        item.carbs,
            fat:          item.fat,
            fiber:        item.fiber,
            sugar:        item.sugar,
            saturatedFat: item.saturatedFat,
            sodium:       item.sodium,
            cholesterol:  item.cholesterol,
            potassium:    item.potassium,
            calcium:      item.calcium,
            iron:         item.iron,
            vitaminA:     item.vitaminA,
            vitaminC:     item.vitaminC
        )
        context.insert(food)
        for serving in item.servings {
            let s = ServingSize(
                label:      serving.label,
                gramWeight: serving.gramWeight,
                isDefault:  serving.isDefault,
                sortOrder:  item.servings.firstIndex(where: { $0.label == serving.label }) ?? 0,
                unit:       serving.unit,
                amount:     serving.amount
            )
            s.foodItem = food
            context.insert(s)
        }
        if (i + 1) % 20 == 0 { try? context.save() }
        onProgress?(i + 1, total)
    }
    try? context.save()
}

// MARK: - Seed from USDA API (slow path / developer)

@MainActor
private func seedFromUSDA(
    context: ModelContext,
    onProgress: (@MainActor (Int, Int) -> Void)?,
    collected: inout [SeedItem]
) async {
    let total = entries.count
    onProgress?(0, total)

    for (i, entry) in entries.enumerated() {
        if let item = await fetchAndSeed(entry: entry, context: context) {
            collected.append(item)
        }
        if (i + 1) % 10 == 0 { try? context.save() }
        onProgress?(i + 1, total)
        if (i + 1) % 10 == 0 && i + 1 < entries.count {
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms rate-limit pause
        }
    }
    try? context.save()
}

@MainActor
private func fetchAndSeed(entry: Entry, context: ModelContext) async -> SeedItem? {
    guard let results = try? await USDAFoodDataService.shared.searchFoods(
        query: entry.searchTerm, pageSize: 10
    ), !results.isEmpty else { return nil }

    let scored = results.map { ($0, relevance(name: $0.description, term: entry.searchTerm)) }
    guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 > 0 else { return nil }

    guard let detail = try? await USDAFoodDataService.shared.getFoodDetails(fdcId: best.0.fdcId) else { return nil }
    let product = detail.toProductInfo()
    guard let n = product.nutriments, let cal = n.energyKcal100g?.value, cal >= 0 else { return nil }

    let food = FoodItem(
        name:         entry.name,
        source:       IngredientSeeder.currentVersion,
        nutritionMode: .per100g,
        calories:     cal,
        protein:      n.proteins100g?.value       ?? 0,
        carbs:        n.carbohydrates100g?.value  ?? 0,
        fat:          n.fat100g?.value            ?? 0,
        fiber:        n.fiber100g?.value,
        sugar:        n.sugars100g?.value,
        saturatedFat: n.saturatedFat100g?.value,
        sodium:       n.sodium100g.map      { $0.value * 1_000 },
        cholesterol:  n.cholesterol100g.map { $0.value * 1_000 },
        potassium:    n.potassium100g.map   { $0.value * 1_000 },
        calcium:      n.calcium100g.map     { $0.value * 1_000 },
        iron:         n.iron100g.map        { $0.value * 1_000 },
        vitaminA:     n.vitaminA100g.map    { $0.value * 1_000_000 },
        vitaminC:     n.vitaminC100g.map    { $0.value * 1_000 }
    )
    context.insert(food)

    var seedServings: [SeedServing] = []
    let portions = product.portions?.isEmpty == false ? product.portions! : nil

    if let portions = portions {
        for (idx, portion) in portions.enumerated() {
            let amtStr = portion.amount == portion.amount.rounded()
                ? String(Int(portion.amount)) : String(format: "%.2g", portion.amount)
            let label = "\(amtStr) \(portion.modifier)"
            let unitAbbr = ServingSizeParser.parseUnit(portion.modifier)?.abbreviation
            let serving = ServingSize(
                label:      label,
                gramWeight: portion.gramWeight,
                isDefault:  idx == 0,
                sortOrder:  idx,
                unit:       unitAbbr,
                amount:     portion.amount
            )
            serving.foodItem = food
            context.insert(serving)
            seedServings.append(SeedServing(
                label: label, gramWeight: portion.gramWeight,
                unit: unitAbbr, amount: portion.amount, isDefault: idx == 0
            ))
        }
    } else {
        let serving = ServingSize(label: "100g", gramWeight: 100, isDefault: true, sortOrder: 0, unit: "g", amount: 100)
        serving.foodItem = food
        context.insert(serving)
        seedServings.append(SeedServing(label: "100g", gramWeight: 100, unit: "g", amount: 100, isDefault: true))
    }

    return SeedItem(
        name: entry.name,
        calories: cal,
        protein: n.proteins100g?.value ?? 0,
        carbs: n.carbohydrates100g?.value ?? 0,
        fat: n.fat100g?.value ?? 0,
        fiber: n.fiber100g?.value,
        sugar: n.sugars100g?.value,
        saturatedFat: n.saturatedFat100g?.value,
        sodium: n.sodium100g.map { $0.value * 1_000 },
        cholesterol: n.cholesterol100g.map { $0.value * 1_000 },
        potassium: n.potassium100g.map { $0.value * 1_000 },
        calcium: n.calcium100g.map { $0.value * 1_000 },
        iron: n.iron100g.map { $0.value * 1_000 },
        vitaminA: n.vitaminA100g.map { $0.value * 1_000_000 },
        vitaminC: n.vitaminC100g.map { $0.value * 1_000 },
        servings: seedServings
    )
}

// MARK: - Bundle JSON Export (developer workflow)

private func exportBundleJSON(_ bundle: SeedBundle) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(bundle),
          let jsonString = String(data: data, encoding: .utf8) else { return }

    // Write to Documents so it can be retrieved via Xcode's device container download
    if let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
        let fileURL = docsURL.appendingPathComponent("ingredients.json")
        try? data.write(to: fileURL)
        print("📦 INGREDIENT BUNDLE SAVED TO: \(fileURL.path)")
    }

    // Also print full JSON to the Xcode console so you can copy it directly.
    // In Xcode: expand the console, select all the text between the two markers, copy, paste into a new file.
    print("📦 ===== BEGIN ingredients.json =====")
    print(jsonString)
    print("📦 ===== END ingredients.json =====")
    print("📦 Copy the JSON above into a file named 'ingredients.json' and add it to both")
    print("📦 BiteLedger and BitePlan targets in Xcode as a bundle resource.")
}

// MARK: - Relevance Scoring

private func relevance(name: String, term: String) -> Int {
    let n = name.lowercased()
    let t = term.lowercased()
    if n == t { return 100 }
    let sep = CharacterSet.whitespaces.union(.punctuationCharacters)
    let nWords = Set(n.components(separatedBy: sep).filter { !$0.isEmpty })
    let tWords = t.components(separatedBy: sep).filter { !$0.isEmpty }
    if n.hasPrefix(t) {
        let after = n.dropFirst(t.count)
        if after.isEmpty || after.first == "," || after.first == " " { return 80 }
    }
    if !tWords.isEmpty, tWords.allSatisfy({ nWords.contains($0) }) { return 50 }
    if n.contains(t) { return 10 }
    return 0
}

// MARK: - Entry

private struct Entry {
    let name: String
    let searchTerm: String
    init(_ name: String, _ searchTerm: String? = nil) {
        self.name = name
        self.searchTerm = searchTerm ?? name
    }
}

// MARK: - Ingredient List (~510 items)

private let entries: [Entry] = [

    // ── Fats & Oils ──────────────────────────────────────────────────────────
    Entry("Butter",          "butter salted"),
    Entry("Unsalted Butter", "butter unsalted"),
    Entry("Olive Oil",       "oil olive salad or cooking"),
    Entry("Vegetable Oil",   "oil vegetable"),
    Entry("Canola Oil",      "oil canola"),
    Entry("Coconut Oil",     "oil coconut"),
    Entry("Sesame Oil",      "oil sesame salad or cooking"),
    Entry("Avocado Oil",     "oil avocado"),
    Entry("Shortening",      "shortening vegetable"),
    Entry("Lard",            "lard"),
    Entry("Grapeseed Oil",   "oil grapeseed"),
    Entry("Walnut Oil",      "oil walnut salad"),
    Entry("Flaxseed Oil",    "oil flaxseed"),
    Entry("MCT Oil",         "oil coconut"),

    // ── Dairy ────────────────────────────────────────────────────────────────
    Entry("Whole Milk",                "milk whole 3.25% milkfat"),
    Entry("2% Milk",                   "milk reduced fat 2% milkfat"),
    Entry("Skim Milk",                 "milk nonfat"),
    Entry("Buttermilk",                "milk buttermilk fluid"),
    Entry("Heavy Cream",               "cream fluid heavy whipping"),
    Entry("Half and Half",             "cream fluid half and half"),
    Entry("Whipping Cream",            "cream fluid light whipping"),
    Entry("Sour Cream",                "cream sour"),
    Entry("Cream Cheese",              "cheese cream"),
    Entry("Greek Yogurt",              "yogurt greek plain nonfat"),
    Entry("Plain Yogurt",              "yogurt plain whole milk"),
    Entry("Sweetened Condensed Milk",  "milk sweetened condensed canned"),
    Entry("Evaporated Milk",           "milk evaporated canned"),
    Entry("Dry Milk Powder",           "milk dry nonfat regular"),
    Entry("Buttermilk Powder",         "buttermilk dry"),
    Entry("Oat Milk",                  "beverages oat milk unenriched"),
    Entry("Almond Milk",               "milk almond unsweetened shelf stable"),
    Entry("Soy Milk",                  "soymilk original and vanilla unfortified"),
    Entry("Coconut Cream",             "cream coconut canned"),
    Entry("Condensed Coconut Milk",    "coconut cream canned"),

    // ── Cheese ───────────────────────────────────────────────────────────────
    Entry("Parmesan",       "cheese parmesan grated"),
    Entry("Mozzarella",     "cheese mozzarella whole milk"),
    Entry("Cheddar",        "cheese cheddar"),
    Entry("Feta",           "cheese feta"),
    Entry("Ricotta",        "cheese ricotta whole milk"),
    Entry("Gouda",          "cheese gouda"),
    Entry("Swiss Cheese",   "cheese swiss"),
    Entry("Goat Cheese",    "cheese goat soft"),
    Entry("Cottage Cheese", "cheese cottage 2% milkfat"),
    Entry("Monterey Jack",  "cheese monterey"),
    Entry("Pepper Jack",    "cheese monterey jack with jalapeno pepper"),
    Entry("Brie",           "cheese brie"),
    Entry("Gruyere",        "cheese gruyere"),
    Entry("Mascarpone",     "cheese mascarpone"),
    Entry("Burrata",        "cheese mozzarella whole milk"),
    Entry("Pecorino Romano","cheese romano"),
    Entry("Fontina",        "cheese fontina"),
    Entry("Provolone",      "cheese provolone"),
    Entry("Blue Cheese",    "cheese blue"),
    Entry("Manchego",       "cheese manchego"),
    Entry("Asiago",         "cheese asiago"),
    Entry("Havarti",        "cheese havarti"),
    Entry("Camembert",      "cheese camembert"),
    Entry("Muenster",       "cheese muenster"),
    Entry("Paneer",         "cheese paneer"),
    Entry("Cotija Cheese",  "cheese cotija"),
    Entry("Queso Fresco",   "cheese queso fresco"),
    Entry("American Cheese","cheese american"),
    Entry("Halloumi",       "cheese gruyere"),

    // ── Eggs ─────────────────────────────────────────────────────────────────
    Entry("Egg",        "egg whole raw fresh"),
    Entry("Egg White",  "egg white raw fresh"),
    Entry("Egg Yolk",   "egg yolk raw fresh"),

    // ── Flours & Baking Basics ───────────────────────────────────────────────
    Entry("All-Purpose Flour",  "wheat flour white all purpose"),
    Entry("Whole Wheat Flour",  "wheat flour whole grain"),
    Entry("Bread Flour",        "wheat flour white bread"),
    Entry("Cake Flour",         "wheat flour white cake"),
    Entry("Almond Flour",       "almond flour"),
    Entry("Oat Flour",          "oat flour"),
    Entry("Cornstarch",         "cornstarch"),
    Entry("Cornmeal",           "cornmeal whole grain yellow"),
    Entry("Baking Powder",      "baking powder"),
    Entry("Baking Soda",        "leavening agents baking soda"),
    Entry("Active Dry Yeast",   "yeast bakers dry active"),
    Entry("Instant Yeast",      "yeast bakers compressed"),
    Entry("Cream of Tartar",    "cream of tartar"),
    Entry("Rye Flour",          "flour rye medium"),
    Entry("Spelt Flour",        "spelt uncooked"),
    Entry("Buckwheat Flour",    "buckwheat flour whole groat"),
    Entry("Rice Flour",         "rice flour brown"),
    Entry("Coconut Flour",      "coconut flour"),
    Entry("Cassava Flour",      "cassava raw"),
    Entry("Teff Flour",         "teff uncooked"),
    Entry("Sorghum Flour",      "sorghum grain"),
    Entry("Semolina",           "wheat semolina unenriched"),
    Entry("Tapioca Starch",     "tapioca dry"),
    Entry("Potato Starch",      "potato flour"),
    Entry("Arrowroot Powder",   "arrowroot"),
    Entry("Xanthan Gum",        "xanthan gum"),
    Entry("Psyllium Husk",      "psyllium husks"),
    Entry("Vital Wheat Gluten", "vital wheat gluten"),
    Entry("Pectin",             "pectin dry mix"),
    Entry("Gelatin",            "gelatin dry powder unsweetened"),

    // ── Sweeteners ───────────────────────────────────────────────────────────
    Entry("Granulated Sugar",    "sugars granulated"),
    Entry("Brown Sugar",         "sugars brown"),
    Entry("Powdered Sugar",      "sugars powdered"),
    Entry("Honey",               "honey"),
    Entry("Maple Syrup",         "syrups maple"),
    Entry("Molasses",            "molasses"),
    Entry("Corn Syrup",          "syrups corn light"),
    Entry("Agave Nectar",        "agave syrup"),
    Entry("Coconut Sugar",       "sugars coconut"),
    Entry("Turbinado Sugar",     "sugar turbinado"),
    Entry("Erythritol",          "erythritol"),

    // ── Spices & Seasonings ──────────────────────────────────────────────────
    Entry("Salt",               "salt table"),
    Entry("Kosher Salt",        "salt kosher"),
    Entry("Black Pepper",       "spices pepper black"),
    Entry("White Pepper",       "spices pepper white"),
    Entry("Garlic Powder",      "spices garlic powder"),
    Entry("Onion Powder",       "spices onion powder"),
    Entry("Paprika",            "spices paprika"),
    Entry("Smoked Paprika",     "spices paprika smoked"),
    Entry("Cumin",              "spices cumin seed"),
    Entry("Chili Powder",       "spices chili powder"),
    Entry("Dried Oregano",      "spices oregano dried"),
    Entry("Dried Basil",        "spices basil dried"),
    Entry("Dried Thyme",        "spices thyme dried"),
    Entry("Dried Rosemary",     "spices rosemary dried"),
    Entry("Cayenne Pepper",     "spices pepper red or cayenne"),
    Entry("Red Pepper Flakes",  "spices pepper red crushed"),
    Entry("Cinnamon",           "spices cinnamon ground"),
    Entry("Nutmeg",             "spices nutmeg ground"),
    Entry("Turmeric",           "spices turmeric ground"),
    Entry("Ground Ginger",      "spices ginger ground"),
    Entry("Curry Powder",       "spices curry powder"),
    Entry("Italian Seasoning",  "spices italian seasoning"),
    Entry("Bay Leaves",         "spices bay leaf"),
    Entry("Coriander",          "spices coriander seed"),
    Entry("Allspice",           "spices allspice ground"),
    Entry("Cloves",             "spices cloves ground"),
    Entry("Mustard Powder",     "mustard powder dry"),
    Entry("Celery Salt",        "spices celery salt"),
    Entry("Fennel Seeds",       "spices fennel seed"),
    Entry("Star Anise",         "spices anise seed"),
    Entry("Chinese Five-Spice", "spices five spice powder"),
    Entry("Garam Masala",       "spices garam masala"),
    Entry("Fenugreek Seeds",    "spices fenugreek seed"),
    Entry("Ground Cardamom",    "spices cardamom"),
    Entry("Mustard Seeds",      "spices mustard seed yellow"),
    Entry("Dried Dill",         "spices dill weed dried"),
    Entry("Dried Mint",         "spices mint dried"),
    Entry("Mexican Oregano",    "spices oregano ground"),
    Entry("Za'atar",            "spices thyme dried"),
    Entry("Sumac",              "spices sumac"),
    Entry("Saffron",            "spices saffron"),
    Entry("Cardamom Pods",      "spices cardamom"),
    Entry("Smoked Salt",        "salt table"),

    // ── Extracts & Sauces ────────────────────────────────────────────────────
    Entry("Vanilla Extract",       "vanilla extract"),
    Entry("Almond Extract",        "extract almond imitation"),
    Entry("Peppermint Extract",    "vanilla extract"),
    Entry("Orange Extract",        "vanilla extract"),
    Entry("Lemon Extract",         "vanilla extract"),
    Entry("Soy Sauce",             "soy sauce made from soy tamari"),
    Entry("Fish Sauce",            "fish sauce ready to serve"),
    Entry("Worcestershire Sauce",  "sauce worcestershire"),
    Entry("Hot Sauce",             "sauce ready to serve hot chile"),
    Entry("Liquid Smoke",          "smoke flavoring"),
    Entry("Coconut Aminos",        "soy sauce made from soy"),
    Entry("Anchovy Paste",         "fish anchovy european raw"),

    // ── Aromatics ────────────────────────────────────────────────────────────
    Entry("Garlic",         "garlic raw"),
    Entry("Onion",          "onions raw"),
    Entry("Yellow Onion",   "onions yellow raw"),
    Entry("Red Onion",      "onions red raw"),
    Entry("Shallot",        "shallots raw"),
    Entry("Ginger Root",    "ginger root raw"),
    Entry("Green Onions",   "onions spring or scallions raw"),
    Entry("Leeks",          "leeks bulb and lower leaf raw"),
    Entry("Celery",         "celery raw"),
    Entry("Carrots",        "carrots raw"),
    Entry("Bell Pepper",    "peppers sweet red raw"),
    Entry("Jalapeño",       "peppers jalapeno raw"),
    Entry("Serrano Pepper", "peppers serrano raw"),
    Entry("Poblano Pepper", "peppers poblano raw"),
    Entry("Thai Chili",     "peppers hot chili red raw"),

    // ── Fresh Herbs ──────────────────────────────────────────────────────────
    Entry("Fresh Parsley",   "parsley fresh"),
    Entry("Fresh Cilantro",  "coriander cilantro leaves raw"),
    Entry("Fresh Basil",     "basil fresh"),
    Entry("Thai Basil",      "basil fresh"),
    Entry("Fresh Mint",      "mint fresh"),
    Entry("Fresh Dill",      "dill weed fresh"),
    Entry("Chives",          "chives raw"),
    Entry("Fresh Rosemary",  "rosemary fresh"),
    Entry("Fresh Thyme",     "thyme fresh"),
    Entry("Fresh Sage",      "sage fresh"),
    Entry("Fresh Tarragon",  "tarragon fresh"),
    Entry("Lemongrass",      "lemon grass citronella raw"),
    Entry("Curry Leaves",    "spices curry powder"),

    // ── Vegetables ───────────────────────────────────────────────────────────
    Entry("Tomato",           "tomatoes red raw"),
    Entry("Cherry Tomatoes",  "tomatoes cherry red raw"),
    Entry("Spinach",          "spinach raw"),
    Entry("Broccoli",         "broccoli raw"),
    Entry("Zucchini",         "squash summer zucchini raw"),
    Entry("Mushrooms",        "mushrooms white raw"),
    Entry("Cremini Mushrooms","mushrooms brown italian or crimini raw"),
    Entry("Portobello Mushrooms","mushrooms portabella raw"),
    Entry("Shiitake Mushrooms","mushrooms shiitake raw"),
    Entry("Oyster Mushrooms", "mushrooms oyster raw"),
    Entry("Enoki Mushrooms",  "mushrooms enoki raw"),
    Entry("Porcini Mushrooms","mushrooms porcini dried"),
    Entry("Russet Potato",    "potatoes russet raw"),
    Entry("Sweet Potato",     "sweet potato raw"),
    Entry("Yukon Gold Potato","potatoes flesh and skin raw"),
    Entry("Corn",             "corn sweet yellow raw"),
    Entry("Peas",             "peas green raw"),
    Entry("Green Beans",      "beans snap green raw"),
    Entry("Cucumber",         "cucumber raw"),
    Entry("Kale",             "kale raw"),
    Entry("Cauliflower",      "cauliflower raw"),
    Entry("Asparagus",        "asparagus raw"),
    Entry("Eggplant",         "eggplant raw"),
    Entry("Brussels Sprouts", "brussels sprouts raw"),
    Entry("Cabbage",          "cabbage raw"),
    Entry("Beets",            "beets raw"),
    Entry("Artichoke Hearts", "artichokes globe raw"),
    Entry("Bok Choy",         "cabbage chinese pak choi raw"),
    Entry("Napa Cabbage",     "cabbage chinese pe tsai raw"),
    Entry("Fennel Bulb",      "fennel bulb raw"),
    Entry("Butternut Squash", "squash winter butternut raw"),
    Entry("Acorn Squash",     "squash winter acorn raw"),
    Entry("Spaghetti Squash", "squash winter spaghetti raw"),
    Entry("Swiss Chard",      "chard swiss raw"),
    Entry("Collard Greens",   "collards raw"),
    Entry("Turnip Greens",    "turnip greens raw"),
    Entry("Mustard Greens",   "mustard greens raw"),
    Entry("Okra",             "okra raw"),
    Entry("Turnip",           "turnip raw"),
    Entry("Parsnip",          "parsnip raw"),
    Entry("Rutabaga",         "rutabaga raw"),
    Entry("Kohlrabi",         "kohlrabi raw"),
    Entry("Radicchio",        "radicchio raw"),
    Entry("Daikon Radish",    "radishes oriental raw"),
    Entry("Radish",           "radishes raw"),
    Entry("Snow Peas",        "peas edible podded raw"),
    Entry("Snap Peas",        "peas edible podded raw"),
    Entry("Bean Sprouts",     "bean sprouts mung raw"),
    Entry("Water Chestnuts",  "water chestnuts chinese canned"),
    Entry("Tomatillos",       "tomatillos raw"),
    Entry("Chayote",          "squash vegetable gourd chayote fruit raw"),
    Entry("Plantains",        "plantains raw"),
    Entry("Jicama",           "jicama yambean tuber raw"),
    Entry("Watercress",       "watercress raw"),
    Entry("Endive",           "endive raw"),
    Entry("Romaine Lettuce",  "lettuce cos or romaine raw"),
    Entry("Iceberg Lettuce",  "lettuce iceberg raw"),
    Entry("Arugula",          "arugula raw"),
    Entry("Mixed Greens",     "lettuce cos or romaine raw"),
    Entry("Leek",             "leeks bulb and lower leaf raw"),

    // ── Fruits ───────────────────────────────────────────────────────────────
    Entry("Lemon",        "lemon raw without peel"),
    Entry("Lime",         "lime raw"),
    Entry("Orange",       "oranges raw all commercial varieties"),
    Entry("Lemon Juice",  "lemon juice raw"),
    Entry("Lime Juice",   "lime juice raw"),
    Entry("Orange Juice", "orange juice raw"),
    Entry("Apple",        "apples raw with skin"),
    Entry("Banana",       "bananas raw"),
    Entry("Strawberries", "strawberries raw"),
    Entry("Blueberries",  "blueberries raw"),
    Entry("Raspberries",  "raspberries raw"),
    Entry("Avocado",      "avocados raw all commercial varieties"),
    Entry("Mango",        "mangos raw"),
    Entry("Papaya",       "papaya raw"),
    Entry("Pineapple",    "pineapple raw all varieties"),
    Entry("Peach",        "peaches raw"),
    Entry("Pear",         "pears raw"),
    Entry("Plum",         "plums raw"),
    Entry("Cherries",     "cherries sweet raw"),
    Entry("Kiwi",         "kiwifruit green raw"),
    Entry("Cantaloupe",   "melons cantaloupe raw"),
    Entry("Watermelon",   "watermelon raw"),
    Entry("Grapefruit",   "grapefruit raw pink and red all areas"),
    Entry("Pomegranate",  "pomegranates raw"),
    Entry("Fresh Figs",   "figs raw"),
    Entry("Fresh Apricots","apricots raw"),
    Entry("Grapes",       "grapes red or green american type adherent skin raw"),
    Entry("Blackberries", "blackberries raw"),
    Entry("Cranberries",  "cranberries raw"),
    Entry("Mango Juice",  "mango nectar canned"),

    // ── Dried Fruits ─────────────────────────────────────────────────────────
    Entry("Raisins",              "raisins seedless"),
    Entry("Golden Raisins",       "raisins golden seedless"),
    Entry("Dried Cranberries",    "cranberries dried sweetened"),
    Entry("Dried Apricots",       "apricots dried sulfured"),
    Entry("Dried Figs",           "figs dried uncooked"),
    Entry("Dried Cherries",       "cherries dried sweetened"),
    Entry("Prunes",               "plums dried prunes uncooked"),
    Entry("Dried Mango",          "mangos dried sweetened"),
    Entry("Medjool Dates",        "dates medjool"),
    Entry("Shredded Coconut",     "coconut meat dried unsweetened"),

    // ── Proteins — Beef ──────────────────────────────────────────────────────
    Entry("Chicken Breast",    "chicken broilers or fryers breast meat only raw"),
    Entry("Chicken Thigh",     "chicken broilers or fryers thigh meat only raw"),
    Entry("Chicken Drumstick", "chicken broilers or fryers drumstick meat only raw"),
    Entry("Chicken Wing",      "chicken broilers or fryers wing meat only raw"),
    Entry("Whole Chicken",     "chicken broilers or fryers whole meat and skin raw"),
    Entry("Ground Chicken",    "chicken ground raw"),
    Entry("Chicken Liver",     "chicken liver all classes raw"),
    Entry("Turkey Breast",     "turkey breast meat only raw"),
    Entry("Turkey Leg",        "turkey leg meat only raw"),
    Entry("Ground Turkey",     "turkey ground raw"),
    Entry("Duck Breast",       "duck domesticated meat only raw"),
    Entry("Duck Leg",          "duck domesticated leg meat only raw"),
    Entry("Ground Beef 80/20", "beef ground 80% lean meat 20% fat raw"),
    Entry("Ground Beef 90/10", "beef ground 90% lean meat 10% fat raw"),
    Entry("Ground Beef 73/27", "beef ground 73% lean meat 27% fat raw"),
    Entry("Brisket",           "beef brisket flat half separable lean and fat raw"),
    Entry("Chuck Roast",       "beef chuck arm pot roast separable lean and fat raw"),
    Entry("Beef Short Ribs",   "beef short ribs separable lean and fat raw"),
    Entry("Ribeye Steak",      "beef rib eye steak bone-in separable lean and fat raw"),
    Entry("NY Strip Steak",    "beef loin top loin steak boneless separable lean and fat raw"),
    Entry("Flank Steak",       "beef flank steak separable lean and fat raw"),
    Entry("Skirt Steak",       "beef skirt steak separable lean and fat raw"),
    Entry("T-Bone Steak",      "beef loin t-bone steak separable lean and fat raw"),
    Entry("Beef Stew Meat",    "beef chuck for stew separable lean and fat raw"),
    Entry("Top Round Roast",   "beef round top round roast separable lean and fat raw"),
    Entry("Beef Tri-Tip",      "beef loin tri-tip roast separable lean and fat raw"),
    Entry("Sirloin Steak",     "beef loin top sirloin steak lean raw"),
    Entry("Ground Pork",       "pork ground raw"),
    Entry("Pork Chop",         "pork fresh loin center chop raw"),
    Entry("Pork Tenderloin",   "pork fresh loin tenderloin separable lean only raw"),
    Entry("Pork Shoulder",     "pork fresh shoulder boston blade roast separable lean and fat raw"),
    Entry("Pork Belly",        "pork fresh belly raw"),
    Entry("Pork Baby Back Ribs","pork fresh loin back ribs bone-in separable lean and fat raw"),
    Entry("Pork Spare Ribs",   "pork fresh loin back ribs separable lean and fat raw"),
    Entry("Pork Loin Roast",   "pork fresh loin whole separable lean and fat raw"),
    Entry("Bacon",             "pork cured bacon unprepared"),
    Entry("Ham",               "pork cured ham regular approximately 11% fat"),
    Entry("Italian Sausage",   "pork sausage italian raw"),
    Entry("Andouille Sausage", "pork sausage smoked"),
    Entry("Chorizo",           "pork sausage fresh chorizo"),
    Entry("Kielbasa",          "pork sausage kielbasa"),
    Entry("Pancetta",          "pork cured pancetta"),
    Entry("Prosciutto",        "pork cured prosciutto"),
    Entry("Smoked Sausage",    "pork sausage smoked"),
    Entry("Salt Pork",         "pork cured salt pork raw"),
    Entry("Salmon",            "fish salmon atlantic farmed raw"),
    Entry("Tuna",              "fish tuna light canned in water"),
    Entry("Shrimp",            "crustaceans shrimp mixed species raw"),
    Entry("Cod",               "fish cod atlantic raw"),
    Entry("Tilapia",           "fish tilapia raw"),
    Entry("Halibut",           "fish halibut atlantic and pacific raw"),
    Entry("Mahi-Mahi",         "fish mahimahi raw"),
    Entry("Catfish",           "catfish channel wild raw"),
    Entry("Flounder",          "fish flounder and sole species raw"),
    Entry("Trout",             "fish trout rainbow farmed raw"),
    Entry("Snapper",           "fish snapper mixed species raw"),
    Entry("Sea Bass",          "fish sea bass mixed species raw"),
    Entry("Swordfish",         "fish swordfish raw"),
    Entry("Pollock",           "fish pollock alaska raw"),
    Entry("Sardines",          "fish sardine atlantic canned in oil"),
    Entry("Scallops",          "mollusks scallop mixed species raw"),
    Entry("Clams",             "mollusks clam mixed species raw"),
    Entry("Mussels",           "mollusks mussel blue raw"),
    Entry("Oysters",           "mollusks oyster eastern wild raw"),
    Entry("Crab",              "crustaceans crab blue raw"),
    Entry("Crawfish",          "crustaceans crawfish mixed species wild raw"),
    Entry("Lobster",           "crustaceans lobster northern raw"),
    Entry("Squid",             "mollusks squid mixed species raw"),
    Entry("Ground Lamb",       "lamb ground raw"),
    Entry("Lamb Chops",        "lamb loin chop raw"),
    Entry("Leg of Lamb",       "lamb leg whole separable lean and fat raw"),
    Entry("Lamb Shoulder",     "lamb shoulder whole separable lean and fat raw"),
    Entry("Rack of Lamb",      "lamb rib whole separable lean and fat raw"),
    Entry("Veal Cutlet",       "veal leg top round cap off separable lean only raw"),
    Entry("Ground Veal",       "veal ground raw"),
    Entry("Venison",           "game meat deer raw"),
    Entry("Bison",             "game meat bison ground raw"),
    Entry("Rabbit",            "game meat rabbit domesticated raw"),

    // ── Legumes ──────────────────────────────────────────────────────────────
    Entry("Black Beans",       "beans black canned"),
    Entry("Kidney Beans",      "beans kidney red canned"),
    Entry("Chickpeas",         "chickpeas garbanzo beans bengal gram canned"),
    Entry("Lentils",           "lentils raw"),
    Entry("Red Lentils",       "lentils raw"),
    Entry("Cannellini Beans",  "beans white canned"),
    Entry("Pinto Beans",       "beans pinto canned"),
    Entry("Navy Beans",        "beans navy canned"),
    Entry("Edamame",           "edamame frozen prepared"),
    Entry("Chana Dal",         "chickpeas garbanzo beans bengal gram mature seeds raw"),
    Entry("Moong Dal",         "mung beans mature seeds raw"),
    Entry("Dried Lima Beans",  "beans lima large mature seeds raw"),
    Entry("Black-Eyed Peas",   "cowpeas blackeye peas mature seeds raw"),
    Entry("Dried Chickpeas",   "chickpeas garbanzo beans bengal gram mature seeds raw"),
    Entry("Tofu Firm",         "tofu raw firm prepared with calcium sulfate"),
    Entry("Tofu Silken",       "tofu silken"),
    Entry("Tempeh",            "tempeh cooked"),
    Entry("Seitan",            "vital wheat gluten"),
    Entry("Nutritional Yeast", "yeast extract spread"),

    // ── Grains & Pasta ───────────────────────────────────────────────────────
    Entry("Pasta",              "pasta dry enriched"),
    Entry("White Rice",         "rice white long grain raw"),
    Entry("Brown Rice",         "rice brown long grain raw"),
    Entry("Basmati Rice",       "rice white long grain raw"),
    Entry("Arborio Rice",       "rice white short grain raw"),
    Entry("Sushi Rice",         "rice white short grain raw"),
    Entry("Quinoa",             "quinoa uncooked"),
    Entry("Rolled Oats",        "oats"),
    Entry("Steel-Cut Oats",     "oats"),
    Entry("Breadcrumbs",        "breadcrumbs dry grated plain"),
    Entry("Panko Breadcrumbs",  "breadcrumbs panko"),
    Entry("Couscous",           "couscous dry"),
    Entry("Barley",             "barley pearled raw"),
    Entry("Farro",              "wheat hard red winter"),
    Entry("Polenta",            "corn yellow whole grain"),
    Entry("Grits",              "corn grits white regular and quick unenriched dry"),
    Entry("Semolina Pasta",     "wheat semolina unenriched"),
    Entry("Rice Noodles",       "noodles rice cooked"),
    Entry("Udon Noodles",       "noodles japanese soba cooked"),
    Entry("Soba Noodles",       "noodles japanese soba cooked"),
    Entry("Glass Noodles",      "noodles cellophane or long rice dehydrated"),
    Entry("Millet",             "millet raw"),
    Entry("Freekeh",            "wheat durum"),
    Entry("Bulgur Wheat",       "bulgur dry"),
    Entry("Orzo",               "pasta dry enriched"),
    Entry("Wheat Germ",         "wheat germ crude"),
    Entry("Challah",            "bread egg"),

    // ── Canned & Jarred ──────────────────────────────────────────────────────
    Entry("Diced Tomatoes",         "tomatoes diced canned"),
    Entry("Crushed Tomatoes",       "tomatoes crushed canned"),
    Entry("Whole Peeled Tomatoes",  "tomatoes whole peeled canned"),
    Entry("Tomato Paste",           "tomato paste canned"),
    Entry("Tomato Sauce",           "sauce pasta tomato"),
    Entry("Pesto",                  "sauce pesto basil ready to serve"),
    Entry("Chicken Broth",          "broth chicken ready to serve"),
    Entry("Beef Broth",             "broth beef ready to serve"),
    Entry("Vegetable Broth",        "broth vegetable ready to serve"),
    Entry("Coconut Milk",           "coconut milk canned"),
    Entry("Cream of Mushroom Soup", "soup cream of mushroom canned condensed"),
    Entry("Cream of Chicken Soup",  "soup chicken cream of canned condensed"),
    Entry("Roasted Red Peppers",    "peppers sweet red roasted jarred"),
    Entry("Olives",                 "olives ripe canned"),
    Entry("Kalamata Olives",        "olives ripe canned"),
    Entry("Capers",                 "capers canned"),
    Entry("Sun-Dried Tomatoes",     "tomatoes sundried"),
    Entry("Anchovies",              "fish anchovy european raw"),
    Entry("Canned Corn",            "corn sweet yellow canned whole kernel drained"),
    Entry("Canned Green Beans",     "beans snap green canned"),
    Entry("Canned Pumpkin",         "pumpkin canned without salt"),
    Entry("Canned Refried Beans",   "beans refried traditional canned"),
    Entry("Canned Baked Beans",     "beans baked plain or vegetarian canned"),
    Entry("Canned Black-Eyed Peas", "cowpeas blackeye canned"),
    Entry("Grape Leaves",           "grape leaves canned"),
    Entry("Hominy",                 "hominy canned white"),
    Entry("Water Chestnuts Canned", "water chestnuts chinese canned"),
    Entry("Chicken Stock",          "soup chicken broth or bouillon ready to serve"),
    Entry("Beef Stock",             "soup beef broth or bouillon ready to serve"),
    Entry("Vegetable Stock",        "soup vegetable broth ready to serve"),

    // ── Condiments & Acids ───────────────────────────────────────────────────
    Entry("Dijon Mustard",       "mustard prepared yellow"),
    Entry("Yellow Mustard",      "mustard prepared yellow"),
    Entry("Mayonnaise",          "mayonnaise dressing"),
    Entry("Ketchup",             "catsup"),
    Entry("Apple Cider Vinegar", "vinegar cider"),
    Entry("White Vinegar",       "vinegar distilled"),
    Entry("Balsamic Vinegar",    "vinegar balsamic"),
    Entry("Rice Vinegar",        "vinegar rice"),
    Entry("Red Wine Vinegar",    "vinegar red wine"),
    Entry("White Wine Vinegar",  "vinegar white wine"),
    Entry("Sherry Vinegar",      "vinegar red wine"),
    Entry("Champagne Vinegar",   "vinegar white wine"),
    Entry("Malt Vinegar",        "vinegar malt"),
    Entry("Tahini",              "tahini from roasted and toasted kernels"),
    Entry("Hoisin Sauce",        "sauce hoisin ready to serve"),
    Entry("Oyster Sauce",        "sauce oyster ready to serve"),
    Entry("Sriracha",            "sauce ready to serve sriracha"),
    Entry("Miso Paste",          "soup miso paste"),
    Entry("Gochujang",           "sauce gochujang korean chili"),
    Entry("Harissa",             "peppers hot chili red raw"),
    Entry("Pomegranate Molasses","pomegranate juice unsweetened"),
    Entry("Rose Water",          "water bottled"),
    Entry("Tamarind Paste",      "tamarind raw"),
    Entry("Mirin",               "alcoholic beverage wine rice"),
    Entry("Sake",                "alcoholic beverage wine rice"),
    Entry("Shaoxing Wine",       "alcoholic beverage wine rice"),
    Entry("Pita Bread",          "bread pita white enriched"),
    Entry("Corn Tortillas",      "tortillas ready to bake or fry corn"),
    Entry("Flour Tortillas",     "tortillas ready to bake or fry flour wheat"),
    Entry("Kimchi",              "kimchi"),
    Entry("Masa Harina",         "corn masa flour dry"),
    Entry("Ancho Chile",         "peppers ancho dried"),
    Entry("Guajillo Chile",      "peppers dried"),
    Entry("Chipotle in Adobo",   "peppers chipotle dried"),
    Entry("Ghee",                "butter clarified"),

    // ── Nuts, Seeds & Nut Butters ────────────────────────────────────────────
    Entry("Almonds",          "nuts almonds"),
    Entry("Walnuts",          "nuts walnuts english"),
    Entry("Pecans",           "nuts pecans"),
    Entry("Cashews",          "nuts cashew nuts raw"),
    Entry("Pine Nuts",        "nuts pine nuts dried"),
    Entry("Peanuts",          "peanuts raw"),
    Entry("Sunflower Seeds",  "seeds sunflower seed kernels dried"),
    Entry("Sesame Seeds",     "seeds sesame seeds whole dried"),
    Entry("Chia Seeds",       "seeds chia seeds dried"),
    Entry("Ground Flaxseed",  "seeds flaxseed"),
    Entry("Pepitas",          "seeds pumpkin squash kernels dried"),
    Entry("Hemp Seeds",       "seeds hemp seed hulled"),
    Entry("Peanut Butter",    "peanut butter smooth style without salt"),
    Entry("Almond Butter",    "nut butters almond butter plain without salt added"),
    Entry("Tahini",           "tahini from roasted and toasted kernels"),
    Entry("Macadamia Nuts",   "nuts macadamia nuts raw"),
    Entry("Hazelnuts",        "nuts hazelnuts or filberts"),
    Entry("Brazil Nuts",      "nuts brazilnuts dried unblanched"),
    Entry("Pistachios",       "nuts pistachio nuts raw"),

    // ── Chocolate & Cocoa ────────────────────────────────────────────────────
    Entry("Cocoa Powder",               "cocoa dry powder unsweetened"),
    Entry("Dark Chocolate",             "candies chocolate dark 70-85% cacao solids"),
    Entry("Semi-Sweet Chocolate Chips", "candies chocolate semi sweet"),
    Entry("Milk Chocolate",             "candies milk chocolate"),
    Entry("White Chocolate",            "candies white chocolate"),
    Entry("Bittersweet Chocolate",      "candies chocolate bittersweet"),
    Entry("Unsweetened Chocolate",      "chocolate unsweetened baking"),
    Entry("Butterscotch Chips",         "candies butterscotch"),
    Entry("Marzipan",                   "marzipan"),

    // ── Wine, Beer & Stock ───────────────────────────────────────────────────
    Entry("White Wine",      "alcoholic beverage wine table white"),
    Entry("Red Wine",        "alcoholic beverage wine table red"),
    Entry("Beer",            "alcoholic beverage beer regular"),

    // ── Baking Specialty ─────────────────────────────────────────────────────
    Entry("Puff Pastry",  "pastry puff frozen unbaked"),
    Entry("Phyllo Dough", "phyllo dough"),
]
