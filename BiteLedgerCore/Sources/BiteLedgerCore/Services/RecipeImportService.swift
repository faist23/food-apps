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
    /// Source/author extracted from the scanned card (e.g. "Aunt Debbie"). Nil for URL imports.
    public let detectedSource: String?

    // MARK: - Rich Metadata (URL imports only; nil/empty for OCR)
    public let prepMinutes: Int?
    public let cookMinutes: Int?
    public let totalMinutes: Int?
    /// Remote URL for the recipe hero image.
    public let imageURL: String?
    /// Intro / description paragraph from the recipe website.
    public let recipeDescription: String?
    public let recipeCategory: String?
    public let recipeCuisine: String?
    public let author: String?
    public let ratingValue: Double?
    public let ratingCount: Int?
    public let keywords: [String]
    public let dietTags: [String]

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

    // MARK: - Main Entry Points

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
            nutrition:          raw.nutrition,
            detectedSource:     nil,
            prepMinutes:        raw.prepMinutes,
            cookMinutes:        raw.cookMinutes,
            totalMinutes:       raw.totalMinutes,
            imageURL:           raw.imageURL,
            recipeDescription:  raw.recipeDescription,
            recipeCategory:     raw.recipeCategory,
            recipeCuisine:      raw.recipeCuisine,
            author:             raw.author,
            ratingValue:        raw.ratingValue,
            ratingCount:        raw.ratingCount,
            keywords:           raw.keywords,
            dietTags:           raw.dietTags
        )
    }

    /// Import a recipe from raw OCR text lines (e.g. from a Vision framework scan of a cookbook).
    /// Uses Claude to structure the text if an API key is available; falls back to heuristics.
    public func importFromOCRLines(_ lines: [String]) async throws -> RecipeImportResult {
        guard !lines.isEmpty else { throw RecipeImportError.noRecipeFound }

        let preprocessed = preprocessOCRLines(lines)

        // Try Claude to structure the raw OCR text
        if let apiKey, !apiKey.isEmpty,
           let structured = await structureOCRWithClaude(preprocessed) {
            let ingredients = await parseIngredients(structured.ingredientStrings)
            return RecipeImportResult(
                name:              structured.name,
                servingsYield:     structured.servingsYield,
                sourceURL:         "ocr://scan",
                directions:        structured.directions,
                parsedIngredients: ingredients,
                nutrition:         nil,
                detectedSource:    structured.detectedSource,
                prepMinutes: nil, cookMinutes: nil, totalMinutes: nil,
                imageURL: nil, recipeDescription: nil,
                recipeCategory: nil, recipeCuisine: nil, author: nil,
                ratingValue: nil, ratingCount: nil, keywords: [], dietTags: []
            )
        }

        // Heuristic fallback
        let structured = heuristicParseOCR(preprocessed)
        guard !structured.ingredientStrings.isEmpty else { throw RecipeImportError.noIngredients }
        let ingredients = await parseIngredients(structured.ingredientStrings)
        return RecipeImportResult(
            name:              structured.name.isEmpty ? "Scanned Recipe" : structured.name,
            servingsYield:     structured.servingsYield,
            sourceURL:         "ocr://scan",
            directions:        structured.directions,
            parsedIngredients: ingredients,
            nutrition:         nil,
            detectedSource:    nil,
            prepMinutes: nil, cookMinutes: nil, totalMinutes: nil,
            imageURL: nil, recipeDescription: nil,
            recipeCategory: nil, recipeCuisine: nil, author: nil,
            ratingValue: nil, ratingCount: nil, keywords: [], dietTags: []
        )
    }

    /// Parses a single raw ingredient string into structured fields using the same
    /// logic as the full import pipeline. Use this to re-parse after the user edits
    /// an ingredient's raw text on the review screen.
    public func parseIngredientText(_ raw: String) -> RecipeImportResult.ParsedIngredient {
        let (qty, unit, term) = fallbackParse(raw)
        return RecipeImportResult.ParsedIngredient(
            rawString: raw,
            quantity:  max(0.1, qty),
            unit:      unit,
            searchTerm: term.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    // MARK: - OCR Preprocessing

    /// Fixes clear OCR character misreads before sending lines to Claude or the heuristic parser.
    /// Only corrects unambiguous character substitutions — does not merge, reorder, or restructure lines.
    /// Normalises and filters raw OCR lines before displaying them to the user and before sending
    /// to Claude. Public so callers (e.g. OCRRecipeImportView) can show the cleaned text.
    ///
    /// Two passes:
    /// 1. Character-level fixes (parenthesised quantities, unit abbreviations, OCR misreads)
    /// 2. Noise filtering — drops lines that can't plausibly be recipe content (decorative
    ///    card artwork, borders, background patterns, and single stray characters are common
    ///    sources of garbage in handwritten-recipe-card scans)
    public func preprocessOCRLines(_ lines: [String]) -> [String] {
        // Pass 1: character-level normalisation
        let normalised: [String] = lines.compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            var s = trimmed
            // Parenthesised leading quantities: "(2)" → "2", "(4)" → "4"
            s = s.replacingOccurrences(of: #"^\((\d+)\)\s*"#, with: "$1 ", options: .regularExpression)
            // Unit abbreviation expansion — case-sensitive: standalone T=tbsp, t=tsp
            s = s.replacingOccurrences(of: #"\bT\b"#, with: "tbsp", options: .regularExpression)
            s = s.replacingOccurrences(of: #"\bt\b"#, with: "tsp",  options: .regularExpression)
            // OCR character misreads for the letter 't' in tbsp/tsp
            s = s.replacingOccurrences(of: #"\+\s*bsp\b"#, with: "tbsp", options: [.regularExpression, .caseInsensitive])
            s = s.replacingOccurrences(of: #"\+\s*sp\b"#,  with: "tsp",  options: [.regularExpression, .caseInsensitive])
            s = s.replacingOccurrences(of: #"\blbsp\b"#,   with: "tbsp", options: [.regularExpression, .caseInsensitive])
            s = s.replacingOccurrences(of: #"\btbps\b"#,   with: "tbsp", options: [.regularExpression, .caseInsensitive])
            s = s.replacingOccurrences(of: #"\btpsp\b"#,   with: "tsp",  options: [.regularExpression, .caseInsensitive])
            return s.trimmingCharacters(in: .whitespaces)
        }

        // Pass 2: noise filtering
        return normalised.filter { isPlausibleRecipeLine($0) }
    }

    /// Returns false for lines that are almost certainly OCR noise rather than recipe content.
    /// Designed to drop stray characters from card artwork, borders, and decorative backgrounds
    /// while preserving all genuine recipe text.
    private func isPlausibleRecipeLine(_ line: String) -> Bool {
        // Must have at least 2 characters
        guard line.count >= 2 else { return false }

        let letters    = line.filter { $0.isLetter }
        let alphanum   = line.filter { $0.isLetter || $0.isNumber }
        let totalChars = line.count

        // Must contain at least one letter
        guard !letters.isEmpty else { return false }

        // Alphanumeric density must be ≥ 40 % — catches lines that are mostly symbols/punctuation
        let density = Double(alphanum.count) / Double(totalChars)
        guard density >= 0.40 else { return false }

        // Must have at least one "real word" (3+ consecutive letters), OR start with a quantity.
        // This catches lines like "a b c" (all 1-letter tokens) from decorative lettering.
        let words = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let hasRealWord = words.contains { $0.filter { $0.isLetter }.count >= 3 }
        if !hasRealWord {
            let firstChar = line.unicodeScalars.first!
            let quantityStarters = CharacterSet.decimalDigits
                .union(CharacterSet(charactersIn: "½¼¾⅓⅔⅛⅜⅝⅞/"))
            guard quantityStarters.contains(firstChar) else { return false }
        }

        return true
    }

    // MARK: - OCR Structuring (Claude)

    private func structureOCRWithClaude(_ lines: [String]) async -> RawRecipeData? {
        guard let apiKey else { return nil }

        let joined = lines.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let prompt = """
        The following numbered lines were extracted via OCR from a physical recipe card or cookbook page.
        Structure the recipe following every rule below exactly.

        CRITICAL — NO HALLUCINATION:
        You MUST only include ingredients and steps that are explicitly written in the OCR lines below.
        Do NOT invent, infer, assume, or add anything that is not present in the text.
        If something is unclear, use the OCR text as-is rather than guessing.

        LAYOUT (recipe cards are often multi-column):
        - Many cards have a LEFT column for quantity+unit ("2 cups", "½ cup", "1 tbsp") and a RIGHT
          column for the ingredient name ("sugar", "milk", "cocoa"). Quantity and name may appear on
          SEPARATE consecutive lines — combine them: line 6="2 cups", line 7="sugar" → "2 cups sugar".
        - Some cards have a THIRD column of directions/notes mixed in — exclude direction text from
          ingredient strings; it belongs in instructions only.
        - A quantity-only line always belongs to the ingredient on the very next non-blank line.

        PARENTHESIZED QUANTITIES:
        - Numbers in parentheses like (2), (4), (3) at the start of an ingredient line are the
          quantity, NOT step numbers. "(2) 12.5oz canned chicken" = 2 cans of 12.5oz canned chicken.
          Write as: "2 12.5oz canned chicken". Preserve "canned", "jarred", etc. exactly.

        SUB-SECTIONS:
        - If the card has a sub-section for toppings (e.g. "For top:", "For frosting:", "For sauce:"),
          include those ingredients in the main ingredient list. Prefix each with the section label:
          e.g. "For top: 2 tbsp melted butter", "For top: 1/3 bag crushed croutons".

        INGREDIENTS:
        - Format each as: quantity unit name (e.g. "2 cups sugar", "1 tsp vanilla", "2 12.5oz canned chicken").
        - PREFIX every ingredient with "[N]" where N = OCR line number of the ingredient name line.
          Example: "[7] 2 cups sugar". Do NOT omit this prefix — it is required for ordering.

        SOURCE:
        - Look for author/source phrases: "from the kitchen of", "recipe by", "submitted by", etc.
        - Return just the name (e.g. "Pat Faist"), not the phrase. Use null if none found.

        SERVINGS:
        - Extract from: "serves X", "yield X", "yields X", "makes X", "makes X-Y" (use smaller),
          "makes X dozen" → X × 12. Default to 4 if not stated.

        TIMING (prepMinutes, cookMinutes, totalMinutes):
        - ONLY extract times that are explicitly written on the card.
        - "Prep: 15 min" → prepMinutes=15. "Bake 350° for 30 min" → cookMinutes=30.
        - "1 hour" → 60, "1½ hours" → 90, "45 minutes" → 45.
        - Return null for any time not explicitly stated. Do NOT guess or invent times.

        DESCRIPTION:
        - If there is a short intro note or tagline before the ingredients ("A family favorite!",
          "Quick weeknight dinner"), return it as "description".
        - Return null if no such note exists. Do NOT invent one.

        CATEGORY:
        - Infer from context. Use exactly one of: "Dessert", "Bread", "Soup", "Salad",
          "Appetizer", "Side Dish", "Main Dish", "Breakfast", "Drink", "Snack".
        - A chocolate cake recipe → "Dessert". Chicken casserole → "Main Dish".
        - Return null only if genuinely ambiguous.

        INSTRUCTIONS:
        - Copy steps as written. Do not reorder or combine steps.
        - Do not invent steps not in the OCR text.

        Ignore page numbers, print credits, card artwork, blank lines.

        Respond ONLY with valid JSON, no commentary:
        {"name":"...","servings":4,"source":null,"prepMinutes":null,"cookMinutes":null,"totalMinutes":null,"description":null,"category":null,"ingredients":["[N] quantity unit name"],"instructions":["step 1","step 2"]}

        OCR Lines:
        \(joined)
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": [["role": "user", "content": prompt]]
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody   = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey,             forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01",       forHTTPHeaderField: "anthropic-version")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200
        else {
            print("⚠️ RecipeImportService: OCR Claude call failed, using heuristic fallback")
            return nil
        }

        guard let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text    = content.first?["text"] as? String,
              let start   = text.firstIndex(of: "{"),
              let end     = text.lastIndex(of: "}")
        else { return nil }

        let slice = String(text[start...end])
        guard let objData = slice.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: objData) as? [String: Any]
        else { return nil }

        let name           = (obj["name"] as? String) ?? "Scanned Recipe"
        let servings       = (obj["servings"] as? Double) ?? Double((obj["servings"] as? Int) ?? 4)
        let rawIngredients = (obj["ingredients"] as? [String]) ?? []
        let instructions   = (obj["instructions"] as? [String]) ?? []
        let detectedSource = obj["source"] as? String
        // New fields — only present when Claude finds them in the card text
        let prepMins   = obj["prepMinutes"]  as? Int
        let cookMins   = obj["cookMinutes"]  as? Int
        let totalMins  = obj["totalMinutes"] as? Int
        let desc       = (obj["description"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let category   = (obj["category"]    as? String).flatMap { $0.isEmpty ? nil : $0 }

        guard !rawIngredients.isEmpty else { return nil }

        // Parse "[N] ingredient text" prefixes, sort by N to guarantee original order,
        // then strip the prefix before storing.
        let lineTagPattern = #"^\[(\d+)\]\s*"#
        let tagged: [(lineNum: Int, text: String)] = rawIngredients.compactMap { raw in
            if let range = raw.range(of: lineTagPattern, options: .regularExpression),
               let numRange = raw.range(of: #"\d+"#, options: .regularExpression, range: range) {
                let num = Int(raw[numRange]) ?? Int.max
                let text = String(raw[raw.index(range.upperBound, offsetBy: 0)...])
                return (num, text)
            }
            // Claude omitted the tag — keep as-is, append to end
            return (Int.max, raw)
        }
        let ingredients = tagged.sorted { $0.lineNum < $1.lineNum }.map { $0.text }

        print("✅ RecipeImportService: OCR structured via Claude — \(name), \(ingredients.count) ingredients, source: \(detectedSource ?? "none"), prepMins: \(prepMins.map(String.init) ?? "nil"), category: \(category ?? "nil")")
        return RawRecipeData(
            name:              name,
            servingsYield:     max(1, servings),
            ingredientStrings: ingredients,
            directions:        instructions,
            nutrition:         nil,
            detectedSource:    detectedSource,
            prepMinutes:       prepMins,
            cookMinutes:       cookMins,
            totalMinutes:      totalMins,
            imageURL:          nil,   // set later from scanned photo, not from text
            recipeDescription: desc,
            recipeCategory:    category,
            recipeCuisine:     nil,
            author:            nil,
            ratingValue:       nil,
            ratingCount:       nil,
            keywords:          [],
            dietTags:          []
        )
    }

    // MARK: - OCR Structuring (Heuristic Fallback)

    private func heuristicParseOCR(_ lines: [String]) -> RawRecipeData {
        enum Section { case header, ingredients, instructions, other }

        let ingredientHeaders: Set<String> = [
            "ingredients", "ingredient list", "you'll need", "you will need",
            "what you need", "for the recipe", "for the filling", "for the sauce",
            "for the dough", "for the topping"
        ]
        let instructionHeaders: Set<String> = [
            "instructions", "directions", "method", "steps", "preparation",
            "how to make", "how to prepare", "to make", "procedure"
        ]

        var name          = ""
        var servings      = 4.0      // default 4 when nothing is mentioned
        var ingredients   = [String]()
        var instructions  = [String]()
        var section       = Section.header
        var nameFound     = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let lower = trimmed.lowercased()

            // Detect section transitions
            if ingredientHeaders.contains(where: { lower == $0 || lower.hasPrefix($0 + ":") }) {
                section = .ingredients
                continue
            }
            if instructionHeaders.contains(where: { lower == $0 || lower.hasPrefix($0 + ":") }) {
                section = .instructions
                continue
            }

            // Servings / yield line — check anywhere in the text (often at the bottom)
            if lower.contains("serves") || lower.contains("servings") ||
               lower.contains("yield") || lower.contains("makes") {
                if let n = extractFirstNumber(from: trimmed) {
                    // "makes 3 dozen" or "makes 3 or 4 dozen" → multiply by 12
                    servings = lower.contains("dozen") ? n * 12 : n
                }
                // Don't skip the line — it might still be part of a section
                continue
            }

            switch section {
            case .header:
                // Recipe name = first substantial non-numeric line
                if !nameFound, trimmed.count > 2,
                   trimmed.rangeOfCharacter(from: .letters) != nil {
                    name = trimmed
                    nameFound = true
                }
            case .ingredients:
                ingredients.append(trimmed)
            case .instructions:
                instructions.append(trimmed)
            case .other:
                break
            }
        }

        // Second pass: if no ingredients were found (no explicit header),
        // identify ingredient-like lines by pattern (quantity + unit or leading fraction/number).
        if ingredients.isEmpty {
            let unitWords: Set<String> = [
                "cup", "cups", "tablespoon", "tablespoons", "tbsp", "tsp",
                "teaspoon", "teaspoons", "oz", "ounce", "ounces", "lb", "lbs",
                "pound", "pounds", "gram", "grams", "g", "kg", "ml", "liter",
                "liters", "quart", "quarts", "pint", "pints", "stick", "sticks",
                "bunch", "bunches", "clove", "cloves", "slice", "slices",
                "can", "cans", "package", "packages", "pkg", "jar", "jars",
                "bag", "bags", "pinch", "dash", "handful", "head", "heads",
                "T", "t"
            ]
            // Fraction/number start: "1", "1/2", "½", "¼", "¾", "2½"
            let leadingQuantityPattern = #"^[\d¼½¾⅓⅔⅛⅜⅝⅞]"#
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed.count > 2 else { continue }
                let words = trimmed.components(separatedBy: .whitespaces)
                let firstWord = words.first ?? ""
                let secondWord = words.count > 1 ? words[1] : ""
                let hasLeadingNumber = trimmed.range(of: leadingQuantityPattern, options: .regularExpression) != nil
                let hasUnitSecond = unitWords.contains(secondWord.lowercased())
                let hasUnitFirst = unitWords.contains(firstWord)
                // Include lines that look like "qty unit ingredient" or just start with a unit
                if (hasLeadingNumber && hasUnitSecond) || hasUnitFirst {
                    // Skip if this looks like a title or serving note
                    let lower = trimmed.lowercased()
                    guard !lower.contains("serves") && !lower.contains("servings") &&
                          !lower.contains("makes") && !lower.contains("yield") else { continue }
                    ingredients.append(trimmed)
                }
            }
        }

        return RawRecipeData(
            name:              nameFound ? name : "Scanned Recipe",
            servingsYield:     servings,
            ingredientStrings: ingredients,
            directions:        instructions,
            nutrition:         nil,
            detectedSource:    nil,
            prepMinutes: nil, cookMinutes: nil, totalMinutes: nil,
            imageURL: nil, recipeDescription: nil,
            recipeCategory: nil, recipeCuisine: nil, author: nil,
            ratingValue: nil, ratingCount: nil, keywords: [], dietTags: []
        )
    }

    private func extractFirstNumber(from text: String) -> Double? {
        let pattern = #"\d+\.?\d*"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return Double(String(text[range]))
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
        let name: String
        let servingsYield: Double
        let ingredientStrings: [String]
        let directions: [String]
        let nutrition: RecipeNutrition?
        let detectedSource: String?
        // Rich metadata — populated for URL imports, nil/empty for OCR/heuristic
        let prepMinutes: Int?
        let cookMinutes: Int?
        let totalMinutes: Int?
        let imageURL: String?
        let recipeDescription: String?
        let recipeCategory: String?
        let recipeCuisine: String?
        let author: String?
        let ratingValue: Double?
        let ratingCount: Int?
        let keywords: [String]
        let dietTags: [String]
    }

    private func extractSchemaOrgRecipe(from html: String) throws -> RawRecipeData {
        let blocks = extractJSONLDBlocks(from: html)
        guard let recipe = findRecipeObject(in: blocks) else {
            throw RecipeImportError.noRecipeFound
        }

        let name           = (recipe["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Imported Recipe"
        let yield          = parseYield(recipe["recipeYield"])
        let directions     = parseInstructions(recipe["recipeInstructions"])
        let rawIngredients = parseIngredientStrings(recipe["recipeIngredient"])
        let nutrition      = parseSchemaOrgNutrition(recipe["nutrition"])

        // Rich metadata
        let prepMins   = parseISODuration(recipe["prepTime"])
        let cookMins   = parseISODuration(recipe["cookTime"])
        let totalMins  = parseISODuration(recipe["totalTime"])
        let imageURL   = parseImageURL(recipe["image"])
        let desc       = (recipe["description"] as? String).flatMap { s -> String? in
            let t = stripHTMLTags(s).trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        let category   = parseTextOrArray(recipe["recipeCategory"])
        let cuisine    = parseTextOrArray(recipe["recipeCuisine"])
        let author     = parseAuthorName(recipe["author"])
        let (rating, ratingCount) = parseAggregateRating(recipe["aggregateRating"])
        let keywords   = parseKeywordsList(recipe["keywords"])
        let dietTags   = parseDietTags(recipe["suitableForDiet"])

        return RawRecipeData(
            name:              name,
            servingsYield:     yield,
            ingredientStrings: rawIngredients,
            directions:        directions,
            nutrition:         nutrition,
            detectedSource:    nil,
            prepMinutes:       prepMins,
            cookMinutes:       cookMins,
            totalMinutes:      totalMins,
            imageURL:          imageURL,
            recipeDescription: desc,
            recipeCategory:    category,
            recipeCuisine:     cuisine,
            author:            author,
            ratingValue:       rating,
            ratingCount:       ratingCount,
            keywords:          keywords,
            dietTags:          dietTags
        )
    }

    // MARK: - Rich Metadata Parsers

    /// Parses ISO 8601 duration strings to total minutes. "PT1H30M" → 90, "PT15M" → 15.
    private func parseISODuration(_ value: Any?) -> Int? {
        guard let s = value as? String, s.hasPrefix("P") else { return nil }
        var minutes = 0
        // Hours: match digits before "H"
        if let range = s.range(of: #"(\d+)H"#, options: .regularExpression),
           let digits = s[range].range(of: #"\d+"#, options: .regularExpression) {
            minutes += (Int(s[range][digits]) ?? 0) * 60
        }
        // Minutes: match digits before "M" — exclude month "P1M" (no T prefix context needed
        // since recipe durations are always in hours/minutes, not months)
        if let range = s.range(of: #"(\d+)M"#, options: .regularExpression),
           let digits = s[range].range(of: #"\d+"#, options: .regularExpression) {
            minutes += Int(s[range][digits]) ?? 0
        }
        return minutes > 0 ? minutes : nil
    }

    /// Extracts the first usable image URL from Schema.org `image` (string, array, or ImageObject).
    private func parseImageURL(_ value: Any?) -> String? {
        func fromString(_ s: String) -> String? { s.hasPrefix("http") ? s : nil }
        func fromObject(_ obj: [String: Any]) -> String? {
            (obj["url"] as? String).flatMap(fromString)
        }
        if let s   = value as? String              { return fromString(s) }
        if let obj = value as? [String: Any]       { return fromObject(obj) }
        if let arr = value as? [Any] {
            for item in arr {
                if let s   = item as? String        { if let u = fromString(s)   { return u } }
                if let obj = item as? [String: Any] { if let u = fromObject(obj) { return u } }
            }
        }
        return nil
    }

    /// Returns the first value as a trimmed string when the field is a String or [String].
    private func parseTextOrArray(_ value: Any?) -> String? {
        if let s = value as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        if let arr = value as? [String] { return arr.first }
        return nil
    }

    /// Extracts the author name from a string, Person object, or array of either.
    private func parseAuthorName(_ value: Any?) -> String? {
        func fromObj(_ obj: [String: Any]) -> String? { obj["name"] as? String }
        if let s   = value as? String              { return s.isEmpty ? nil : s }
        if let obj = value as? [String: Any]       { return fromObj(obj) }
        if let arr = value as? [Any] {
            for item in arr {
                if let s   = item as? String        { if !s.isEmpty   { return s } }
                if let obj = item as? [String: Any] { if let n = fromObj(obj) { return n } }
            }
        }
        return nil
    }

    /// Parses `aggregateRating` → (ratingValue, ratingCount).
    private func parseAggregateRating(_ value: Any?) -> (Double?, Int?) {
        guard let obj = value as? [String: Any] else { return (nil, nil) }
        let rv: Double? = {
            if let d = obj["ratingValue"] as? Double { return d }
            if let i = obj["ratingValue"] as? Int    { return Double(i) }
            if let s = obj["ratingValue"] as? String { return Double(s) }
            return nil
        }()
        let rc: Int? = {
            for key in ["reviewCount", "ratingCount"] {
                if let i = obj[key] as? Int    { return i }
                if let s = obj[key] as? String { return Int(s) }
            }
            return nil
        }()
        return (rv, rc)
    }

    /// Parses the `keywords` field (comma-separated string or array).
    private func parseKeywordsList(_ value: Any?) -> [String] {
        if let s = value as? String {
            return s.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
        }
        if let arr = value as? [String] { return arr.filter { !$0.isEmpty } }
        return []
    }

    /// Maps Schema.org `suitableForDiet` URLs/strings to human-readable labels.
    private func parseDietTags(_ value: Any?) -> [String] {
        let dietMap: [String: String] = [
            "VeganDiet": "Vegan", "VegetarianDiet": "Vegetarian",
            "GlutenFreeDiet": "Gluten-Free", "DiabeticDiet": "Diabetic",
            "HalalDiet": "Halal", "KosherDiet": "Kosher",
            "LowCalorieDiet": "Low-Calorie", "LowFatDiet": "Low-Fat",
            "LowLactoseDiet": "Low-Lactose", "LowSaltDiet": "Low-Salt"
        ]
        func map(_ raw: String) -> String {
            let key = raw.components(separatedBy: "/").last ?? raw
            return dietMap[key] ?? key
        }
        if let s   = value as? String  { return [map(s)] }
        if let arr = value as? [String] { return arr.map(map) }
        return []
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
        - Case-sensitive single-letter units: uppercase "T" = tablespoon (tbsp), lowercase "t" = teaspoon (tsp)
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

        if nextIndex < parts.count {
            let rawUnit = parts[nextIndex].trimmingCharacters(in: .punctuationCharacters)
            // Case-sensitive single-letter cooking abbreviations must be checked BEFORE lowercasing
            // because T (tablespoon) and t (teaspoon) are otherwise identical after lowercasing.
            if rawUnit == "T" {
                unit = "tbsp"; termStart = nextIndex + 1
            } else if rawUnit == "t" {
                unit = "tsp"; termStart = nextIndex + 1
            } else if let mapped = unitMap[rawUnit.lowercased()] {
                unit = mapped; termStart = nextIndex + 1
            } else {
                // Handle fused quantity+unit tokens like "12.5oz", "8oz", "16oz"
                // e.g. "2 12.5oz canned chicken" — skip the size descriptor, keep the food name
                let fusedPattern = #"^\d+\.?\d*(oz|g|ml|lb|lbs|kg|cup|tbsp|tsp)$"#
                if rawUnit.range(of: fusedPattern, options: [.regularExpression, .caseInsensitive]) != nil {
                    // The fused token is a package-size descriptor — skip it, don't use as unit
                    termStart = nextIndex + 1
                    // Unit stays as "piece" since the leading qty (e.g. 2 cans) has no explicit unit
                    unit = "can"   // most common case for fused-size ingredients like "2 12.5oz canned chicken"
                }
            }
        }

        // Rest of words form the search term; strip common prep notes
        let prepNotes: Set<String> = [
            "diced","chopped","minced","sliced","cooked","coarsely","finely","fresh","frozen",
            "dried","ground","optional","shredded","grated","melted","softened","peeled",
            "pitted","halved","quartered","crushed","torn","roughly","lightly","well","rinsed",
            "drained","packed","sifted","beaten","room","temperature","separated","skinless",
            "boneless","lean","large","medium","small","extra",
            // flavour/processing adjectives
            "salted","unsalted","jarred","whole","organic","plain","wild","light",
            // NOTE: "canned" intentionally excluded — "canned chicken" is a distinct food, not a prep note
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

    // MARK: - Local Image Storage

    /// Saves raw JPEG data for a scanned recipe image to the app's Documents directory.
    /// Returns a `file://` URL string, or nil on failure.
    /// The caller is responsible for deleting the file when the recipe is deleted.
    public static func saveImageDataLocally(_ jpegData: Data) -> String? {
        let filename = "recipe-\(UUID().uuidString).jpg"
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = dir.appendingPathComponent(filename)
        do {
            try jpegData.write(to: fileURL, options: .atomic)
            return fileURL.absoluteString
        } catch {
            print("⚠️ RecipeImportService: failed to save scanned image — \(error)")
            return nil
        }
    }

    /// Deletes a locally-saved recipe image. Safe to call with remote `https://` URLs (no-op).
    public static func deleteLocalImage(urlString: String) {
        guard urlString.hasPrefix("file://"),
              let url = URL(string: urlString) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
