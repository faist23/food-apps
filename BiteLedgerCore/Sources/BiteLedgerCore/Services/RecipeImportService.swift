//
//  RecipeImportService.swift
//  BiteLedger
//
//  Fetches a recipe URL, extracts Schema.org JSON-LD markup, and uses Claude to
//  parse raw ingredient strings into structured (quantity, unit, searchTerm) data.
//
//  Degrades gracefully when claude.plist is missing: Schema.org parsing still runs
//  and a regex-based fallback parses ingredients without the Claude API.
//

import Foundation

// MARK: - Public Result Types

/// Per-serving nutrition scraped directly from the recipe website's Schema.org markup.
/// All values are per serving as declared by the recipe author.
public struct RecipeNutrition: Codable {
    public let calories: Double      // kcal
    public let protein: Double       // g
    public let carbs: Double         // g
    public let fat: Double           // g
    public let fiber: Double?        // g
    public let sugar: Double?        // g
    public let saturatedFat: Double? // g
    public let sodium: Double?       // mg
    public let cholesterol: Double?  // mg
    public let potassium: Double?    // mg
    public let calcium: Double?      // mg
    public let iron: Double?         // mg
    public let vitaminA: Double?     // mcg
    public let vitaminC: Double?     // mg
}

public struct RecipeImportResult {
    public let name: String
    public let servingsYield: Double
    public let sourceURL: String
    public let directions: [String]
    public let parsedIngredients: [ParsedIngredient]
    /// Non-nil when the recipe website included Schema.org NutritionInformation.
    public let nutrition: RecipeNutrition?

    public struct ParsedIngredient: Identifiable {
        public let id: UUID = UUID()
        public let rawString: String
        public let quantity: Double
        public let unit: String       // normalised: "cup", "tbsp", "oz", "lb", "piece", etc.
        public let searchTerm: String // core food name, stripped of prep notes
    }
}

// MARK: - Errors

public enum RecipeImportError: Error, LocalizedError {
    case invalidURL
    case fetchFailed(String)
    case noRecipeFound
    case noIngredients

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "That doesn't look like a valid URL. Make sure it starts with https://"
        case .fetchFailed(let msg):
            return "Couldn't load the page: \(msg)"
        case .noRecipeFound:
            return "No recipe data found on this page. The site may not use standard recipe markup (Schema.org)."
        case .noIngredients:
            return "The recipe was found but had no ingredients listed."
        }
    }
}

// MARK: - Service

public struct RecipeImportService {

    private let apiKey: String?
    private let model    = "claude-haiku-4-5-20251001"
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    public init(apiKey: String? = nil) {
        self.apiKey = apiKey
    }

    // MARK: - Factory

    /// Loads the API key from claude.plist. Returns a service with nil apiKey if the
    /// plist is missing or unconfigured — ingredient parsing then falls back to regex.
    public static func fromPlist() -> RecipeImportService {
        guard let path = Bundle.main.path(forResource: "claude", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: String],
              let key = dict["APIKey"], !key.hasPrefix("YOUR_")
        else {
            print("⚠️ RecipeImportService: claude.plist not found or APIKey not set — using regex fallback")
            return RecipeImportService(apiKey: nil)
        }
        print("✅ RecipeImportService: API key loaded (\(key.prefix(10))…)")
        return RecipeImportService(apiKey: key)
    }

    // MARK: - Main Entry Point

    public func importRecipe(from urlString: String) async throws -> RecipeImportResult {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { throw RecipeImportError.invalidURL }

        let html  = try await fetchHTML(from: url)
        let raw   = try extractSchemaOrgRecipe(from: html)
        let ingredients = await parseIngredients(raw.ingredientStrings)

        return RecipeImportResult(
            name:               raw.name,
            servingsYield:      raw.servingsYield,
            sourceURL:          trimmed,
            directions:         raw.directions,
            parsedIngredients:  ingredients,
            nutrition:          raw.nutrition
        )
    }

    // MARK: - Fetch

    private func fetchHTML(from url: URL) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw RecipeImportError.fetchFailed("HTTP \(code)")
            }
            // Try UTF-8 first; fall back to ISO-8859-1 for older sites
            if let html = String(data: data, encoding: .utf8) { return html }
            if let html = String(data: data, encoding: .isoLatin1) { return html }
            throw RecipeImportError.fetchFailed("Could not decode page content")
        } catch let e as RecipeImportError {
            throw e
        } catch {
            throw RecipeImportError.fetchFailed(error.localizedDescription)
        }
    }

    // MARK: - Schema.org Parsing

    private struct RawRecipeData {
        public let name: String
        public let servingsYield: Double
        public let ingredientStrings: [String]
        public let directions: [String]
        public let nutrition: RecipeNutrition?
    }

    private func extractSchemaOrgRecipe(from html: String) throws -> RawRecipeData {
        let blocks = extractJSONLDBlocks(from: html)
        guard let recipe = findRecipeObject(in: blocks) else {
            throw RecipeImportError.noRecipeFound
        }

        let name       = (recipe["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Imported Recipe"
        let yield      = parseYield(recipe["recipeYield"])
        let directions = parseInstructions(recipe["recipeInstructions"])
        let rawIngredients = parseIngredientStrings(recipe["recipeIngredient"])
        let nutrition  = parseSchemaOrgNutrition(recipe["nutrition"])

        return RawRecipeData(
            name:              name,
            servingsYield:     yield,
            ingredientStrings: rawIngredients,
            directions:        directions,
            nutrition:         nutrition
        )
    }

    /// Finds all <script type="application/ld+json"> blocks and parses each as JSON.
    private func extractJSONLDBlocks(from html: String) -> [Any] {
        let pattern = #"<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>([\s\S]*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns      = html as NSString
        let range   = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: html, range: range)

        return matches.compactMap { match -> Any? in
            guard match.numberOfRanges >= 2 else { return nil }
            let captureRange = match.range(at: 1)
            guard captureRange.location != NSNotFound,
                  let swiftRange = Range(captureRange, in: html) else { return nil }
            let jsonString = String(html[swiftRange])
            guard let data = jsonString.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        }
    }

    /// Finds the first object with @type = "Recipe" across direct objects, arrays, and @graph.
    private func findRecipeObject(in blocks: [Any]) -> [String: Any]? {
        for block in blocks {
            if let obj = block as? [String: Any] {
                if isRecipeType(obj) { return obj }
                if let graph = obj["@graph"] as? [[String: Any]],
                   let found = graph.first(where: { isRecipeType($0) }) { return found }
            } else if let arr = block as? [[String: Any]] {
                if let found = arr.first(where: { isRecipeType($0) }) { return found }
            }
        }
        return nil
    }

    private func isRecipeType(_ obj: [String: Any]) -> Bool {
        if let t = obj["@type"] as? String  { return t == "Recipe" }
        if let t = obj["@type"] as? [String] { return t.contains("Recipe") }
        return false
    }

    /// Parses a Schema.org NutritionInformation object into a RecipeNutrition value.
    /// Values are strings like "320 calories", "25 g", "800 mg" — the leading number is extracted.
    private func parseSchemaOrgNutrition(_ value: Any?) -> RecipeNutrition? {
        guard let obj = value as? [String: Any] else { return nil }

        func num(_ key: String) -> Double? {
            let v = obj[key]
            if let s = v as? String {
                let trimmed = s.trimmingCharacters(in: .whitespaces)
                return trimmed.components(separatedBy: .whitespaces).first.flatMap { Double($0) }
            }
            if let d = v as? Double { return d }
            if let i = v as? Int    { return Double(i) }
            return nil
        }

        guard let calories = num("calories"), calories > 0 else { return nil }

        print("✅ RecipeImportService: Found Schema.org nutrition — \(Int(calories)) kcal/serving")
        return RecipeNutrition(
            calories:     calories,
            protein:      num("proteinContent")       ?? 0,
            carbs:        num("carbohydrateContent")  ?? 0,
            fat:          num("fatContent")           ?? 0,
            fiber:        num("fiberContent"),
            sugar:        num("sugarContent"),
            saturatedFat: num("saturatedFatContent"),
            sodium:       num("sodiumContent"),
            cholesterol:  num("cholesterolContent"),
            potassium:    num("potassiumContent"),
            calcium:      num("calciumContent"),
            iron:         num("ironContent"),
            vitaminA:     num("vitaminAContent"),
            vitaminC:     num("vitaminCContent")
        )
    }

    private func parseYield(_ value: Any?) -> Double {
        guard let value else { return 4.0 }
        if let n = value as? Double { return max(1, n) }
        if let n = value as? Int    { return Double(max(1, n)) }
        let str: String
        if      let s = value as? String                               { str = s }
        else if let a = value as? [Any], let f = a.first as? String   { str = f }
        else { return 4.0 }
        // Extract leading number from e.g. "6 servings" or "Makes 4"
        let digits = str.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return Double(digits).flatMap { $0 > 0 ? $0 : nil } ?? 4.0
    }

    private func parseInstructions(_ value: Any?) -> [String] {
        guard let value else { return [] }

        func extractText(from step: [String: Any]) -> [String] {
            let type = step["@type"] as? String ?? ""
            if type == "HowToSection", let items = step["itemListElement"] as? [[String: Any]] {
                return items.compactMap { $0["text"] as? String ?? $0["name"] as? String }
            }
            if let text = step["text"] as? String { return [text] }
            if let name = step["name"] as? String { return [name] }
            return []
        }

        let raw: [String]
        if      let steps   = value as? [[String: Any]] { raw = steps.flatMap { extractText(from: $0) } }
        else if let strings = value as? [String]        { raw = strings }
        else if let single  = value as? String          { raw = single.components(separatedBy: "\n") }
        else                                            { return [] }

        return raw
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            // Strip HTML tags from some sites that embed <p> inside text fields
            .map { stripHTMLTags($0) }
            .filter { !$0.isEmpty }
    }

    private func parseIngredientStrings(_ value: Any?) -> [String] {
        guard let value else { return [] }
        if let arr    = value as? [String] { return arr.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
        if let single = value as? String   { return [single] }
        return []
    }

    private func stripHTMLTags(_ string: String) -> String {
        string.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
              .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Ingredient Parsing

    private func parseIngredients(_ strings: [String]) async -> [RecipeImportResult.ParsedIngredient] {
        guard !strings.isEmpty else { return [] }

        // Try Claude first
        if let apiKey, !apiKey.isEmpty,
           let claudeResults = await parseWithClaude(strings) {
            return claudeResults
        }

        // Regex fallback
        return strings.map { raw in
            let (qty, unit, term) = fallbackParse(raw)
            return RecipeImportResult.ParsedIngredient(
                rawString: raw, quantity: qty, unit: unit, searchTerm: term
            )
        }
    }

    // MARK: Claude Ingredient Parsing

    private func parseWithClaude(_ strings: [String]) async -> [RecipeImportResult.ParsedIngredient]? {
        guard let apiKey else { return nil }

        var prompt = """
        Parse each recipe ingredient into a quantity, unit, and core food name.

        Rules:
        - Convert Unicode fractions: ½=0.5, ¼=0.25, ¾=0.75, ⅓=0.333, ⅔=0.667, ⅛=0.125
        - Convert mixed numbers: "1½" → 1.5, "2 1/4" → 2.25
        - For ranges like "1-2": use the smaller number
        - Strip preparation notes: diced, chopped, minced, cooked, optional, room temperature, etc.
        - Simplify to a generic searchable name: "Barilla penne pasta" → "penne pasta"
        - Use "piece" as unit for count-based items with no unit: "3 eggs" → unit="piece"
        - For "N (X oz) item" format, total quantity = N×X, unit = oz: "8 (4 ounce) chicken cutlets" → quantity=32, unit="oz", searchTerm="chicken breast"
        - Known units: cup, tbsp, tsp, oz, lb, g, kg, ml, l, piece, slice, can, jar, package, bunch, clove, sprig, stalk, head

        Respond ONLY with a JSON array, one object per ingredient in order:
        [{"i":1,"quantity":1.0,"unit":"lb","searchTerm":"chicken breast"},...]

        Ingredients:
        """
        for (i, s) in strings.enumerated() {
            prompt += "\n\(i + 1). \"\(s)\""
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": [["role": "user", "content": prompt]]
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody   = bodyData
        request.setValue("application/json",    forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey,                forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01",          forHTTPHeaderField: "anthropic-version")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200
        else {
            print("⚠️ RecipeImportService: Claude call failed, using regex fallback")
            return nil
        }

        return parseClaudeResponse(data: data, originals: strings)
    }

    private func parseClaudeResponse(data: Data, originals: [String]) -> [RecipeImportResult.ParsedIngredient]? {
        guard let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text    = content.first?["text"] as? String,
              let start   = text.firstIndex(of: "["),
              let end     = text.lastIndex(of: "]")
        else { return nil }

        let slice = String(text[start...end])
        guard let arrayData = slice.data(using: .utf8),
              let picks = try? JSONSerialization.jsonObject(with: arrayData) as? [[String: Any]]
        else { return nil }

        // Build a result for every original string, using Claude's data where available
        var byIndex: [Int: RecipeImportResult.ParsedIngredient] = [:]

        for pick in picks {
            guard let i          = pick["i"] as? Int, i >= 1, i <= originals.count else { continue }
            let qty              = (pick["quantity"] as? Double) ?? 1.0
            let unit             = (pick["unit"] as? String) ?? "piece"
            let term             = (pick["searchTerm"] as? String) ?? originals[i - 1]
            byIndex[i] = RecipeImportResult.ParsedIngredient(
                rawString: originals[i - 1],
                quantity:  max(0.1, qty),
                unit:      unit,
                searchTerm: term.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return originals.enumerated().map { (offset, raw) in
            byIndex[offset + 1] ?? {
                let (qty, unit, term) = fallbackParse(raw)
                return RecipeImportResult.ParsedIngredient(rawString: raw, quantity: qty, unit: unit, searchTerm: term)
            }()
        }
    }

    // MARK: Regex Fallback

    private func fallbackParse(_ string: String) -> (quantity: Double, unit: String, searchTerm: String) {
        var s = string

        // Before stripping parens: detect "N (X unit)" weight-per-piece pattern.
        // e.g. "8 (4 ounce) chicken cutlets" → "32 oz chicken cutlets"
        // The parenthetical tells us each piece weighs X units, so total = N × X.
        let weightModPattern = #"^(\d+(?:\.\d+)?)\s+\((\d+(?:\.\d+)?)\s*(oz|ounce|ounces|lb|pound|pounds|g|gram|grams)\)"#
        if let regex = try? NSRegularExpression(pattern: weightModPattern, options: .caseInsensitive) {
            let ns = s as NSString
            if let m = regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
               m.numberOfRanges == 4,
               let r1 = Range(m.range(at: 1), in: s),
               let r2 = Range(m.range(at: 2), in: s),
               let r3 = Range(m.range(at: 3), in: s),
               let count = Double(s[r1]),
               let weight = Double(s[r2]) {
                let unitWord = String(s[r3]).lowercased()
                let unitNorm: [String: String] = [
                    "oz": "oz", "ounce": "oz", "ounces": "oz",
                    "lb": "lb", "pound": "lb", "pounds": "lb",
                    "g": "g",   "gram":  "g",  "grams":  "g"
                ]
                let unit = unitNorm[unitWord] ?? unitWord
                let total = count * weight
                let totalStr = total == total.rounded()
                    ? "\(Int(total)) \(unit) "
                    : "\(String(format: "%.2g", total)) \(unit) "
                s = regex.stringByReplacingMatches(in: s, range: m.range, withTemplate: totalStr)
            }
        }

        // Remove parenthetical notes — repeat to handle nested ((…)) constructs
        for _ in 0..<3 {
            s = s.replacingOccurrences(of: #"\([^()]*\)"#, with: " ", options: .regularExpression)
        }
        // Strip everything after the first comma: "pesto, I used Classico" → "pesto"
        if let commaRange = s.range(of: ",") { s = String(s[..<commaRange.lowerBound]) }
        // Normalise Unicode fractions
        let fractions: [(String, String)] = [
            ("½","0.5"),("¼","0.25"),("¾","0.75"),("⅓","0.333"),
            ("⅔","0.667"),("⅛","0.125"),("⅜","0.375"),("⅝","0.625"),("⅞","0.875")
        ]
        for (f, r) in fractions { s = s.replacingOccurrences(of: f, with: r + " ") }

        let parts = s.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else {
            return (1.0, "piece", string.trimmingCharacters(in: .whitespaces))
        }

        // Parse leading number
        var quantity  = 1.0
        var nextIndex = 0
        if let n = parseNumber(parts[0]) {
            quantity  = n
            nextIndex = 1
            // Check for a following fraction like "1 1/2"
            if nextIndex < parts.count, let frac = parseFraction(parts[nextIndex]) {
                quantity  += frac
                nextIndex += 1
            }
        }

        // Match unit word
        let unitMap: [String: String] = [
            "cup":"cup","cups":"cup",
            "tbsp":"tbsp","tablespoon":"tbsp","tablespoons":"tbsp",
            "tsp":"tsp","teaspoon":"tsp","teaspoons":"tsp",
            "oz":"oz","ounce":"oz","ounces":"oz","fl":"oz",
            "lb":"lb","lbs":"lb","pound":"lb","pounds":"lb",
            "g":"g","gram":"g","grams":"g",
            "kg":"kg","kilogram":"kg","kilograms":"kg",
            "ml":"ml","l":"l","liter":"l","liters":"l",
            "can":"can","cans":"can","jar":"jar","jars":"jar",
            "package":"package","packages":"package","pkg":"package",
            "bunch":"bunch","bunches":"bunch","clove":"clove","cloves":"clove",
            "sprig":"sprig","sprigs":"sprig","stalk":"stalk","stalks":"stalk",
            "head":"head","heads":"head","slice":"slice","slices":"slice",
            "sheet":"sheet","sheets":"sheet","strip":"strip","strips":"strip"
        ]

        var unit      = "piece"
        var termStart = nextIndex

        if nextIndex < parts.count,
           let mapped = unitMap[parts[nextIndex].lowercased().trimmingCharacters(in: .punctuationCharacters)] {
            unit      = mapped
            termStart = nextIndex + 1
        }

        // Rest of words form the search term; strip common prep notes
        let prepNotes: Set<String> = [
            "diced","chopped","minced","sliced","cooked","coarsely","finely","fresh","frozen",
            "dried","ground","optional","shredded","grated","melted","softened","peeled",
            "pitted","halved","quartered","crushed","torn","roughly","lightly","well","rinsed",
            "drained","packed","sifted","beaten","room","temperature","separated","skinless",
            "boneless","lean","large","medium","small","extra",
            // flavour/processing adjectives
            "salted","unsalted","jarred","canned","whole","organic","plain","wild","light",
            "reduced","nonfat","fat-free","low-fat","rotisserie","thick","thin","raw",
            "grass-fed","free-range","roasted","toasted","blanched","soaked","dry","wet"
        ]
        let termParts = Array(parts[termStart...])
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty && !prepNotes.contains($0.lowercased()) }

        let rawTermParts = Array(parts[termStart...])
        let searchTerm = termParts.isEmpty
            ? rawTermParts.joined(separator: " ")
            : termParts.joined(separator: " ")

        return (quantity, unit, searchTerm.isEmpty ? string : searchTerm)
    }

    private func parseNumber(_ s: String) -> Double? {
        if let n = Double(s) { return n }
        return parseFraction(s)
    }

    private func parseFraction(_ s: String) -> Double? {
        let parts = s.split(separator: "/")
        guard parts.count == 2,
              let num = Double(parts[0]),
              let den = Double(parts[1]), den != 0
        else { return nil }
        return num / den
    }
}
