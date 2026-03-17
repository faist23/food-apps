import Foundation

// MARK: - USDA FoodData Central Service

/// Service for interacting with the USDA FoodData Central API
/// Great for whole foods, fruits, vegetables, and basic ingredients
@MainActor
public class USDAFoodDataService {
    public static let shared = USDAFoodDataService()
    
    private let baseURL = "https://api.nal.usda.gov/fdc/v1"
    private let session: URLSession
    
    // API key - replace with your USDA FoodData Central API key
    // Get your free API key at: https://fdc.nal.usda.gov/api-key-signup.html
    private let apiKey = "oOmrSwfN79pdnObk07VfKO3hNuFqyRW4aYtGDytz"
    
    private init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }
    
    /// Search for foods in the USDA database
    /// - Parameters:
    ///   - query: Search term (e.g., "banana", "apple")
    ///   - page: Page number (1-indexed)
    ///   - pageSize: Number of results per page
    /// - Returns: Array of USDA food items
    public func searchFoods(query: String, page: Int = 1, pageSize: Int = 25) async throws -> [USDAFoodItem] {
        // Search both SR Legacy (whole foods) and Survey (FNDDS - restaurant foods) in parallel
        async let srLegacyResults = searchFoodsByDataType(query: query, dataType: "SR Legacy", page: page, pageSize: pageSize)
        async let fnddsResults = searchFoodsByDataType(query: query, dataType: "Survey (FNDDS)", page: page, pageSize: pageSize)
        
        var allResults: [USDAFoodItem] = []
        
        // SR Legacy first (whole foods with good portion data)
        do {
            let srFoods = try await srLegacyResults
            print("✅ SR Legacy returned \(srFoods.count) results")
            allResults.append(contentsOf: srFoods)
        } catch {
            print("⚠️ SR Legacy search failed: \(error.localizedDescription)")
        }
        
        // FNDDS second (restaurant and survey foods)
        do {
            let surveyFoods = try await fnddsResults
            print("✅ Survey (FNDDS) returned \(surveyFoods.count) results")
            allResults.append(contentsOf: surveyFoods)
        } catch {
            print("⚠️ Survey (FNDDS) search failed: \(error.localizedDescription)")
        }
        
        // If both failed, throw an error
        if allResults.isEmpty {
            throw USDAError.noResults
        }
        
        return allResults
    }
    
    /// Search for foods by specific data type
    private func searchFoodsByDataType(query: String, dataType: String, page: Int, pageSize: Int) async throws -> [USDAFoodItem] {
        guard var components = URLComponents(string: "\(baseURL)/foods/search") else {
            throw USDAError.invalidURL
        }
        
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "pageSize", value: "\(pageSize)"),
            URLQueryItem(name: "pageNumber", value: "\(page)"),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "dataType", value: dataType)
        ]
        
        guard let url = components.url else {
            throw USDAError.invalidURL
        }
        
        print("🌐 USDA API Request [\(dataType)]: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.setValue("BiteLedger - iOS Food Tracker", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw USDAError.invalidResponse
        }
        
        print("🌐 USDA API Response [\(dataType)] status: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            if let errorString = String(data: data, encoding: .utf8) {
                print("❌ USDA API Error response [\(dataType)]: \(errorString)")
            }
            throw USDAError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        do {
            let searchResponse = try decoder.decode(USDASearchResponse.self, from: data)
            print("🌐 USDA [\(dataType)] decoded successfully: \(searchResponse.foods.count) foods")
            
            // Log first few foods for debugging
            for (index, food) in searchResponse.foods.prefix(3).enumerated() {
                print("🥕 [\(dataType)] Food \(index + 1): \(food.description)")
                print("   - FDC ID: \(food.fdcId)")
                print("   - Data Type: \(food.dataType)")
            }
            
            return searchResponse.foods
        } catch {
            print("❌ USDA [\(dataType)] Decoding error: \(error)")
            throw USDAError.decodingError(error)
        }
    }
    
    /// Get detailed information about a specific food
    /// - Parameter fdcId: The USDA FDC ID
    /// - Returns: Detailed food information
    public func getFoodDetails(fdcId: Int) async throws -> USDAFoodDetail {
        guard var components = URLComponents(string: "\(baseURL)/food/\(fdcId)") else {
            throw USDAError.invalidURL
        }
        
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey)
        ]
        
        guard let url = components.url else {
            throw USDAError.invalidURL
        }
        
        print("🌐 USDA Food Detail Request: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.setValue("BiteLedger - iOS Food Tracker", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw USDAError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw USDAError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(USDAFoodDetail.self, from: data)
    }
}

// MARK: - Response Models

public struct USDASearchResponse: Codable, Sendable {
    public let foods: [USDAFoodItem]
    public let totalHits: Int
    public let currentPage: Int
    public let totalPages: Int
}

public struct USDAFoodItem: Codable, Identifiable, Sendable {
    public let fdcId: Int
    public let description: String
    public let dataType: String
    public let brandOwner: String?
    public let ingredients: String?
    public let foodNutrients: [USDANutrient]?
    
    public var id: Int { fdcId }
    
    public var displayName: String {
        description
    }
    
    public var displayBrand: String {
        brandOwner ?? "USDA"
    }
}

public struct USDAFoodDetail: Codable {
    public let fdcId: Int
    public let description: String
    public let dataType: String
    public let foodNutrients: [USDANutrientDetail]
    public let foodPortions: [USDAFoodPortion]?  // SR Legacy uses 'foodPortions'
    
    public var displayName: String {
        description
    }
    
    public var portions: [USDAFoodPortion]? {
        foodPortions
    }
}

public struct USDANutrient: Codable, Sendable {
    public let nutrientId: Int
    public let nutrientName: String
    public let nutrientNumber: String?
    public let value: Double
    public let unitName: String
}

public struct USDANutrientDetail: Codable {
    public let nutrient: USDANutrientInfo
    public let amount: Double?
    
    // Different data types use different field names
    private enum CodingKeys: String, CodingKey {
        case nutrient
        case amount
        case value  // SR Legacy uses 'value'
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nutrient = try container.decode(USDANutrientInfo.self, forKey: .nutrient)
        
        // Try 'amount' first (Survey/Foundation), then 'value' (SR Legacy)
        if let amt = try? container.decode(Double.self, forKey: .amount) {
            amount = amt
        } else if let val = try? container.decode(Double.self, forKey: .value) {
            amount = val
        } else {
            amount = nil
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nutrient, forKey: .nutrient)
        try container.encodeIfPresent(amount, forKey: .amount)
    }
}

public struct USDANutrientInfo: Codable {
    public let id: Int
    public let number: String
    public let name: String
    public let unitName: String
}

public struct USDAFoodPortion: Codable {
    public let id: Int
    public let amount: Double?
    public let modifier: String?
    public let gramWeight: Double
    public let sequenceNumber: Int?
    
    public var displayName: String {
        let amt = amount ?? 1.0
        if let modifier = modifier {
            if amt == 1.0 {
                return modifier
            }
            return "\(amt) \(modifier)"
        }
        return "\(Int(gramWeight))g"
    }
}

// MARK: - Conversion Extensions

extension USDAFoodItem {
    /// Convert USDA food item to app's ProductInfo model for compatibility
    public func toProductInfo() -> ProductInfo? {
        guard let nutrients = foodNutrients else { return nil }
        
        // Extract nutrition values (USDA provides per 100g)
        var calories: Double = 0
        var protein: Double = 0
        var carbs: Double = 0
        var fat: Double = 0
        var fiber: Double = 0
        var sugar: Double = 0
        var sodium: Double = 0
        var saturatedFat: Double = 0
        
        for nutrient in nutrients {
            // USDA nutrient numbers: https://fdc.nal.usda.gov/api-guide.html
            switch nutrient.nutrientNumber {
            case "208": calories = nutrient.value  // Energy (kcal)
            case "203": protein = nutrient.value   // Protein
            case "205": carbs = nutrient.value     // Carbohydrate
            case "204": fat = nutrient.value       // Total lipid (fat)
            case "291": fiber = nutrient.value     // Fiber
            case "269": sugar = nutrient.value     // Sugars, total
            case "307": sodium = nutrient.value    // Sodium (mg)
            case "606": saturatedFat = nutrient.value  // Saturated fat
            default: break
            }
        }
        
        let nutriments = Nutriments(
            energyKcal100g: FlexibleDouble(calories),
            energyKcalComputed: calories,
            proteins100g: FlexibleDouble(protein),
            carbohydrates100g: FlexibleDouble(carbs),
            sugars100g: FlexibleDouble(sugar),
            fat100g: FlexibleDouble(fat),
            saturatedFat100g: FlexibleDouble(saturatedFat),
            transFat100g: nil,
            monounsaturatedFat100g: nil,
            polyunsaturatedFat100g: nil,
            fiber100g: FlexibleDouble(fiber),
            sodium100g: FlexibleDouble(sodium / 1000),  // mg → g
            salt100g: nil,
            cholesterol100g: nil,
            vitaminA100g: nil,
            vitaminC100g: nil,
            vitaminD100g: nil,
            vitaminE100g: nil,
            vitaminK100g: nil,
            vitaminB6100g: nil,
            vitaminB12100g: nil,
            folate100g: nil,
            choline100g: nil,
            calcium100g: nil,
            iron100g: nil,
            potassium100g: nil,
            magnesium100g: nil,
            zinc100g: nil,
            caffeine100g: nil,
            energyKcalServing: nil,
            proteinsServing: nil,
            carbohydratesServing: nil,
            sugarsServing: nil,
            fatServing: nil,
            saturatedFatServing: nil,
            fiberServing: nil,
            sodiumServing: nil
        )
        
        return ProductInfo(
            code: "usda_\(fdcId)",
            productName: description,
            brands: brandOwner,
            imageUrl: nil,
            nutriments: nutriments,
            servingSize: "100g",
            quantity: nil,
            portions: nil,  // Search results don't include portions
            countriesTags: ["en:united-states"],  // USDA is US-only
            lastUsed: nil  // Not from My Foods
        )
    }
}

extension USDAFoodDetail {
    /// Convert detailed USDA food to ProductInfo with portions
    public func toProductInfo() -> ProductInfo {
        var calories: Double = 0
        var protein: Double = 0
        var carbs: Double = 0
        var fat: Double = 0
        var fiber: Double = 0
        var sugar: Double = 0
        var sodium: Double = 0
        var saturatedFat: Double = 0
        var transFat: Double = 0
        var cholesterol: Double = 0
        var monounsaturatedFat: Double = 0
        var polyunsaturatedFat: Double = 0
        var vitaminA: Double = 0
        var vitaminC: Double = 0
        var vitaminD: Double = 0
        var vitaminE: Double = 0
        var vitaminK: Double = 0
        var vitaminB6: Double = 0
        var vitaminB12: Double = 0
        var folate: Double = 0
        var choline: Double = 0
        var calcium: Double = 0
        var iron: Double = 0
        var potassium: Double = 0
        var magnesium: Double = 0
        var zinc: Double = 0
        var caffeine: Double = 0
        
        for nutrientDetail in foodNutrients {
            let nutrient = nutrientDetail.nutrient
            guard let amount = nutrientDetail.amount else { continue }
            
            switch nutrient.number {
            case "208": calories = amount
            case "203": protein = amount
            case "205": carbs = amount
            case "204": fat = amount
            case "291": fiber = amount
            case "269": sugar = amount
            case "307": sodium = amount  // mg
            case "606": saturatedFat = amount
            case "605": transFat = amount
            case "645": monounsaturatedFat = amount
            case "646": polyunsaturatedFat = amount
            case "601": cholesterol = amount  // mg
            case "320": vitaminA = amount  // µg
            case "401": vitaminC = amount  // mg
            case "324": vitaminD = amount  // µg
            case "323": vitaminE = amount  // mg
            case "430": vitaminK = amount  // µg
            case "415": vitaminB6 = amount  // mg
            case "418": vitaminB12 = amount  // µg
            case "417": folate = amount  // µg
            case "421": choline = amount  // mg
            case "301": calcium = amount  // mg
            case "303": iron = amount  // mg
            case "306": potassium = amount  // mg
            case "304": magnesium = amount  // mg
            case "309": zinc = amount  // mg
            case "262": caffeine = amount  // mg
            default: break
            }
        }
        
        // USDA is a per-100g database. Do NOT populate *Serving fields here.
        // The picker's nutritionMultiplier uses totalGrams/100 when hasServingData == false,
        // which correctly scales all *100g nutrients (including sodium, cholesterol) by the
        // selected portion's gram weight. Populating *Serving from the wrong (unsorted) portion
        // would cause the picker to show 1452 cal for a single frankfurter.

        // Nutriments.*100g fields use g/100g (OpenFoodFacts convention).
        // USDA provides micronutrients in mg or mcg per 100g — must convert.
        let nutriments = Nutriments(
            energyKcal100g: FlexibleDouble(calories),
            energyKcalComputed: calories,
            proteins100g: FlexibleDouble(protein),
            carbohydrates100g: FlexibleDouble(carbs),
            sugars100g: FlexibleDouble(sugar),
            fat100g: FlexibleDouble(fat),
            saturatedFat100g: FlexibleDouble(saturatedFat),
            transFat100g: FlexibleDouble(transFat),
            monounsaturatedFat100g: FlexibleDouble(monounsaturatedFat),
            polyunsaturatedFat100g: FlexibleDouble(polyunsaturatedFat),
            fiber100g: FlexibleDouble(fiber),
            sodium100g: FlexibleDouble(sodium / 1000),           // mg → g
            salt100g: nil,
            cholesterol100g: FlexibleDouble(cholesterol / 1000), // mg → g
            vitaminA100g: FlexibleDouble(vitaminA / 1_000_000),  // mcg → g
            vitaminC100g: FlexibleDouble(vitaminC / 1000),       // mg → g
            vitaminD100g: FlexibleDouble(vitaminD / 1_000_000),  // mcg → g
            vitaminE100g: FlexibleDouble(vitaminE / 1000),       // mg → g
            vitaminK100g: FlexibleDouble(vitaminK / 1_000_000),  // mcg → g
            vitaminB6100g: FlexibleDouble(vitaminB6 / 1000),     // mg → g
            vitaminB12100g: FlexibleDouble(vitaminB12 / 1_000_000), // mcg → g
            folate100g: FlexibleDouble(folate / 1_000_000),      // mcg → g
            choline100g: FlexibleDouble(choline / 1000),         // mg → g
            calcium100g: FlexibleDouble(calcium / 1000),         // mg → g
            iron100g: FlexibleDouble(iron / 1000),               // mg → g
            potassium100g: FlexibleDouble(potassium / 1000),     // mg → g
            magnesium100g: FlexibleDouble(magnesium / 1000),     // mg → g
            zinc100g: FlexibleDouble(zinc / 1000),               // mg → g
            caffeine100g: FlexibleDouble(caffeine / 1000),       // mg → g
            energyKcalServing: nil,
            proteinsServing: nil,
            carbohydratesServing: nil,
            sugarsServing: nil,
            fatServing: nil,
            saturatedFatServing: nil,
            fiberServing: nil,
            sodiumServing: nil
        )
        
        // Log all portions for debugging
        print("🍌 USDA Food: \(description)")
        print("🍌 Total portions available: \(portions?.count ?? 0)")
        portions?.forEach { portion in
            print("   - Portion: modifier='\(portion.modifier ?? "nil")', amount=\(portion.amount ?? 0), gramWeight=\(portion.gramWeight)")
        }
        
        // Convert USDA portions to ServingPortion (only if there are meaningful portions)
        let servingPortions = portions?.compactMap { portion -> ServingPortion? in
            guard let modifier = portion.modifier else {
                print("   ⚠️ Skipping portion with nil modifier")
                return nil
            }
            
            // Skip portions that are just "100g" equivalents
            if modifier.lowercased().contains("100 g") || modifier.lowercased().contains("100g") {
                print("   ⚠️ Skipping '100g' portion")
                return nil
            }
            
            // Skip portions that are purely numeric codes (Survey/FNDDS sometimes has these)
            // But keep portions like "1 cup" or "1 serving"
            if modifier.range(of: "^[0-9]+$", options: .regularExpression) != nil {
                print("   ⚠️ Skipping numeric portion code: '\(modifier)'")
                return nil
            }
            
            // Clean up modifier for better display
            var cleanModifier = modifier
            
            // Simplify long descriptions but keep the size descriptors
            cleanModifier = cleanModifier
                .replacingOccurrences(of: " (7\" to 7-7/8\" long)", with: "")
                .replacingOccurrences(of: " (8\" to 8-7/8\" long)", with: "")
                .replacingOccurrences(of: " (6\" to 6-7/8\" long)", with: "")
                .replacingOccurrences(of: " (9\" or longer)", with: "")
                .replacingOccurrences(of: " (less than 6\" long)", with: "")
            
            // For Survey/FNDDS data, keep "1.0 serving" portions as they're meaningful
            // Skip only if there are better alternatives
            let isServingPortion = cleanModifier.lowercased().contains("serving")
            let isNLEAServing = cleanModifier.lowercased() == "nlea serving"
            
            // Skip NLEA serving only if we have other non-serving portions
            if isNLEAServing {
                let hasOtherPortions = portions?.contains(where: { otherPortion in
                    guard let otherMod = otherPortion.modifier?.lowercased() else { return false }
                    return !otherMod.contains("serving") && !otherMod.contains("100")
                }) ?? false
                
                if hasOtherPortions {
                    print("   ⚠️ Skipping NLEA serving in favor of size-based portions")
                    return nil
                }
            }
            
            print("   ✅ Keeping portion: \(cleanModifier)")
            return ServingPortion(
                id: portion.id,
                amount: portion.amount ?? 1.0,
                modifier: cleanModifier,
                gramWeight: portion.gramWeight
            )
        }
        
        // Sort portions: prefer individual-unit portions over bulk/package descriptors.
        // "package", "bag", "box", "container", "can" go to the end so the picker
        // defaults to the single-item serving (e.g., "frankfurter" over "package").
        let bulkKeywords = ["package", "bag", "box", "container", "can", "jar", "bottle", "carton"]
        let sortedPortions = servingPortions?.sorted { a, b in
            let aIsBulk = bulkKeywords.contains(where: { a.modifier.lowercased().contains($0) })
            let bIsBulk = bulkKeywords.contains(where: { b.modifier.lowercased().contains($0) })
            if aIsBulk != bIsBulk { return !aIsBulk }
            return false
        }

        print("🍌 Filtered to \(sortedPortions?.count ?? 0) meaningful portions")

        // Use first portion as default serving size, or 100g if none available
        let defaultServing: String
        if let firstPortion = sortedPortions?.first {
            // Format: "1.0 medium (118g)" so the parser can extract gram weight
            let gramWeight = Int(firstPortion.gramWeight)
            defaultServing = "1.0 \(firstPortion.modifier) (\(gramWeight)g)"
        } else {
            defaultServing = "100g"
        }
        
        // Create a human-readable list of available portions
        let portionsList = servingPortions?.map { portion in
            "\(portion.modifier): \(Int(portion.gramWeight))g"
        }.joined(separator: ", ")
        
        print("🍌 Default serving: \(defaultServing)")
        print("🍌 Available portions: \(portionsList ?? "none")")
        
        return ProductInfo(
            code: "usda_\(fdcId)",
            productName: description,
            brands: "USDA",
            imageUrl: nil,
            nutriments: nutriments,
            servingSize: defaultServing,
            quantity: portionsList, // Store portions info for reference
            portions: sortedPortions,
            countriesTags: ["en:united-states"],  // USDA is US-only
            lastUsed: nil  // Not from My Foods
        )
    }
}

// MARK: - Errors

public enum USDAError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)
    case noAPIKey
    case noResults
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Could not create valid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode):
            return "Server error: \(statusCode)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .noAPIKey:
            return "No USDA API key configured. Get one at https://fdc.nal.usda.gov/api-key-signup.html"
        case .noResults:
            return "No results found in USDA database"
        }
    }
}

// MARK: - Micronutrients per 100g (extracted from USDA search result nutrients array)

public struct USDAMicrosPer100g {
    public var caloriesPer100g: Double = 0
    public var potassium:   Double?
    public var calcium:     Double?
    public var iron:        Double?
    public var magnesium:   Double?
    public var zinc:        Double?
    public var vitaminA:    Double?
    public var potassium2:  Double? // unused — kept for layout symmetry
    public var vitaminC:    Double?
    public var vitaminD:    Double?
    public var vitaminE:    Double?
    public var vitaminK:    Double?
    public var vitaminB6:   Double?
    public var vitaminB12:  Double?
    public var folate:      Double?
    public var choline:     Double?
    public var caffeine:    Double?
}

public extension USDAFoodItem {
    var microsPer100g: USDAMicrosPer100g {
        var m = USDAMicrosPer100g()
        for n in foodNutrients ?? [] {
            guard let num = n.nutrientNumber else { continue }
            let v = n.value
            switch num {
            case "208": m.caloriesPer100g = v
            case "306": m.potassium  = v > 0 ? v : nil
            case "301": m.calcium    = v > 0 ? v : nil
            case "303": m.iron       = v > 0 ? v : nil
            case "304": m.magnesium  = v > 0 ? v : nil
            case "309": m.zinc       = v > 0 ? v : nil
            case "320": m.vitaminA   = v > 0 ? v : nil
            case "401": m.vitaminC   = v > 0 ? v : nil
            case "324": m.vitaminD   = v > 0 ? v : nil
            case "323": m.vitaminE   = v > 0 ? v : nil
            case "430": m.vitaminK   = v > 0 ? v : nil
            case "415": m.vitaminB6  = v > 0 ? v : nil
            case "418": m.vitaminB12 = v > 0 ? v : nil
            case "417": m.folate     = v > 0 ? v : nil
            case "421": m.choline    = v > 0 ? v : nil
            case "262": m.caffeine   = v > 0 ? v : nil
            default: break
            }
        }
        return m
    }
}
