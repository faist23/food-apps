import Foundation

// MARK: - Unified Food Search Service

/// Combines multiple food databases (USDA, FatSecret, and OpenFoodFacts) for comprehensive search results
@MainActor
public class UnifiedFoodSearchService {
    public static let shared = UnifiedFoodSearchService()
    
    private let usdaService = USDAFoodDataService.shared
    private let fatSecretService = FatSecretService.shared
    private let openFoodFactsService = OpenFoodFactsService.shared
    
    private init() {}
    
    /// Search all databases and merge results
    /// - USDA results appear first (better for whole foods)
    /// - FatSecret results appear second (better for restaurant foods)
    /// - OpenFoodFacts results appear third (better for packaged products)
    public func searchAllDatabases(query: String) async throws -> [ProductInfo] {
        // Search all databases in parallel
        async let usdaResults = searchUSDA(query: query)
        async let fatSecretResults = searchFatSecret(query: query)
        async let openFoodResults = searchOpenFoodFacts(query: query)

        var allResults: [ProductInfo] = []

        // USDA first (better for fruits, vegetables, whole foods)
        do {
            let usda = try await usdaResults
            print("✅ USDA returned \(usda.count) results")
            allResults.append(contentsOf: usda)
        } catch {
            print("⚠️ USDA search failed: \(error.localizedDescription)")
        }

        // FatSecret second (better for restaurant foods)
        do {
            let fatSecret = try await fatSecretResults
            print("✅ FatSecret returned \(fatSecret.count) results")
            allResults.append(contentsOf: fatSecret)
        } catch {
            print("⚠️ FatSecret search failed: \(error.localizedDescription)")
        }

        // OpenFoodFacts third (better for packaged products)
        do {
            let openFood = try await openFoodResults
            print("✅ OpenFoodFacts returned \(openFood.count) results")
            allResults.append(contentsOf: openFood)
        } catch {
            print("⚠️ OpenFoodFacts search failed: \(error.localizedDescription)")
        }

        // Filter out foods with only 100g data and no serving information
        // Bad data is worse than no data - users don't eat "100g of Big Mac"
        let validResults = allResults.filter { product in
            // USDA foods always have portions - keep them
            if product.code.hasPrefix("usda_") {
                return true
            }
            
            // FatSecret foods always have serving info - keep them
            if product.code.hasPrefix("fatsecret_") {
                return true
            }
            
            // OpenFoodFacts: Reject if no serving size info
            if product.servingSize == nil || product.servingSize?.isEmpty == true {
                print("❌ Rejected \\(product.displayName) - no serving size data")
                return false
            }
            
            // Reject if serving size is just "100g" or "100 g" (useless)
            let serving = product.servingSize?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""
            if serving == "100g" || serving == "100 g" || serving == "100.0g" || serving == "100.0 g" {
                print("❌ Rejected \\(product.displayName) - only 100g data (serving: \\(serving))")
                return false
            }
            
            return true
        }
        
        print("📊 Filtered \\(allResults.count) results down to \\(validResults.count) with valid serving info")

        // Only throw if every database call failed and we have nothing at all.
        // If the serving-size filter removed everything (common for basic cooking
        // ingredients like "salt"), fall back to the unfiltered results so the
        // user can still find and assign the food.
        if allResults.isEmpty {
            throw UnifiedSearchError.noResults
        }
        let finalResults = validResults.isEmpty ? allResults : validResults

        // Sort by relevance - products with search terms in name or brand rank higher
        let sortedResults = finalResults.sorted { product1, product2 in
            let name1 = product1.productName?.lowercased() ?? ""
            let name2 = product2.productName?.lowercased() ?? ""
            let brand1 = product1.brands?.lowercased() ?? ""
            let brand2 = product2.brands?.lowercased() ?? ""
            let searchLower = query.lowercased()

            // Exact match in brand ranks highest (for restaurant searches like "Chipotle")
            let exactBrandMatch1 = brand1 == searchLower
            let exactBrandMatch2 = brand2 == searchLower
            if exactBrandMatch1 != exactBrandMatch2 { return exactBrandMatch1 }
            
            // Exact match in name ranks next
            let exactMatch1 = name1 == searchLower
            let exactMatch2 = name2 == searchLower
            if exactMatch1 != exactMatch2 { return exactMatch1 }

            // Brand starts with search ranks next
            let brandStartsWith1 = brand1.hasPrefix(searchLower)
            let brandStartsWith2 = brand2.hasPrefix(searchLower)
            if brandStartsWith1 != brandStartsWith2 { return brandStartsWith1 }
            
            // Name starts with search ranks next
            let startsWith1 = name1.hasPrefix(searchLower)
            let startsWith2 = name2.hasPrefix(searchLower)
            if startsWith1 != startsWith2 { return startsWith1 }

            // Brand contains search as whole phrase ranks next
            let brandContains1 = brand1.contains(searchLower)
            let brandContains2 = brand2.contains(searchLower)
            if brandContains1 != brandContains2 { return brandContains1 }
            
            // Name contains search as whole phrase ranks next
            let containsPhrase1 = name1.contains(searchLower)
            let containsPhrase2 = name2.contains(searchLower)
            if containsPhrase1 != containsPhrase2 { return containsPhrase1 }

            // Otherwise keep original order (USDA first, then FatSecret, then OpenFoodFacts)
            return false
        }

        return sortedResults
    }
    
    /// Search only USDA database (best for whole foods)
    private func searchUSDA(query: String) async throws -> [ProductInfo] {
        let usdaFoods = try await usdaService.searchFoods(query: query)
        let products = usdaFoods.compactMap { $0.toProductInfo() }

        // Filter to ensure ALL search words are present
        let searchWords = query.lowercased().split(separator: " ").map { String($0) }
        let filtered = products.filter { product in
            let name = product.productName?.lowercased() ?? ""
            let brand = product.brands?.lowercased() ?? ""
            let combinedText = "\(name) \(brand)"

            // Check if ALL search words are present
            return searchWords.allSatisfy { word in
                combinedText.contains(word)
            }
        }

        return filtered
    }
    
    /// Search only OpenFoodFacts database (best for packaged products)
    /// Filters results to prefer US English language products
    private func searchOpenFoodFacts(query: String) async throws -> [ProductInfo] {
        let results = try await openFoodFactsService.searchProducts(query: query)

        // Filter results for US/English products with ALL search terms
        let filtered = results.filter { product in
            let name = product.productName?.lowercased() ?? ""
            let brand = product.brands?.lowercased() ?? ""
            let combinedText = "\(name) \(brand)"

            // Split search query into individual words
            let searchWords = query.lowercased().split(separator: " ").map { String($0) }

            // Check if ALL search words are present in name or brand
            let hasAllSearchTerms = searchWords.allSatisfy { word in
                combinedText.contains(word)
            }

            // Filter out products with non-Latin characters (non-English)
            let nameHasNonLatin = name.range(of: "[^\\x00-\\x7F]", options: .regularExpression) != nil
            let brandHasNonLatin = brand.range(of: "[^\\x00-\\x7F]", options: .regularExpression) != nil

            // Must have all search terms and be in English
            return hasAllSearchTerms && !nameHasNonLatin && !brandHasNonLatin
        }

        print("🌐 Filtered OpenFoodFacts from \(results.count) to \(filtered.count) US/English results")
        return filtered
    }
    
    /// Search only FatSecret database (best for restaurant foods)
    private func searchFatSecret(query: String) async throws -> [ProductInfo] {
        let fatSecretFoods = try await fatSecretService.searchFoods(query: query)
        let products = fatSecretFoods.compactMap { $0.toProductInfo() }
        
        // Filter to ensure ALL search words are present
        let searchWords = query.lowercased().split(separator: " ").map { String($0) }
        let filtered = products.filter { product in
            let name = product.productName?.lowercased() ?? ""
            let brand = product.brands?.lowercased() ?? ""
            let combinedText = "\(name) \(brand)"
            
            // Check if ALL search words are present
            return searchWords.allSatisfy { word in
                combinedText.contains(word)
            }
        }
        
        return filtered
    }
    
    /// Determine which database a product code belongs to
    public func getDatabaseType(for code: String) -> DatabaseType {
        if code.hasPrefix("usda_") {
            return .usda
        } else if code.hasPrefix("fatsecret_") {
            return .fatSecret
        }
        return .openFoodFacts
    }
    
    /// Get detailed information for a product from the appropriate database
    public func getProductDetails(code: String) async throws -> ProductInfo {
        let dbType = getDatabaseType(for: code)
        
        switch dbType {
        case .usda:
            // Extract FDC ID from code (format: "usda_12345")
            let fdcIdString = code.replacingOccurrences(of: "usda_", with: "")
            guard let fdcId = Int(fdcIdString) else {
                throw UnifiedSearchError.invalidProductCode
            }
            let detail = try await usdaService.getFoodDetails(fdcId: fdcId)
            return detail.toProductInfo()
            
        case .fatSecret:
            // Extract food ID from code (format: "fatsecret_12345")
            let foodIdString = code.replacingOccurrences(of: "fatsecret_", with: "")
            let detail = try await fatSecretService.getFoodDetails(foodId: foodIdString)
            return detail.toProductInfo() ?? ProductInfo(
                code: code,
                productName: "Unknown Food",
                brands: nil,
                imageUrl: nil,
                nutriments: nil,
                servingSize: nil,
                quantity: nil,
                portions: nil,
                countriesTags: nil,
                lastUsed: nil
            )
            
        case .openFoodFacts:
            return try await openFoodFactsService.fetchProduct(barcode: code)
        }
    }
}

// MARK: - Database Type

public enum DatabaseType {
    case usda
    case fatSecret
    case openFoodFacts
    
    public var displayName: String {
        switch self {
        case .usda:
            return "USDA"
        case .fatSecret:
            return "FatSecret"
        case .openFoodFacts:
            return "Open Food Facts"
        }
    }
}

// MARK: - Errors

public enum UnifiedSearchError: LocalizedError {
    case noResults
    case invalidProductCode
    
    public var errorDescription: String? {
        switch self {
        case .noResults:
            return "No results found in any database"
        case .invalidProductCode:
            return "Invalid product code format"
        }
    }
}
