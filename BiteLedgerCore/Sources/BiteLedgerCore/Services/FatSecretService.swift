import Foundation
import CommonCrypto

// MARK: - FatSecret API Service

/// Service for interacting with the FatSecret Platform API
/// Uses OAuth 1.0 authentication for API requests
@MainActor
public class FatSecretService {
    public static let shared = FatSecretService()

    private let baseURL = "https://platform.fatsecret.com/rest/server.api"
    private let session: URLSession

    private var consumerKey: String?
    private var consumerSecret: String?

    private init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
        loadCredentials()
    }

    private func loadCredentials() {
        guard let path = Bundle.main.path(forResource: "fatsecret", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: String] else {
            print("⚠️ FatSecret credentials not found in fatsecret.plist")
            return
        }
        consumerKey    = dict["ConsumerKey"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        consumerSecret = dict["ConsumerSecret"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if consumerKey != nil && consumerSecret != nil {
            print("✅ FatSecret OAuth 1.0 credentials loaded")
        } else {
            print("⚠️ FatSecret credentials incomplete")
        }
    }

    // MARK: - Signed Request Builder

    private func makeSignedRequest(params: [String: String]) throws -> URLRequest {
        guard let key = consumerKey, let secret = consumerSecret else {
            throw FatSecretError.noCredentials
        }

        let timestamp = "\(Int(Date().timeIntervalSince1970))"
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")

        var allParams = params
        allParams["oauth_consumer_key"]     = key
        allParams["oauth_signature_method"] = "HMAC-SHA1"
        allParams["oauth_timestamp"]        = timestamp
        allParams["oauth_nonce"]            = nonce
        allParams["oauth_version"]          = "1.0"

        let signature = generateOAuthSignature(parameters: allParams, consumerSecret: secret)
        allParams["oauth_signature"] = signature

        // Use percentEncodedQuery so that Base64 '+' signs become '%2B'.
        // URLComponents.queryItems does NOT encode '+', causing servers to
        // interpret it as a space and reject the signature.
        let percentEncodedQuery = allParams.sorted { $0.key < $1.key }
            .map { "\($0.key.oauthEncoded())=\($0.value.oauthEncoded())" }
            .joined(separator: "&")
        guard var components = URLComponents(string: baseURL) else {
            throw FatSecretError.invalidURL
        }
        components.percentEncodedQuery = percentEncodedQuery
        guard let url = components.url else {
            throw FatSecretError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("BiteLedger - iOS Food Tracker", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func executeRequest(_ request: URLRequest, retryCount: Int = 0) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FatSecretError.invalidResponse
        }
        print("🌐 FatSecret status: \(http.statusCode)")
        if let s = String(data: data, encoding: .utf8) {
            print("📥 FatSecret Response: \(s.prefix(500))")
        }
        guard http.statusCode == 200 else {
            throw FatSecretError.httpError(statusCode: http.statusCode)
        }
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = dict["error"] as? [String: Any] {
            let code = err["code"] as? Int ?? -1
            print("⚠️ FatSecret API Error: \(err)")
            // Code 12 = rate limit — retry up to 3 times with exponential backoff
            if code == 12 && retryCount < 3 {
                let delay = UInt64(2_000_000_000) * UInt64(retryCount + 1)  // 2s, 4s, 6s
                print("⏳ FatSecret rate limited, retrying in \(retryCount + 2)s… (attempt \(retryCount + 1)/3)")
                try await Task.sleep(nanoseconds: delay)
                return try await executeRequest(request, retryCount: retryCount + 1)
            }
            throw FatSecretError.httpError(statusCode: code)
        }
        return data
    }

    // MARK: - Public API

    public func searchFoods(query: String, page: Int = 0, maxResults: Int = 20) async throws -> [FatSecretFood] {
        let request = try makeSignedRequest(params: [
            "method":            "foods.search",
            "search_expression": query,
            "page_number":       "\(page)",
            "max_results":       "\(maxResults)",
            "format":            "json"
        ])
        let data = try await executeRequest(request)

        do {
            let searchResponse = try JSONDecoder().decode(FatSecretSearchResponse.self, from: data)
            let foods: [FatSecretFood]
            switch searchResponse.foods.food {
            case .array(let a):  foods = a
            case .single(let s): foods = [s]
            }
            print("✅ FatSecret decoded \(foods.count) foods")
            return foods
        } catch {
            print("❌ FatSecret search decode error: \(error)")
            if let jsonDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = jsonDict["error"] as? [String: Any] {
                print("⚠️ FatSecret API Error: \(err)")
                return []
            }
            throw FatSecretError.decodingError(error)
        }
    }

    public func getFoodDetails(foodId: String) async throws -> FatSecretFood {
        let request = try makeSignedRequest(params: [
            "method":  "food.get",
            "food_id": foodId,
            "format":  "json"
        ])
        let data = try await executeRequest(request)

        if let s = String(data: data, encoding: .utf8) {
            print("📥 FatSecret Detail: \(s.prefix(1000))")
        }

        let decoder = JSONDecoder()
        if let wrapped = try? decoder.decode(FatSecretFoodDetailResponse.self, from: data) {
            return wrapped.food
        }
        if let direct = try? decoder.decode(FatSecretFood.self, from: data) {
            return direct
        }
        if let nested = try? decoder.decode(FatSecretSearchResponse.self, from: data),
           let first = nested.foods.food.first {
            return first
        }
        throw FatSecretError.decodingError(
            NSError(domain: "FatSecretService", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected food.get response format"])
        )
    }

    // MARK: - OAuth 1.0 Signature

    private func generateOAuthSignature(parameters: [String: String], consumerSecret: String) -> String {
        let sortedParams = parameters.sorted { $0.key < $1.key }
        let paramString = sortedParams
            .map { "\($0.key.oauthEncoded())=\($0.value.oauthEncoded())" }
            .joined(separator: "&")

        let base = "GET&\(baseURL.oauthEncoded())&\(paramString.oauthEncoded())"
        let signingKey = "\(consumerSecret.oauthEncoded())&"
        let signature = base.hmacSHA1(key: signingKey)
        print("🔐 Base: \(base)")
        print("🔐 Signature: \(signature)")
        return signature
    }
}

// MARK: - OAuth String Helpers

private extension String {
    func oauthEncoded() -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }

    func hmacSHA1(key: String) -> String {
        let keyData = Data(key.utf8)
        let msgData = Data(utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        keyData.withUnsafeBytes { k in
            msgData.withUnsafeBytes { m in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA1),
                       k.baseAddress, keyData.count,
                       m.baseAddress, msgData.count,
                       &digest)
            }
        }
        return Data(digest).base64EncodedString()
    }
}

// MARK: - Response Models

public struct FatSecretSearchResponse: Codable {
    public let foods: FatSecretFoodsContainer
}

public struct FatSecretFoodsContainer: Codable {
    public let food: FoodOrArray
    public let maxResults: String
    public let pageNumber: String
    public let totalResults: String

    public enum CodingKeys: String, CodingKey {
        case food
        case maxResults = "max_results"
        case pageNumber = "page_number"
        case totalResults = "total_results"
    }
}

// Custom type to handle single food or array of foods
public enum FoodOrArray: Codable {
    case single(FatSecretFood)
    case array([FatSecretFood])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let array = try? container.decode([FatSecretFood].self) {
            self = .array(array)
        } else if let single = try? container.decode(FatSecretFood.self) {
            self = .single(single)
        } else {
            throw DecodingError.typeMismatch(FoodOrArray.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected array or single food"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .single(let food):
            try container.encode(food)
        case .array(let foods):
            try container.encode(foods)
        }
    }

    public var first: FatSecretFood? {
        switch self {
        case .single(let f): return f
        case .array(let a):  return a.first
        }
    }

    public static func ~= (pattern: FoodOrArray, value: Any) -> Bool {
        switch pattern {
        case .single:
            return value is FatSecretFood
        case .array:
            return value is [FatSecretFood]
        }
    }
}

public struct FatSecretFoodDetailResponse: Codable {
    public let food: FatSecretFood
}

// MARK: - Detailed Serving Models (food.get response)

public struct FatSecretServingData: Codable, Sendable {
    public let servingDescription: String?
    public let metricServingAmount: String?
    public let metricServingUnit: String?
    public let calories: String?
    public let carbohydrate: String?
    public let protein: String?
    public let fat: String?
    public let saturatedFat: String?
    public let cholesterol: String?
    public let sodium: String?
    public let potassium: String?
    public let fiber: String?
    public let sugar: String?
    // Vitamins/minerals — FatSecret returns these as % DV strings (e.g., "21" = 21%)
    public let vitaminA: String?
    public let vitaminC: String?
    public let calcium: String?
    public let iron: String?

    public enum CodingKeys: String, CodingKey {
        case servingDescription = "serving_description"
        case metricServingAmount = "metric_serving_amount"
        case metricServingUnit = "metric_serving_unit"
        case calories, carbohydrate, protein, fat
        case saturatedFat = "saturated_fat"
        case cholesterol, sodium, potassium, fiber, sugar
        case vitaminA = "vitamin_a"
        case vitaminC = "vitamin_c"
        case calcium, iron
    }

    private func toPositiveDouble(_ s: String?) -> Double? {
        guard let s, let d = Double(s), d > 0 else { return nil }
        return d
    }

    public var caloriesDouble: Double  { Double(calories ?? "0") ?? 0 }
    public var carbsDouble: Double     { Double(carbohydrate ?? "0") ?? 0 }
    public var proteinDouble: Double   { Double(protein ?? "0") ?? 0 }
    public var fatDouble: Double       { Double(fat ?? "0") ?? 0 }
    public var saturatedFatGrams: Double? { toPositiveDouble(saturatedFat) }
    public var cholesterolMg: Double?  { toPositiveDouble(cholesterol) }
    public var sodiumMg: Double?       { toPositiveDouble(sodium) }
    public var potassiumMg: Double?    { toPositiveDouble(potassium) }
    public var fiberGrams: Double?     { toPositiveDouble(fiber) }
    public var sugarGrams: Double?     { toPositiveDouble(sugar) }
    /// Gram weight of this serving (ml treated as g, i.e. water density)
    public var metricGrams: Double?    { toPositiveDouble(metricServingAmount) }

    // FDA Daily Values used to convert % DV → absolute amounts
    private static let vitaminADV: Double  = 900.0   // mcg RAE
    private static let vitaminCDV: Double  = 90.0    // mg
    private static let calciumDV: Double   = 1300.0  // mg
    private static let ironDV: Double      = 18.0    // mg

    public var vitaminAMcg: Double? {
        guard let s = vitaminA, let pct = Double(s), pct > 0 else { return nil }
        return pct / 100.0 * Self.vitaminADV
    }
    public var vitaminCMg: Double? {
        guard let s = vitaminC, let pct = Double(s), pct > 0 else { return nil }
        return pct / 100.0 * Self.vitaminCDV
    }
    public var calciumMg: Double? {
        guard let s = calcium, let pct = Double(s), pct > 0 else { return nil }
        return pct / 100.0 * Self.calciumDV
    }
    public var ironMg: Double? {
        guard let s = iron, let pct = Double(s), pct > 0 else { return nil }
        return pct / 100.0 * Self.ironDV
    }
}

public struct FatSecretServingsContainer: Codable, Sendable {
    public let servingList: [FatSecretServingData]

    public enum CodingKeys: String, CodingKey { case serving }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let array = try? container.decode([FatSecretServingData].self, forKey: .serving) {
            print("🍽️ Decoded serving as array (\(array.count) items)")
            servingList = array
        } else if let single = try? container.decode(FatSecretServingData.self, forKey: .serving) {
            print("🍽️ Decoded serving as single item")
            servingList = [single]
        } else {
            print("⚠️ Could not decode serving field - neither array nor single object")
            servingList = []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(servingList, forKey: .serving)
    }

    public var first: FatSecretServingData? { servingList.first }
}

public struct FatSecretFood: Codable, Identifiable, Sendable {
    public let foodId: String
    public let foodName: String
    public let foodType: String
    public let brandName: String?
    public let foodDescription: String?
    public let foodUrl: String?
    public let servings: FatSecretServingsContainer?  // Only present in food.get detail response

    public var id: String { foodId }

    public enum CodingKeys: String, CodingKey {
        case foodId = "food_id"
        case foodName = "food_name"
        case foodType = "food_type"
        case brandName = "brand_name"
        case foodDescription = "food_description"
        case foodUrl = "food_url"
        case servings
    }

    public var displayName: String {
        foodName
    }

    public var displayBrand: String {
        brandName ?? "Generic"
    }
}

// MARK: - Conversion Extensions

extension FatSecretFood {
    /// Convert FatSecret food to app's ProductInfo model.
    /// Uses detailed serving data from food.get when available; falls back to
    /// parsing the food_description summary from search results.
    public func toProductInfo() -> ProductInfo? {
        if let serving = servings?.first {
            return toProductInfoFromServing(serving)
        }
        return toProductInfoFromDescription()
    }

    // MARK: - Detail path (food.get)

    private func toProductInfoFromServing(_ serving: FatSecretServingData) -> ProductInfo {
        print("🍔 Building ProductInfo from detailed serving for: \(foodName)")
        let servingDesc = serving.servingDescription ?? "1 serving"
        let metricGrams = serving.metricGrams  // nil if not available

        // Compute per-100g values for nutrients not in Nutriments serving fields
        // (potassium, cholesterol) — used by the vitamins/minerals section of the picker.
        let potassium100g: FlexibleDouble?
        let cholesterol100g: FlexibleDouble?
        if let g = metricGrams, g > 0 {
            potassium100g  = serving.potassiumMg.map  { FlexibleDouble(($0 / 1000.0) / g * 100.0) }
            cholesterol100g = serving.cholesterolMg.map { FlexibleDouble(($0 / 1000.0) / g * 100.0) }
        } else {
            potassium100g  = nil
            cholesterol100g = nil
        }

        let nutriments = Nutriments(
            energyKcal100g: nil,
            energyKcalComputed: serving.caloriesDouble,
            proteins100g: nil,
            carbohydrates100g: nil,
            sugars100g: nil,
            fat100g: nil,
            saturatedFat100g: nil,
            transFat100g: nil,
            monounsaturatedFat100g: nil,
            polyunsaturatedFat100g: nil,
            fiber100g: nil,
            sodium100g: nil,
            salt100g: nil,
            cholesterol100g: cholesterol100g,
            vitaminA100g: nil, vitaminC100g: nil, vitaminD100g: nil,
            vitaminE100g: nil, vitaminK100g: nil, vitaminB6100g: nil,
            vitaminB12100g: nil, folate100g: nil, choline100g: nil,
            calcium100g: nil, iron100g: nil,
            potassium100g: potassium100g,
            magnesium100g: nil, zinc100g: nil, caffeine100g: nil,
            // Per-serving macros + micronutrients from the detail endpoint
            energyKcalServing: FlexibleDouble(serving.caloriesDouble),
            proteinsServing: FlexibleDouble(serving.proteinDouble),
            carbohydratesServing: FlexibleDouble(serving.carbsDouble),
            sugarsServing: serving.sugarGrams.map { FlexibleDouble($0) },
            fatServing: FlexibleDouble(serving.fatDouble),
            saturatedFatServing: serving.saturatedFatGrams.map { FlexibleDouble($0) },
            fiberServing: serving.fiberGrams.map { FlexibleDouble($0) },
            sodiumServing: serving.sodiumMg.map { FlexibleDouble($0 / 1000.0) },  // mg → g
            // Per-serving minerals/vitamins (absolute values, mg or mcg)
            potassiumServing: serving.potassiumMg.map { FlexibleDouble($0) },
            cholesterolServing: serving.cholesterolMg.map { FlexibleDouble($0) },
            calciumServing: serving.calciumMg.map { FlexibleDouble($0) },
            ironServing: serving.ironMg.map { FlexibleDouble($0) },
            vitaminAServing: serving.vitaminAMcg.map { FlexibleDouble($0) },
            vitaminCServing: serving.vitaminCMg.map { FlexibleDouble($0) }
        )

        return ProductInfo(
            code: "fatsecret_\(foodId)",
            productName: foodName,
            brands: brandName,
            imageUrl: nil,
            nutriments: nutriments,
            servingSize: servingDesc,
            quantity: nil,
            portions: nil,
            countriesTags: nil,
            lastUsed: nil
        )
    }

    // MARK: - Fallback path (search result food_description)

    private func toProductInfoFromDescription() -> ProductInfo? {
        // Format: "Per 8 fl oz - Calories: 45kcal | Fat: 0.00g | Carbs: 11.00g | Protein: 1.00g"
        let description = foodDescription ?? ""
        print("🍔 Parsing FatSecret food_description for: \(foodName)")
        print("🍔 Description: \(description)")

        var calories: Double = 0
        var protein: Double = 0
        var carbs: Double = 0
        var fat: Double = 0
        var servingSize: String = "100g"

        if let perRange = description.range(of: "Per ", options: .caseInsensitive),
           let dashRange = description.range(of: " - ", range: perRange.upperBound..<description.endIndex) {
            servingSize = String(description[perRange.upperBound..<dashRange.lowerBound])
        }

        func extractNumber(_ pattern: String) -> Double? {
            guard let matchRange = description.range(of: pattern, options: .regularExpression),
                  let numRange = String(description[matchRange]).range(of: #"\d+\.?\d*"#, options: .regularExpression),
                  let val = Double(String(description[matchRange])[numRange]) else { return nil }
            return val
        }

        calories = extractNumber(#"Calories:\s*(\d+\.?\d*)kcal"#) ?? 0
        protein  = extractNumber(#"Protein:\s*(\d+\.?\d*)g"#)     ?? 0
        carbs    = extractNumber(#"Carbs:\s*(\d+\.?\d*)g"#)        ?? 0
        fat      = extractNumber(#"Fat:\s*(\d+\.?\d*)g"#)          ?? 0

        print("🍔 Parsed: cal=\(calories), protein=\(protein), carbs=\(carbs), fat=\(fat)")

        let nutriments = Nutriments(
            energyKcal100g: nil,
            energyKcalComputed: calories,
            proteins100g: nil,
            carbohydrates100g: nil,
            sugars100g: nil,
            fat100g: nil,
            saturatedFat100g: nil,
            transFat100g: nil,
            monounsaturatedFat100g: nil,
            polyunsaturatedFat100g: nil,
            fiber100g: nil,
            sodium100g: nil,
            salt100g: nil,
            cholesterol100g: nil,
            vitaminA100g: nil, vitaminC100g: nil, vitaminD100g: nil,
            vitaminE100g: nil, vitaminK100g: nil, vitaminB6100g: nil,
            vitaminB12100g: nil, folate100g: nil, choline100g: nil,
            calcium100g: nil, iron100g: nil,
            potassium100g: nil,
            magnesium100g: nil, zinc100g: nil, caffeine100g: nil,
            energyKcalServing: FlexibleDouble(calories),
            proteinsServing: FlexibleDouble(protein),
            carbohydratesServing: FlexibleDouble(carbs),
            sugarsServing: nil,
            fatServing: FlexibleDouble(fat),
            saturatedFatServing: nil,
            fiberServing: nil,
            sodiumServing: nil
        )

        return ProductInfo(
            code: "fatsecret_\(foodId)",
            productName: foodName,
            brands: brandName,
            imageUrl: nil,
            nutriments: nutriments,
            servingSize: servingSize,
            quantity: nil,
            portions: nil,
            countriesTags: nil,
            lastUsed: nil
        )
    }
}

// MARK: - Errors

public enum FatSecretError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)
    case noCredentials

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
        case .noCredentials:
            return "FatSecret credentials not configured. Add ClientID and ClientSecret to fatsecret.plist"
        }
    }
}

