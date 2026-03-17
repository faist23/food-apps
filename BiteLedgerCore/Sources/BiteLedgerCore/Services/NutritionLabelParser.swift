import Foundation

/// Parsed nutrition data from a label scan
public struct NutritionData {
    public var servingSize: String?
    public var servingSizeGrams: Double? // Extracted grams/mL from serving size
    public var servingsPerContainer: String?
    public var calories: Double?
    public var totalFat: Double?
    public var saturatedFat: Double?
    public var transFat: Double?
    public var cholesterol: Double?
    public var sodium: Double?
    public var totalCarbs: Double?
    public var fiber: Double?
    public var sugars: Double?
    public var addedSugars: Double?
    public var protein: Double?
    public var vitaminD: Double?
    public var calcium: Double?
    public var iron: Double?
    public var potassium: Double?
    public var vitaminA: Double?
    public var vitaminC: Double?
    public var vitaminE: Double?
    public var vitaminK: Double?
    public var vitaminB6: Double?
    public var vitaminB12: Double?
    public var folate: Double?
    public var choline: Double?
    public var magnesium: Double?
    public var zinc: Double?
    public var caffeine: Double?
    public var monounsaturatedFat: Double?
    public var polyunsaturatedFat: Double?

    public init() {}
}

/// Parser for extracting nutrition information from OCR text
public struct NutritionLabelParser {
    
    /// Parse an array of text lines from OCR into nutrition data
    public static func parse(_ lines: [String]) -> NutritionData? {
        var data = NutritionData()
        var foundAnyData = false
        
        print("🔍 Parsing nutrition label text (\(lines.count) lines):")
        for (index, line) in lines.enumerated() {
            print("Line \(index): \"\(line)\"")
        }
        print("---")
        
        // Join all lines for easier processing
        let fullText = lines.joined(separator: " ").lowercased()
        
        // Check if this looks like a nutrition label
        guard fullText.contains("nutrition") || fullText.contains("calories") else {
            print("❌ Doesn't appear to be a nutrition label")
            return nil
        }
        
        // Try to find nutrient-value pairs across non-adjacent lines
        // This handles table layouts where labels and values are in different columns
        if let result = parseTableFormat(lines) {
            print("✅ Successfully parsed table format")
            return result
        }
        
        // Try to find calories in the full text first (handles multi-line cases)
        if let calories = extractCaloriesFromFullText(lines) {
            data.calories = calories
            foundAnyData = true
            print("✅ Found calories from full text: \(calories)")
        }
        
        // Parse each line
        for (index, line) in lines.enumerated() {
            let cleaned = line.lowercased().trimmingCharacters(in: .whitespaces)
            
            // Serving size - may span multiple lines
            if cleaned.contains("serving size") {
                // Combine current line with next 2 lines to catch split text
                var combinedText = line
                if index + 1 < lines.count {
                    combinedText += " " + lines[index + 1]
                }
                if index + 2 < lines.count {
                    combinedText += " " + lines[index + 2]
                }
                
                let (description, grams) = extractServingSizeWithWeight(from: combinedText)
                data.servingSize = description
                data.servingSizeGrams = grams
                foundAnyData = true
            }
            
            // Servings per container
            if cleaned.contains("servings per container") {
                data.servingsPerContainer = extractNumber(from: line)
                foundAnyData = true
            }
            
            // Skip calorie extraction from individual lines since we already did it from full text
            // (This prevents false positives from line-by-line parsing)
            
            // Check specific fat types BEFORE general "total fat" to prevent mismatches
            // Saturated Fat (check first)
            if let satFat = extractNutrient(from: line, patterns: ["saturated fat", "sat. fat", "sat fat"]) {
                data.saturatedFat = satFat
                foundAnyData = true
                print("✅ Found saturated fat: \(satFat)g")
            }
            // Trans Fat (check second)
            else if let transFat = extractNutrient(from: line, patterns: ["trans fat"]) {
                data.transFat = transFat
                foundAnyData = true
                print("✅ Found trans fat: \(transFat)g")
            }
            // Total Fat (check last, only if not saturated or trans)
            else if let fat = extractNutrient(from: line, patterns: ["total fat"]) {
                data.totalFat = fat
                foundAnyData = true
                print("✅ Found total fat: \(fat)g")
            }
            
            // Cholesterol
            if let cholesterol = extractNutrient(from: line, patterns: ["cholesterol"]) {
                data.cholesterol = cholesterol
                foundAnyData = true
            }
            
            // Sodium
            if let sodium = extractNutrient(from: line, patterns: ["sodium"]) {
                data.sodium = sodium
                foundAnyData = true
                print("✅ Found sodium: \(sodium)mg")
            }
            
            // Total Carbohydrates
            if let carbs = extractNutrient(from: line, patterns: ["total carbohydrate", "total carb", "carbohydrate"]) {
                data.totalCarbs = carbs
                foundAnyData = true
                print("✅ Found carbs: \(carbs)g")
            }
            
            // Dietary Fiber
            if let fiber = extractNutrient(from: line, patterns: ["dietary fiber", "fiber"]) {
                data.fiber = fiber
                foundAnyData = true
            }
            
            // Check "Added Sugars" BEFORE "Total Sugars" to prevent mismatches
            // Added Sugars (check first)
            if let addedSugars = extractNutrient(from: line, patterns: ["added sugars", "incl. added sugars", "includes"]) {
                data.addedSugars = addedSugars
                foundAnyData = true
            }
            // Total Sugars (check second, only if not added sugars)
            else if let sugars = extractNutrient(from: line, patterns: ["total sugars"]) {
                data.sugars = sugars
                foundAnyData = true
            }
            
            // Protein
            if let protein = extractNutrient(from: line, patterns: ["protein"]) {
                data.protein = protein
                foundAnyData = true
                print("✅ Found protein: \(protein)g")
            }
            
            // Vitamin D
            if let vitaminD = extractNutrient(from: line, patterns: ["vitamin d"]) {
                data.vitaminD = vitaminD
                foundAnyData = true
            }
            
            // Calcium
            if let calcium = extractNutrient(from: line, patterns: ["calcium"]) {
                data.calcium = calcium
                foundAnyData = true
            }
            
            // Iron
            if let iron = extractNutrient(from: line, patterns: ["iron"]) {
                data.iron = iron
                foundAnyData = true
            }
            
            // Potassium
            if let potassium = extractNutrient(from: line, patterns: ["potassium"]) {
                data.potassium = potassium
                foundAnyData = true
            }
            
            // Vitamin A
            if let vitaminA = extractNutrient(from: line, patterns: ["vitamin a"]) {
                data.vitaminA = vitaminA
                foundAnyData = true
            }
            
            // Vitamin C
            if let vitaminC = extractNutrient(from: line, patterns: ["vitamin c"]) {
                data.vitaminC = vitaminC
                foundAnyData = true
            }
            
            // Vitamin E
            if let vitaminE = extractNutrient(from: line, patterns: ["vitamin e"]) {
                data.vitaminE = vitaminE
                foundAnyData = true
            }
            
            // Vitamin K
            if let vitaminK = extractNutrient(from: line, patterns: ["vitamin k"]) {
                data.vitaminK = vitaminK
                foundAnyData = true
            }
            
            // Vitamin B6
            if let vitaminB6 = extractNutrient(from: line, patterns: ["vitamin b6", "vitamin b-6", "pyridoxine"]) {
                data.vitaminB6 = vitaminB6
                foundAnyData = true
            }
            
            // Vitamin B12
            if let vitaminB12 = extractNutrient(from: line, patterns: ["vitamin b12", "vitamin b-12", "cobalamin"]) {
                data.vitaminB12 = vitaminB12
                foundAnyData = true
            }
            
            // Folate
            if let folate = extractNutrient(from: line, patterns: ["folate", "folic acid"]) {
                data.folate = folate
                foundAnyData = true
            }
            
            // Choline
            if let choline = extractNutrient(from: line, patterns: ["choline"]) {
                data.choline = choline
                foundAnyData = true
            }
            
            // Magnesium
            if let magnesium = extractNutrient(from: line, patterns: ["magnesium"]) {
                data.magnesium = magnesium
                foundAnyData = true
            }
            
            // Zinc
            if let zinc = extractNutrient(from: line, patterns: ["zinc"]) {
                data.zinc = zinc
                foundAnyData = true
            }
            
            // Caffeine
            if let caffeine = extractNutrient(from: line, patterns: ["caffeine"]) {
                data.caffeine = caffeine
                foundAnyData = true
            }
            
            // Monounsaturated Fat
            if let monoFat = extractNutrient(from: line, patterns: ["monounsaturated fat", "monounsaturated", "mono fat"]) {
                data.monounsaturatedFat = monoFat
                foundAnyData = true
            }
            
            // Polyunsaturated Fat
            if let polyFat = extractNutrient(from: line, patterns: ["polyunsaturated fat", "polyunsaturated", "poly fat"]) {
                data.polyunsaturatedFat = polyFat
                foundAnyData = true
            }
        }
        
        return foundAnyData ? data : nil
    }
    
    // MARK: - Helper Methods
    
    private static func extractServingSizeWithWeight(from text: String) -> (description: String?, grams: Double?) {
        // Look for patterns like "Serving size 2/3 cup (55g)" or "8 fl oz. (240ml)"
        let pattern = #"serving size\s*(.+?)(?=\n\n|\z)"#  // Capture until double newline or end
        guard let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return (nil, nil)
        }
        
        var extracted = String(text[match])
            .replacingOccurrences(of: "serving size", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if extracted.isEmpty {
            return (nil, nil)
        }
        
        // Try to extract a better description than just "1 serving"
        // Look for actual measurements: oz, fl oz, cup, tbsp, mL, etc.
        let measurementPatterns = [
            #"(\d+\.?\d*\s*fl\.?\s*oz\.?(?:\s*\(\d+\.?\d*\s*m[lL]\))?)"#,  // 8 fl oz (240mL)
            #"(\d+\.?\d*\s*oz\.?(?:\s*\(\d+\.?\d*\s*g\))?)"#,              // 8 oz (227g)
            #"(\d+\.?\d*\s*cup[s]?(?:\s*\(\d+\.?\d*\s*[mg]L?\))?)"#,       // 1 cup (240mL)
            #"(\d+\.?\d*\s*tbsp\.?(?:\s*\(\d+\.?\d*\s*[mg]L?\))?)"#,       // 2 tbsp (30mL)
            #"(\d+\.?\d*\s*tsp\.?(?:\s*\(\d+\.?\d*\s*[mg]L?\))?)"#,        // 1 tsp (5mL)
            #"(\d+\.?\d*\s*m[lL](?:\s*\(\d+\.?\d*\s*fl\.?\s*oz\.?\))?)"#,  // 240mL (8 fl oz)
            #"(\d+\.?\d*\s*g(?:\s*\(\d+\.?\d*\s*oz\.?\))?)"#                // 240g (8 oz)
        ]
        
        for pattern in measurementPatterns {
            if let measurementMatch = extracted.range(of: pattern, options: .regularExpression) {
                let measurement = String(extracted[measurementMatch])
                extracted = measurement
                break
            }
        }
        
        // Try to extract grams or mL from parentheses or standalone units
        var gramsValue: Double? = nil
        
        let weightPatterns = [
            #"\((\d+\.?\d*)\s*m[lL]\)"#,  // (240mL) or (240ml)
            #"\((\d+\.?\d*)\s*g\)"#,      // (240g)
            #"(\d+\.?\d*)\s*m[lL]\b"#,    // 240mL (not in parentheses)
            #"(\d+\.?\d*)\s*g\b"#          // 240g (not in parentheses)
        ]
        
        for pattern in weightPatterns {
            if let weightMatch = extracted.range(of: pattern, options: .regularExpression) {
                let matchText = String(extracted[weightMatch])
                // Extract just the number
                if let numberMatch = matchText.range(of: #"\d+\.?\d*"#, options: .regularExpression) {
                    let numberStr = String(matchText[numberMatch])
                    gramsValue = Double(numberStr)
                    break
                }
            }
        }
        
        print("📏 Extracted serving size: '\(extracted)' with \(gramsValue ?? 0)g")
        
        return (extracted, gramsValue)
    }
    
    private static func extractNumber(from text: String) -> String? {
        // Extract first number from text
        let pattern = #"\d+"#
        if let match = text.range(of: pattern, options: .regularExpression) {
            return String(text[match])
        }
        return nil
    }
    
    private static func extractCaloriesFromFullText(_ lines: [String]) -> Double? {
        // Look for "Calories" line and check surrounding lines for the number
        // Prioritize lines that appear to be from the actual nutrition facts table
        for (index, line) in lines.enumerated() {
            let cleaned = line.lowercased().trimmingCharacters(in: .whitespaces)
            
            // Found a line containing "calories"
            if cleaned.contains("calories") || cleaned.contains("calorie") {
                print("📍 Found calories keyword at line \(index): \"\(line)\"")
                
                // Skip marketing/promotional text (these patterns indicate it's not the nutrition facts)
                if cleaned.contains("fewer calories") || 
                   cleaned.contains("reduced") ||
                   cleaned.contains("than") ||
                   cleaned.contains("%") ||
                   cleaned.contains("percent") {
                    print("⚠️ Skipping marketing text at line \(index)")
                    continue
                }
                
                // Look for "Amount per serving" nearby (indicates this is the nutrition facts section)
                let isNearAmountPerServing = (index > 0 && lines[index - 1].lowercased().contains("amount per serving")) ||
                                             (index > 1 && lines[index - 2].lowercased().contains("amount per serving"))
                
                // If this is just "Calories" on its own line (FDA format), check next few lines
                if cleaned == "calories" || cleaned == "calorie" {
                    // Search within next 25 lines for a standalone number (calorie value)
                    for offset in 1...min(25, lines.count - index - 1) {
                        let checkLine = lines[index + offset]
                        
                        // Check if this line is just a number (calorie value)
                        if let numberMatch = checkLine.range(of: #"^\s*\d+\s*$"#, options: .regularExpression) {
                            let numberStr = String(checkLine[numberMatch]).trimmingCharacters(in: .whitespaces)
                            if let value = Double(numberStr), value > 0 && value < 1000 {
                                print("✅ Found calories \(offset) line(s) after 'Calories' keyword: \(value)")
                                return value
                            }
                        }
                    }
                    
                    // If we didn't find it in the forward search, try looking backward
                    print("⚠️ Calorie number not found in forward search, trying backward...")
                    for backIndex in stride(from: index - 1, through: max(0, index - 10), by: -1) {
                        let backLine = lines[backIndex].lowercased()
                        if backLine.contains("calorie") && backLine.contains("per") {
                            print("📍 Found potential calorie reference: '\(lines[backIndex])'")
                            let allMatches = lines[backIndex].matches(of: /\d+/)
                            let numbers = allMatches.map { Int($0.output) ?? 0 }
                            if let firstValid = numbers.first(where: { $0 > 0 && $0 < 1000 }) {
                                print("✅ Found calories from reference text: \(firstValid)")
                                return Double(firstValid)
                            }
                        }
                    }
                    
                    continue
                }
                
                // Strategy 1: Number on same line after "calories" (e.g., "Calories 230")
                // But only if it looks like nutrition facts format
                if isNearAmountPerServing || cleaned.starts(with: "calories") {
                    if let numberMatch = line.range(of: #"calories\s*(\d+)"#, options: [.regularExpression, .caseInsensitive]) {
                        let matchText = String(line[numberMatch])
                        if let numMatch = matchText.range(of: #"\d+"#, options: .regularExpression) {
                            let numberStr = String(matchText[numMatch])
                            if let value = Double(numberStr), value > 0 && value < 1000 {
                                print("✅ Found calories on same line: \(value)")
                                return value
                            }
                        }
                    }
                }
                
                // Strategy 2: Number on next line (common in FDA labels)
                if index + 1 < lines.count {
                    let nextLine = lines[index + 1]
                    print("📍 Checking next line: \"\(nextLine)\"")
                    // Only match if next line is JUST a number
                    if let numberMatch = nextLine.range(of: #"^\s*\d+\s*$"#, options: .regularExpression) {
                        let numberStr = String(nextLine[numberMatch]).trimmingCharacters(in: .whitespaces)
                        if let value = Double(numberStr), value > 0 && value < 1000 {
                            print("✅ Found calories on next line: \(value)")
                            return value
                        }
                    }
                }
            }
        }
        
        // Fallback: Look for "X calories per serving" pattern in marketing text
        // This catches cases like "5 CALORIES PER TWO PIECE SERVING"
        print("⚠️ Standard calorie detection failed, trying fallback patterns...")
        for (index, line) in lines.enumerated() {
            let cleaned = line.lowercased().trimmingCharacters(in: .whitespaces)
            
            // Pattern: "5 calories per serving" or "reduced from 8 to 5 calories"
            if cleaned.contains("calories per") || (cleaned.contains("to") && cleaned.contains("calories")) {
                print("📍 Found calorie reference at line \(index): \"\(line)\"")
                
                // Extract all numbers from the line
                let numbers = line.matches(of: /\d+/).map { Int($0.output) ?? 0 }
                print("📍 Numbers found in line: \(numbers)")
                
                // For "reduced from X to Y" pattern, take the last (newer) value
                // For "Y calories per serving", take the first reasonable value
                for number in numbers.reversed() {
                    if number > 0 && number < 1000 {
                        print("✅ Found calories from fallback pattern: \(number)")
                        return Double(number)
                    }
                }
            }
        }
        
        print("❌ Could not find calories value")
        return nil
    }
    
    private static func extractCalories(from text: String) -> Double? {
        let cleaned = text.lowercased().trimmingCharacters(in: .whitespaces)
        
        // Pattern: "Calories 230" or "230 Calories" or "Amount per serving\nCalories 230"
        if cleaned.contains("calories") {
            // Look for number near "calories"
            let patterns = [
                #"calories\s*(\d+)"#,
                #"(\d+)\s*calories"#,
                #"amount per serving\s*calories\s*(\d+)"#
            ]
            
            for pattern in patterns {
                if let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                    let matchText = String(text[match])
                    // Extract just the number
                    if let numberMatch = matchText.range(of: #"\d+"#, options: .regularExpression) {
                        let numberStr = String(matchText[numberMatch])
                        return Double(numberStr)
                    }
                }
            }
        }
        
        return nil
    }
    
    private static func extractNutrient(from text: String, patterns: [String]) -> Double? {
        let cleaned = text.lowercased().trimmingCharacters(in: .whitespaces)
        
        for pattern in patterns {
            if cleaned.contains(pattern) {
                // Look for number followed by g, mg, mcg, or µg
                let numberPatterns = [
                    #"(\d+\.?\d*)\s*g"#,      // "8g" or "8 g"
                    #"(\d+\.?\d*)\s*mg"#,     // "160mg"
                    #"(\d+\.?\d*)\s*mcg"#,    // "2mcg"
                    #"(\d+\.?\d*)\s*µg"#,     // "2µg"
                    #"(\d+\.?\d*)\s*(?=\s|$)"# // Just number
                ]
                
                for numPattern in numberPatterns {
                    if let match = text.range(of: numPattern, options: .regularExpression) {
                        let matchText = String(text[match])
                        // Extract just the number part
                        if let numberMatch = matchText.range(of: #"\d+\.?\d*"#, options: .regularExpression) {
                            let numberStr = String(matchText[numberMatch])
                            if let value = Double(numberStr) {
                                // Convert based on unit
                                if matchText.contains("mg") {
                                    return value // Keep as mg
                                } else if matchText.contains("mcg") || matchText.contains("µg") {
                                    return value // Keep as mcg/µg
                                } else {
                                    return value // Assume grams
                                }
                            }
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    /// Parse table format using proximity matching - finds closest value after each nutrient label
    private static func parseTableFormatProximity(lines: [String], nutrientIndices: [String: Int]) -> NutritionData? {
        var data = NutritionData()
        var foundAnyData = false
        
        // Build a map of all value lines
        var valueMap: [Int: (value: Double, unit: String)] = [:]
        for (index, line) in lines.enumerated() {
            let cleaned = line.trimmingCharacters(in: .whitespaces)
            if let match = cleaned.range(of: #"^(\d+(?:\.\d+)?)\s*(g|mg|mcg|µg|ug)?$"#, options: .regularExpression) {
                let matchText = String(cleaned[match])
                if let numMatch = matchText.range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression),
                   let value = Double(String(matchText[numMatch])) {
                    let unit = matchText.replacingOccurrences(of: #"\d+(?:\.\d+)?"#, with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespaces).lowercased()
                    valueMap[index] = (value: value, unit: unit)
                }
            }
        }
        
        print("🔍 Proximity matching: found \(valueMap.count) value lines")
        
        // For each nutrient, find the closest value after it (within 40 lines for fragmented OCR)
        var usedValueIndices = Set<Int>()
        var matchedCount = 0
        
        for (nutrient, labelIndex) in nutrientIndices.sorted(by: { $0.value < $1.value }) {
            // Find unused value closest to this nutrient label
            // For calories, allow unitless values; for others, prefer values with units
            let candidateValues = valueMap.filter { valueIndex, valueInfo in
                valueIndex > labelIndex && 
                valueIndex - labelIndex <= 40 &&
                !usedValueIndices.contains(valueIndex)
            }.sorted { $0.key < $1.key }
            
            // For non-calorie nutrients, prefer values with appropriate units
            var filteredCandidates = candidateValues
            if nutrient != "calories" {
                // Prefer values with units for non-calorie nutrients
                let withUnits = candidateValues.filter { !$0.value.unit.isEmpty }
                if !withUnits.isEmpty {
                    filteredCandidates = withUnits
                }
            }
            
            guard let (valueIndex, valueData) = filteredCandidates.first else {
                print("⚠️ No value found for \(nutrient) at line \(labelIndex)")
                continue
            }
            
            usedValueIndices.insert(valueIndex)
            
            switch nutrient {
            case "calories":
                data.calories = valueData.value
                foundAnyData = true
                matchedCount += 1
                print("✅ Matched Calories (\(labelIndex)): \(valueData.value) at line \(valueIndex)")
                
            case "totalFat":
                data.totalFat = valueData.value
                foundAnyData = true
                matchedCount += 1
                print("✅ Matched Total Fat (\(labelIndex)): \(valueData.value)\(valueData.unit) at line \(valueIndex)")
                
            case "saturatedFat":
                data.saturatedFat = valueData.value
                foundAnyData = true
                matchedCount += 1
                print("✅ Matched Saturated Fat (\(labelIndex)): \(valueData.value)\(valueData.unit) at line \(valueIndex)")
                
            case "transFat":
                data.transFat = valueData.value
                foundAnyData = true
                matchedCount += 1
                print("✅ Matched Trans Fat (\(labelIndex)): \(valueData.value)\(valueData.unit) at line \(valueIndex)")
                
            case "cholesterol":
                data.cholesterol = valueData.value
                foundAnyData = true
                matchedCount += 1
                print("✅ Matched Cholesterol (\(labelIndex)): \(valueData.value)\(valueData.unit) at line \(valueIndex)")
                
            case "sodium":
                data.sodium = valueData.value
                foundAnyData = true
                matchedCount += 1
                print("✅ Matched Sodium (\(labelIndex)): \(valueData.value)\(valueData.unit) at line \(valueIndex)")
                
            case "totalCarbs":
                data.totalCarbs = valueData.value
                foundAnyData = true
                matchedCount += 1
                print("✅ Matched Total Carbs (\(labelIndex)): \(valueData.value)\(valueData.unit) at line \(valueIndex)")
                
            case "fiber":
                data.fiber = valueData.value
                foundAnyData = true
                matchedCount += 1
                print("✅ Matched Fiber (\(labelIndex)): \(valueData.value)\(valueData.unit) at line \(valueIndex)")
                
            case "totalSugars":
                data.sugars = valueData.value
                foundAnyData = true
                matchedCount += 1
                print("✅ Matched Total Sugars (\(labelIndex)): \(valueData.value)\(valueData.unit) at line \(valueIndex)")
                
            case "protein":
                data.protein = valueData.value
                foundAnyData = true
                matchedCount += 1
                print("✅ Matched Protein (\(labelIndex)): \(valueData.value)\(valueData.unit) at line \(valueIndex)")
                
            case "vitaminD":
                data.vitaminD = valueData.value
                foundAnyData = true
                matchedCount += 1
                print("✅ Matched Vitamin D (\(labelIndex)): \(valueData.value)\(valueData.unit) at line \(valueIndex)")
                
            case "calcium":
                data.calcium = valueData.value
                foundAnyData = true
                matchedCount += 1
                print("✅ Matched Calcium (\(labelIndex)): \(valueData.value)\(valueData.unit) at line \(valueIndex)")
                
            case "iron":
                data.iron = valueData.value
                foundAnyData = true
                matchedCount += 1
                print("✅ Matched Iron (\(labelIndex)): \(valueData.value)\(valueData.unit) at line \(valueIndex)")
                
            case "potassium":
                data.potassium = valueData.value
                foundAnyData = true
                matchedCount += 1
                print("✅ Matched Potassium (\(labelIndex)): \(valueData.value)\(valueData.unit) at line \(valueIndex)")
                
            default:
                break
            }
        }
        
        // Only use proximity matching if we found a substantial number of nutrients
        // Otherwise fall back to sequence-based matching
        if matchedCount >= 8 {
            print("✅ Proximity matching succeeded with \(matchedCount) nutrients")
            return foundAnyData ? data : nil
        } else {
            print("⚠️ Proximity matching found only \(matchedCount) nutrients, falling back to sequence matching")
            return nil
        }
    }
    
    /// Parse table-format nutrition labels where labels and values are in separate columns
    private static func parseTableFormat(_ lines: [String]) -> NutritionData? {
        var data = NutritionData()
        var foundAnyData = false
        
        // Find all nutrient labels and their indices
        var nutrientIndices: [String: Int] = [:]
        for (index, line) in lines.enumerated() {
            let cleaned = line.lowercased().trimmingCharacters(in: .whitespaces)
            
            if cleaned == "calories" { nutrientIndices["calories"] = index }
            if cleaned.contains("total fat") || cleaned == "total fat" { nutrientIndices["totalFat"] = index }
            if cleaned.contains("saturated fat") || cleaned == "saturated fat" { nutrientIndices["saturatedFat"] = index }
            if cleaned.contains("trans fat") || cleaned == "trans fat" { nutrientIndices["transFat"] = index }
            if cleaned == "cholesterol" { nutrientIndices["cholesterol"] = index }
            if cleaned == "sodium" { nutrientIndices["sodium"] = index }
            if cleaned.contains("total carbohydrate") || cleaned == "total carbohydrate" { nutrientIndices["totalCarbs"] = index }
            if cleaned.contains("dietary fiber") || cleaned == "dietary fiber" { nutrientIndices["fiber"] = index }
            
            // For "total sugars", check if standalone "sugars" is part of "Added Sugars" sub-label
            if cleaned.contains("total sugars") || cleaned == "total sugars" {
                nutrientIndices["totalSugars"] = index
            } else if cleaned == "sugars" {
                // Check if previous line contains "added" or "incl" - if so, skip this as it's part of "Added Sugars"
                if index > 0 {
                    let prevLine = lines[index - 1].lowercased()
                    if prevLine.contains("added") || prevLine.contains("incl") {
                        // Skip - this is part of "Added Sugars" sub-label, not a standalone nutrient
                        print("⏭️ Skipping 'Sugars' at line \(index) - part of 'Added Sugars' compound label")
                        continue
                    }
                }
                // If not preceded by "added"/"incl", treat as Total Sugars
                nutrientIndices["totalSugars"] = index
            }
            
            if cleaned == "protein" { nutrientIndices["protein"] = index }
            if cleaned.contains("vitamin d") || cleaned == "vitamin d" { nutrientIndices["vitaminD"] = index }
            if cleaned == "calcium" { nutrientIndices["calcium"] = index }
            if cleaned == "iron" { nutrientIndices["iron"] = index }
            if cleaned == "potassium" { nutrientIndices["potassium"] = index }
        }
        
        print("📊 Found \(nutrientIndices.count) nutrient labels")
        
        // Find all lines with numbers (potential values)
        var valueLines: [(index: Int, value: Double, unit: String)] = []
        for (index, line) in lines.enumerated() {
            let cleaned = line.trimmingCharacters(in: .whitespaces)
            
            // Match patterns like "190", "8g", "560mg", "0ug" etc
            if let match = cleaned.range(of: #"^(\d+(?:\.\d+)?)\s*(g|mg|mcg|µg|ug)?$"#, options: .regularExpression) {
                let matchText = String(cleaned[match])
                if let numMatch = matchText.range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression),
                   let value = Double(String(matchText[numMatch])) {
                    let unit = matchText.replacingOccurrences(of: #"\d+(?:\.\d+)?"#, with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespaces).lowercased()
                    valueLines.append((index: index, value: value, unit: unit))
                }
            }
        }
        
        print("📊 Found \(nutrientIndices.count) nutrient labels and \(valueLines.count) value lines")
        
        // Sort nutrients by their line index to maintain order
        let sortedNutrients = nutrientIndices.sorted { $0.value < $1.value }
        
        guard !sortedNutrients.isEmpty else {
            print("❌ No nutrients found")
            return nil
        }
        
        // Find all potential value columns after the last nutrient label
        let lastNutrientIndex = sortedNutrients.last?.value ?? 0
        let potentialValues = valueLines.filter { $0.index > lastNutrientIndex }.sorted { $0.index < $1.index }
        
        guard !potentialValues.isEmpty else {
            print("❌ Could not find value section")
            return nil
        }
        
        // When there are multiple value columns (e.g., "As Packaged" and "100g"),
        // we need to extract just ONE column. Strategy:
        // 1. Find sequences where consecutive values are close together (within 2-3 lines)
        // 2. Prefer the sequence that starts with a unitless number (calories)
        
        var orderedValues: [(index: Int, value: Double, unit: String)] = []
        let targetCount = sortedNutrients.count
        
        // Build sequences of closely-spaced values (likely same column)
        var sequences: [[(index: Int, value: Double, unit: String)]] = []
        var currentSequence: [(index: Int, value: Double, unit: String)] = []
        
        for (idx, value) in potentialValues.enumerated() {
            if currentSequence.isEmpty {
                currentSequence.append(value)
            } else {
                let gap = value.index - currentSequence.last!.index
                // Allow slightly larger gaps for "% DV" headers or spacing issues
                if gap <= 2 {
                    // Same column
                    currentSequence.append(value)
                } else if gap <= 4 && currentSequence.count < 5 {
                    // For small sequences, be more lenient (might just be starting)
                    currentSequence.append(value)
                } else {
                    // Gap indicates different column, save current and start new
                    if currentSequence.count >= 5 {  // Only keep substantial sequences
                        sequences.append(currentSequence)
                    }
                    currentSequence = [value]
                }
            }
        }
        
        // Don't forget the last sequence
        if currentSequence.count >= 5 {
            sequences.append(currentSequence)
        }
        
        print("📊 Found \(sequences.count) potential value columns")
        for (idx, seq) in sequences.enumerated() {
            print("  Column \(idx): \(seq.count) values starting at line \(seq.first?.index ?? 0), first value: \(seq.first?.value ?? 0)\(seq.first?.unit ?? "")")
        }
        
        // Strategy for picking the right column:
        // 1. Look for the longest sequence (likely the main nutrient values)
        // 2. Check if there's a unitless value (calories) within 5 lines before it
        // 3. If so, prepend calories to the sequence
        
        guard let longestSequence = sequences.max(by: { $0.count < $1.count }) else {
            print("❌ Could not identify value column")
            return nil
        }
        
        let sequenceStart = longestSequence.first?.index ?? 0
        
        // Look for a unitless value (calories) within 5 lines before the main sequence
        if let caloriesValue = potentialValues.first(where: { val in
            val.unit.isEmpty && val.index < sequenceStart && (sequenceStart - val.index) <= 5
        }) {
            // Found calories value before main sequence - combine them
            orderedValues = [caloriesValue] + longestSequence
            print("✅ Found calories at line \(caloriesValue.index), main values at \(sequenceStart), total \(orderedValues.count) values")
        } else if longestSequence.first?.unit.isEmpty == true {
            // Sequence already starts with unitless value
            orderedValues = longestSequence
            print("✅ Using sequence starting with unitless value, \(orderedValues.count) values")
        } else {
            // Use longest sequence as-is
            orderedValues = longestSequence
            print("⚠️ Using longest sequence without calories prepend, \(orderedValues.count) values")
        }
        
        // Trim to target count
        orderedValues = Array(orderedValues.prefix(targetCount))
        
        print("📍 Using values starting at line \(orderedValues.first?.index ?? 0)")
        
        // Match nutrients to values based on their position in the sequence
        for (index, (nutrient, labelIndex)) in sortedNutrients.enumerated() {
            guard index < orderedValues.count else {
                print("⚠️ Not enough values for nutrient \(nutrient)")
                continue
            }
            let valueLine = orderedValues[index]
                switch nutrient {
                case "calories":
                    data.calories = valueLine.value
                    foundAnyData = true
                    print("✅ Matched Calories: \(valueLine.value)")
                    
                case "totalFat":
                    data.totalFat = valueLine.value
                    foundAnyData = true
                    print("✅ Matched Total Fat: \(valueLine.value)g")
                    
                case "saturatedFat":
                    data.saturatedFat = valueLine.value
                    foundAnyData = true
                    
                case "transFat":
                    data.transFat = valueLine.value
                    foundAnyData = true
                    
                case "cholesterol":
                    data.cholesterol = valueLine.value
                    foundAnyData = true
                    
                case "sodium":
                    data.sodium = valueLine.value
                    foundAnyData = true
                    print("✅ Matched Sodium: \(valueLine.value)mg")
                    
                case "totalCarbs":
                    data.totalCarbs = valueLine.value
                    foundAnyData = true
                    
                case "fiber":
                    data.fiber = valueLine.value
                    foundAnyData = true
                    
                case "totalSugars":
                    data.sugars = valueLine.value
                    foundAnyData = true
                    
                case "protein":
                    data.protein = valueLine.value
                    foundAnyData = true
                    
                case "vitaminD":
                    data.vitaminD = valueLine.value
                    foundAnyData = true
                    
                case "calcium":
                    data.calcium = valueLine.value
                    foundAnyData = true
                    print("✅ Matched Calcium: \(valueLine.value)mg")
                    
                case "iron":
                    data.iron = valueLine.value
                    foundAnyData = true
                    print("✅ Matched Iron: \(valueLine.value)mg")
                    
                case "potassium":
                    data.potassium = valueLine.value
                    foundAnyData = true
                    
                default:
                    break
                }
        }
        
        return foundAnyData ? data : nil
    }
}
