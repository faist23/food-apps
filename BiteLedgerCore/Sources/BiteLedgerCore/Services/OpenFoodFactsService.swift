import Foundation

// MARK: - Flexible Decoding

/// Handles decoding values that might be strings or numbers
public struct FlexibleDouble: Codable, Sendable {
    public let value: Double
    
    public init(_ value: Double) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self),
                  let doubleValue = Double(stringValue) {
            value = doubleValue
        } else {
            value = 0
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

// MARK: - Service

/// Service for interacting with the Open Food Facts API
@MainActor
public class OpenFoodFactsService {
    public static let shared = OpenFoodFactsService()
    
    private let baseURL = "https://world.openfoodfacts.org/api/v2"
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }
    
    /// Fetch product information by barcode
    public func fetchProduct(barcode: String) async throws -> ProductInfo {
        let urlString = "\(baseURL)/product/\(barcode).json"
        
        guard let url = URL(string: urlString) else {
            throw OpenFoodFactsError.invalidBarcode
        }
        
        print("📷 Barcode lookup: \(barcode)")
        print("🌐 URL: \(urlString)")
        
        var request = URLRequest(url: url)
        request.setValue("BiteLedger - iOS Food Tracker", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenFoodFactsError.invalidResponse
        }
        
        print("🌐 Barcode lookup status: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            throw OpenFoodFactsError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        // Don't use convertFromSnakeCase - we have custom CodingKeys
        
        let apiResponse = try decoder.decode(OpenFoodFactsResponse.self, from: data)
        
        guard apiResponse.status == 1, let product = apiResponse.product else {
            print("❌ Product not found or invalid status")
            throw OpenFoodFactsError.productNotFound
        }
        
        print("📦 Found product: \(product.displayName)")
        print("   - Serving size: '\(product.servingSize ?? "nil")'")
        if let nutriments = product.nutriments {
            print("   - Calories: \(nutriments.calories)")
        } else {
            print("   - Nutriments: nil")
        }
        
        return product
    }
    
    /// Search for products by name
    public func searchProducts(query: String, page: Int = 1) async throws -> [ProductInfo] {
        // Use the world endpoint for faster response, filter client-side
        let urlString = "https://world.openfoodfacts.org/cgi/search.pl"

        guard var components = URLComponents(string: urlString) else {
            throw OpenFoodFactsError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "page_size", value: "25"),
            URLQueryItem(name: "fields", value: "code,product_name,brands,image_url,nutriments,serving_size,quantity,countries_tags")
        ]
        
        guard let url = components.url else {
            throw OpenFoodFactsError.invalidURL
        }
        
        print("🌐 API Request URL: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.setValue("BiteLedger - iOS Food Tracker", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenFoodFactsError.invalidResponse
        }
        
        print("🌐 API Response status: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            throw OpenFoodFactsError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        // Don't use convertFromSnakeCase - we have custom CodingKeys
        
        do {
            let searchResponse = try decoder.decode(OpenFoodFactsSearchResponse.self, from: data)
            print("🌐 API decoded successfully: \(searchResponse.products.count) products")
            
            // Log first few products for debugging
            for (index, product) in searchResponse.products.prefix(3).enumerated() {
                print("📦 Product \(index + 1): \(product.displayName)")
                print("   - Barcode: \(product.code)")
                print("   - Brand: \(product.brands ?? "nil")")
                print("   - Serving: \(product.servingSize ?? "nil")")
                if let nutriments = product.nutriments {
                    print("   - Calories: \(nutriments.calories)")
                } else {
                    print("   - Nutriments: nil")
                }
            }
            
            return searchResponse.products
        } catch {
            print("❌ Decoding error: \(error)")
            throw OpenFoodFactsError.decodingError(error)
        }
    }
}

// MARK: - API Response Models

/// Response from the Open Food Facts API for a single product
public struct OpenFoodFactsResponse: Codable {
    public let status: Int
    public let product: ProductInfo?
}

/// Response from the Open Food Facts search API
public struct OpenFoodFactsSearchResponse: Codable {
    public let count: Int
    public let page: Int
    public let pageSize: Int
    public let products: [ProductInfo]
    
    public enum CodingKeys: String, CodingKey {
        case count
        case page
        case pageSize = "page_size"
        case products
    }
}

/// Product information from Open Food Facts
public struct ProductInfo: Codable, Identifiable, Sendable {
    public let code: String
    public let productName: String?
    public let brands: String?
    public let imageUrl: String?
    public let nutriments: Nutriments?
    public let servingSize: String?
    public let quantity: String?
    public let portions: [ServingPortion]?  // USDA portions (e.g., "1 medium banana")
    public let countriesTags: [String]?  // Countries where product is sold
    public let lastUsed: Date?  // For My Foods - when this item was last used

    public var id: String { code }
    
    public var displayName: String {
        if let name = productName, !name.isEmpty {
            return name
        }
        return "Unknown Product"
    }
    
    public var displayBrand: String {
        brands ?? "Unknown Brand"
    }
    
    public enum CodingKeys: String, CodingKey {
        case code
        case productName = "product_name"
        case brands
        case imageUrl = "image_url"
        case nutriments
        case servingSize = "serving_size"
        case quantity
        case portions
        case countriesTags = "countries_tags"
        // lastUsed is not from API, so not in CodingKeys
    }
    
    // Custom initializer for creating ProductInfo manually (with lastUsed)
    public init(code: String, productName: String?, brands: String?, imageUrl: String?, nutriments: Nutriments?, servingSize: String?, quantity: String?, portions: [ServingPortion]?, countriesTags: [String]?, lastUsed: Date?) {
        self.code = code
        self.productName = productName
        self.brands = brands
        self.imageUrl = imageUrl
        self.nutriments = nutriments
        self.servingSize = servingSize
        self.quantity = quantity
        self.portions = portions
        self.countriesTags = countriesTags
        self.lastUsed = lastUsed
    }
    
    // Custom decoder for API responses (lastUsed defaults to nil)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        productName = try? container.decode(String.self, forKey: .productName)
        brands = try? container.decode(String.self, forKey: .brands)
        imageUrl = try? container.decode(String.self, forKey: .imageUrl)
        nutriments = try? container.decode(Nutriments.self, forKey: .nutriments)
        servingSize = try? container.decode(String.self, forKey: .servingSize)
        quantity = try? container.decode(String.self, forKey: .quantity)
        portions = try? container.decode([ServingPortion].self, forKey: .portions)
        countriesTags = try? container.decode([String].self, forKey: .countriesTags)
        lastUsed = nil  // Not from API
    }
}

/// Represents a serving portion (primarily from USDA)
public struct ServingPortion: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let amount: Double
    public let modifier: String
    public let gramWeight: Double
    
    public var displayName: String {
        if amount == 1.0 {
            return modifier
        }
        return "\(amount) \(modifier)"
    }
}

/// Nutrition information from Open Food Facts
public struct Nutriments: Codable, Sendable {
    // Per 100g values - these might be strings or numbers in the API
    public let energyKcal100g: FlexibleDouble?
    public let energyKcalComputed: Double?
    public let proteins100g: FlexibleDouble?
    public let carbohydrates100g: FlexibleDouble?
    public let sugars100g: FlexibleDouble?
    public let fat100g: FlexibleDouble?
    public let saturatedFat100g: FlexibleDouble?
    public let transFat100g: FlexibleDouble?
    public let monounsaturatedFat100g: FlexibleDouble?
    public let polyunsaturatedFat100g: FlexibleDouble?
    public let fiber100g: FlexibleDouble?
    public let sodium100g: FlexibleDouble?
    public let salt100g: FlexibleDouble?
    public let cholesterol100g: FlexibleDouble?
    
    // Vitamins and minerals
    public let vitaminA100g: FlexibleDouble?
    public let vitaminC100g: FlexibleDouble?
    public let vitaminD100g: FlexibleDouble?
    public let vitaminE100g: FlexibleDouble?
    public let vitaminK100g: FlexibleDouble?
    public let vitaminB6100g: FlexibleDouble?
    public let vitaminB12100g: FlexibleDouble?
    public let folate100g: FlexibleDouble?
    public let choline100g: FlexibleDouble?
    public let calcium100g: FlexibleDouble?
    public let iron100g: FlexibleDouble?
    public let potassium100g: FlexibleDouble?
    public let magnesium100g: FlexibleDouble?
    public let zinc100g: FlexibleDouble?
    public let caffeine100g: FlexibleDouble?
    
    // Serving values (if available)
    public let energyKcalServing: FlexibleDouble?
    public let proteinsServing: FlexibleDouble?
    public let carbohydratesServing: FlexibleDouble?
    public let sugarsServing: FlexibleDouble?
    public let fatServing: FlexibleDouble?
    public let saturatedFatServing: FlexibleDouble?
    public let fiberServing: FlexibleDouble?
    public let sodiumServing: FlexibleDouble?
    // Per-serving minerals/vitamins (FatSecret only — not in OpenFoodFacts JSON)
    // These use default values so CodingKeys-based synthesis still works for OFf responses.
    public var potassiumServing: FlexibleDouble? = nil   // mg/serving
    public var cholesterolServing: FlexibleDouble? = nil // mg/serving
    public var calciumServing: FlexibleDouble? = nil     // mg/serving
    public var ironServing: FlexibleDouble? = nil        // mg/serving
    public var caffeineServing: FlexibleDouble? = nil    // mg/serving
    public var vitaminAServing: FlexibleDouble? = nil    // mcg/serving
    public var vitaminCServing: FlexibleDouble? = nil    // mg/serving
    
    public enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case energyKcalComputed = "energy-kcal_value_computed"
        case proteins100g = "proteins_100g"
        case carbohydrates100g = "carbohydrates_100g"
        case sugars100g = "sugars_100g"
        case fat100g = "fat_100g"
        case saturatedFat100g = "saturated-fat_100g"
        case transFat100g = "trans-fat_100g"
        case monounsaturatedFat100g = "monounsaturated-fat_100g"
        case polyunsaturatedFat100g = "polyunsaturated-fat_100g"
        case fiber100g = "fiber_100g"
        case sodium100g = "sodium_100g"
        case salt100g = "salt_100g"
        case cholesterol100g = "cholesterol_100g"
        case vitaminA100g = "vitamin-a_100g"
        case vitaminC100g = "vitamin-c_100g"
        case vitaminD100g = "vitamin-d_100g"
        case vitaminE100g = "vitamin-e_100g"
        case vitaminK100g = "vitamin-k_100g"
        case vitaminB6100g = "vitamin-b6_100g"
        case vitaminB12100g = "vitamin-b12_100g"
        case folate100g = "folate_100g"
        case choline100g = "choline_100g"
        case calcium100g = "calcium_100g"
        case iron100g = "iron_100g"
        case potassium100g = "potassium_100g"
        case magnesium100g = "magnesium_100g"
        case zinc100g = "zinc_100g"
        case caffeine100g = "caffeine_100g"
        case energyKcalServing = "energy-kcal_serving"
        case proteinsServing = "proteins_serving"
        case carbohydratesServing = "carbohydrates_serving"
        case sugarsServing = "sugars_serving"
        case fatServing = "fat_serving"
        case saturatedFatServing = "saturated-fat_serving"
        case fiberServing = "fiber_serving"
        case sodiumServing = "sodium_serving"
    }

    public init(
        energyKcal100g: FlexibleDouble? = nil, energyKcalComputed: Double? = nil,
        proteins100g: FlexibleDouble? = nil, carbohydrates100g: FlexibleDouble? = nil,
        sugars100g: FlexibleDouble? = nil, fat100g: FlexibleDouble? = nil,
        saturatedFat100g: FlexibleDouble? = nil, transFat100g: FlexibleDouble? = nil,
        monounsaturatedFat100g: FlexibleDouble? = nil, polyunsaturatedFat100g: FlexibleDouble? = nil,
        fiber100g: FlexibleDouble? = nil, sodium100g: FlexibleDouble? = nil,
        salt100g: FlexibleDouble? = nil, cholesterol100g: FlexibleDouble? = nil,
        vitaminA100g: FlexibleDouble? = nil, vitaminC100g: FlexibleDouble? = nil,
        vitaminD100g: FlexibleDouble? = nil, vitaminE100g: FlexibleDouble? = nil,
        vitaminK100g: FlexibleDouble? = nil, vitaminB6100g: FlexibleDouble? = nil,
        vitaminB12100g: FlexibleDouble? = nil, folate100g: FlexibleDouble? = nil,
        choline100g: FlexibleDouble? = nil, calcium100g: FlexibleDouble? = nil,
        iron100g: FlexibleDouble? = nil, potassium100g: FlexibleDouble? = nil,
        magnesium100g: FlexibleDouble? = nil, zinc100g: FlexibleDouble? = nil,
        caffeine100g: FlexibleDouble? = nil,
        energyKcalServing: FlexibleDouble? = nil, proteinsServing: FlexibleDouble? = nil,
        carbohydratesServing: FlexibleDouble? = nil, sugarsServing: FlexibleDouble? = nil,
        fatServing: FlexibleDouble? = nil, saturatedFatServing: FlexibleDouble? = nil,
        fiberServing: FlexibleDouble? = nil, sodiumServing: FlexibleDouble? = nil,
        potassiumServing: FlexibleDouble? = nil, cholesterolServing: FlexibleDouble? = nil,
        calciumServing: FlexibleDouble? = nil, ironServing: FlexibleDouble? = nil,
        caffeineServing: FlexibleDouble? = nil, vitaminAServing: FlexibleDouble? = nil,
        vitaminCServing: FlexibleDouble? = nil
    ) {
        self.energyKcal100g = energyKcal100g; self.energyKcalComputed = energyKcalComputed
        self.proteins100g = proteins100g; self.carbohydrates100g = carbohydrates100g
        self.sugars100g = sugars100g; self.fat100g = fat100g
        self.saturatedFat100g = saturatedFat100g; self.transFat100g = transFat100g
        self.monounsaturatedFat100g = monounsaturatedFat100g; self.polyunsaturatedFat100g = polyunsaturatedFat100g
        self.fiber100g = fiber100g; self.sodium100g = sodium100g
        self.salt100g = salt100g; self.cholesterol100g = cholesterol100g
        self.vitaminA100g = vitaminA100g; self.vitaminC100g = vitaminC100g
        self.vitaminD100g = vitaminD100g; self.vitaminE100g = vitaminE100g
        self.vitaminK100g = vitaminK100g; self.vitaminB6100g   = vitaminB6100g
        self.vitaminB12100g = vitaminB12100g; self.folate100g = folate100g
        self.choline100g = choline100g; self.calcium100g = calcium100g
        self.iron100g = iron100g; self.potassium100g = potassium100g
        self.magnesium100g = magnesium100g; self.zinc100g = zinc100g
        self.caffeine100g = caffeine100g
        self.energyKcalServing = energyKcalServing; self.proteinsServing = proteinsServing
        self.carbohydratesServing = carbohydratesServing; self.sugarsServing = sugarsServing
        self.fatServing = fatServing; self.saturatedFatServing = saturatedFatServing
        self.fiberServing = fiberServing; self.sodiumServing = sodiumServing
        self.potassiumServing = potassiumServing; self.cholesterolServing = cholesterolServing
        self.calciumServing = calciumServing; self.ironServing = ironServing
        self.caffeineServing = caffeineServing; self.vitaminAServing = vitaminAServing
        self.vitaminCServing = vitaminCServing
    }

    public var calories: Double {
        // Prefer the computed value if energy-kcal_100g is 0
        if let kcal = energyKcal100g?.value, kcal > 0 {
            return kcal
        }
        return energyKcalComputed ?? 0
    }
    
    /// Determine the nutrition reference type for this product
    /// - Parameter servingGrams: The gram weight of the serving size, if known (0 if unknown)
    public func nutritionReferenceType(servingGrams: Double = -1) -> String {
        // If serving has no gram weight (0g), prefer per-serving data if available
        if servingGrams == 0, let servingCal = energyKcalServing?.value, servingCal > 0 {
            return "perServing"
        }
        
        // Check if we have actual per-100g data
        if let kcal100g = energyKcal100g?.value, kcal100g > 0 {
            return "per100g"
        } else if let servingCal = energyKcalServing?.value, servingCal > 0 {
            return "perServing"
        }
        return "per100g"  // Default
    }
    
    /// Convert to app's NutritionFacts model
    /// - Parameters:
    ///   - servingMultiplier: Multiplier for nutrition values
    ///   - servingGrams: Gram weight of serving (0 if unknown, use per-serving data)
    public func toNutritionFacts(servingMultiplier: Double = 1.0, servingGrams: Double = -1) -> NutritionFacts {
        // Prefer per-100g values, but fall back to per-serving values if available (e.g., FatSecret)
        // For per-serving values, apply the multiplier directly (it's already per serving)
        let caloriesValue: Double
        let proteinValue: Double
        let carbsValue: Double
        let fatValue: Double
        let fiberValue: Double
        let sugarValue: Double
        let sodiumValue: Double
        let saturatedFatValue: Double
        
        print("🍽️ toNutritionFacts called with multiplier: \(servingMultiplier), servingGrams: \(servingGrams)")
        print("🍽️ energyKcal100g: \(energyKcal100g?.value ?? 0)")
        print("🍽️ energyKcalServing: \(energyKcalServing?.value ?? 0)")
        
        // Prefer per-serving data if it exists (FatSecret, manually entered foods with perServing type)
        // This handles both cases: servingGrams == 0 (FatSecret) and servingGrams > 0 (Halos)
        let hasServingData = energyKcalServing?.value ?? 0 > 0
        
        // Check if we have actual per-100g data (not just computed calories)
        // Only use per-100g if we don't have serving data
        if !hasServingData, let kcal100g = energyKcal100g?.value, kcal100g > 0 {
            // Has per-100g data - use it with multiplier
            print("🍽️ Using per-100g nutrition data")
            caloriesValue = kcal100g * servingMultiplier
            proteinValue = (proteins100g?.value ?? 0) * servingMultiplier
            carbsValue = (carbohydrates100g?.value ?? 0) * servingMultiplier
            fatValue = (fat100g?.value ?? 0) * servingMultiplier
            fiberValue = (fiber100g?.value ?? 0) * servingMultiplier
            sugarValue = (sugars100g?.value ?? 0) * servingMultiplier
            sodiumValue = (sodium100g?.value ?? 0) * servingMultiplier
            saturatedFatValue = (saturatedFat100g?.value ?? 0) * servingMultiplier
        } else if let servingCal = energyKcalServing?.value, servingCal > 0 {
            // Has per-serving data (e.g., FatSecret or items with no gram weight) - use it with multiplier
            print("🍽️ Using per-serving nutrition data: \(servingCal) cal")
            caloriesValue = servingCal * servingMultiplier
            proteinValue = (proteinsServing?.value ?? 0) * servingMultiplier
            carbsValue = (carbohydratesServing?.value ?? 0) * servingMultiplier
            fatValue = (fatServing?.value ?? 0) * servingMultiplier
            fiberValue = (fiberServing?.value ?? 0) * servingMultiplier
            sugarValue = (sugarsServing?.value ?? 0) * servingMultiplier
            sodiumValue = (sodiumServing?.value ?? 0) * servingMultiplier
            saturatedFatValue = (saturatedFatServing?.value ?? 0) * servingMultiplier
            print("🍽️ Calculated values - cal: \(caloriesValue), protein: \(proteinValue), carbs: \(carbsValue), fat: \(fatValue), fiber: \(fiberValue), sugar: \(sugarValue), sodium(g): \(sodiumValue)")
        } else {
            // No data
            print("🍽️ No nutrition data available")
            caloriesValue = 0
            proteinValue = 0
            carbsValue = 0
            fatValue = 0
            fiberValue = 0
            sugarValue = 0
            sodiumValue = 0
            saturatedFatValue = 0
        }
        
        // Per-100g micronutrient fields must be scaled by grams, not serving count.
        // When using per-serving data with a known gramWeight, derive the gram-based multiplier.
        // Otherwise fall back to servingMultiplier (correct for the per-100g path where
        // servingMultiplier == totalGrams/100 already).
        let microMultiplier: Double
        if hasServingData && servingGrams > 0 {
            microMultiplier = servingGrams * servingMultiplier / 100.0
        } else {
            microMultiplier = servingMultiplier
        }

        return NutritionFacts(
            caloriesPer100g: caloriesValue,
            proteinPer100g: proteinValue,
            carbsPer100g: carbsValue,
            fatPer100g: fatValue,
            fiberPer100g: fiberValue,
            sugarPer100g: sugarValue,
            sodiumPer100g: sodiumValue,
            saturatedFatPer100g: saturatedFatValue,
            transFatPer100g: (transFat100g?.value ?? 0) * microMultiplier,
            monounsaturatedFatPer100g: (monounsaturatedFat100g?.value ?? 0) * microMultiplier,
            polyunsaturatedFatPer100g: (polyunsaturatedFat100g?.value ?? 0) * microMultiplier,
            cholesterolPer100g: (cholesterol100g?.value ?? 0) * microMultiplier,
            magnesiumPer100g: (magnesium100g?.value ?? 0) * microMultiplier,
            zincPer100g: (zinc100g?.value ?? 0) * microMultiplier,
            vitaminAPer100g: (vitaminA100g?.value ?? 0) * microMultiplier,
            vitaminCPer100g: (vitaminC100g?.value ?? 0) * microMultiplier,
            vitaminDPer100g: (vitaminD100g?.value ?? 0) * microMultiplier,
            vitaminEPer100g: (vitaminE100g?.value ?? 0) * microMultiplier,
            vitaminKPer100g: (vitaminK100g?.value ?? 0) * microMultiplier,
            vitaminB6Per100g: (vitaminB6100g?.value ?? 0) * microMultiplier,
            vitaminB12Per100g: (vitaminB12100g?.value ?? 0) * microMultiplier,
            folatePer100g: (folate100g?.value ?? 0) * microMultiplier,
            cholinePer100g: (choline100g?.value ?? 0) * microMultiplier,
            calciumPer100g: (calcium100g?.value ?? 0) * microMultiplier,
            ironPer100g: (iron100g?.value ?? 0) * microMultiplier,
            potassiumPer100g: (potassium100g?.value ?? 0) * microMultiplier,
            caffeinePer100g: (caffeine100g?.value ?? 0) * microMultiplier
        )
    }
}

// MARK: - Errors

public enum OpenFoodFactsError: LocalizedError {
    case invalidBarcode
    case invalidURL
    case invalidResponse
    case productNotFound
    case httpError(statusCode: Int)
    case decodingError(Error)
    
    public var errorDescription: String? {
        switch self {
        case .invalidBarcode:
            return "Invalid barcode format"
        case .invalidURL:
            return "Could not create valid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .productNotFound:
            return "Product not found in database"
        case .httpError(let statusCode):
            return "Server error: \(statusCode)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}
