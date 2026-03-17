import Foundation
import Combine
import SwiftData
import BiteLedgerCore

// MARK: - Unique food extracted from a LoseIt CSV

struct LoseItUniqueFood: Identifiable, Hashable {
    let id: UUID
    let name: String
    let units: String
    let caloriesPerServing: Double

    var cacheKey: String { "\(name.lowercased())|\(units.lowercased())" }

    init(name: String, units: String, caloriesPerServing: Double) {
        self.id = UUID()
        self.name = name
        self.units = units
        self.caloriesPerServing = caloriesPerServing
    }

    func hash(into hasher: inout Hasher) { hasher.combine(cacheKey) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.cacheKey == rhs.cacheKey }
}

// MARK: - Match result for one unique food

struct EnrichmentMatch: Identifiable {
    let id: UUID
    let food: LoseItUniqueFood

    // USDA match
    var topCandidate: USDAFoodItem?
    var allCandidates: [USDAFoodItem]
    var confidence: Double      // 0.0 – 1.0

    // FatSecret match (fallback when USDA has no match)
    var fatSecretTopCandidate: FatSecretFood?
    var fatSecretServingData: FatSecretServingData?
    var fatSecretCandidates: [FatSecretFood]

    // Manual micronutrient entry
    var manualOverride: ManualNutrientOverride?

    enum Status {
        case pending
        case autoMatched        // USDA confidence >= 0.70
        case needsReview        // USDA 0.30 <= confidence < 0.70
        case noMatch            // USDA confidence < 0.30 or search failed
        case fatSecretMatched   // FatSecret fallback found a match
        case manuallyEnriched   // user typed in micronutrient values directly
        case userAccepted       // user confirmed a USDA match
        case userSkipped        // user chose to skip enrichment
    }
    var status: Status

    // USDA enrichment path
    var effectiveCandidate: USDAFoodItem? {
        switch status {
        case .autoMatched, .userAccepted: return topCandidate
        default: return nil
        }
    }

    // FatSecret enrichment path
    var effectiveFatSecretData: FatSecretServingData? {
        switch status {
        case .fatSecretMatched: return fatSecretServingData
        default: return nil
        }
    }

    // Manual enrichment path
    var effectiveManualOverride: ManualNutrientOverride? {
        switch status {
        case .manuallyEnriched: return manualOverride
        default: return nil
        }
    }

    var confidenceLabel: String {
        switch status {
        case .autoMatched:       return "\(Int(confidence * 100))% — USDA matched"
        case .needsReview:       return "\(Int(confidence * 100))% — needs review"
        case .noMatch:           return "No match found"
        case .fatSecretMatched:  return "FatSecret matched"
        case .manuallyEnriched:  return "Manually entered"
        case .userAccepted:      return "Accepted"
        case .userSkipped:       return "Skipped"
        case .pending:           return "Pending"
        }
    }
}

// MARK: - Manual micronutrient override (per serving, user-entered)

/* moved to BiteLedgerCore
struct ManualNutrientOverride {
    var potassium:  Double? // mg
    var calcium:    Double? // mg
    var iron:       Double? // mg
    var magnesium:  Double? // mg
    var zinc:       Double? // mg
    var vitaminA:   Double? // mcg
    var vitaminC:   Double? // mg
    var vitaminD:   Double? // mcg
    var vitaminE:   Double? // mg
    var vitaminK:   Double? // mcg
    var vitaminB6:  Double? // mg
    var vitaminB12: Double? // mcg
    var folate:     Double? // mcg
    var choline:    Double? // mg
    var caffeine:   Double? // mg

    var isEmpty: Bool {
        [potassium, calcium, iron, magnesium, zinc,
         vitaminA, vitaminC, vitaminD, vitaminE, vitaminK,
         vitaminB6, vitaminB12, folate, choline, caffeine].allSatisfy { $0 == nil }
    }
}*/

// MARK: - Micronutrients extracted from a USDA search result (per 100 g, app units)

/* moved to BiteLedgerCore
struct USDAMicrosPer100g {
    var caloriesPer100g: Double = 0
    var potassium:   Double? // mg
    var calcium:     Double? // mg
    var iron:        Double? // mg
    var magnesium:   Double? // mg
    var zinc:        Double? // mg
    var vitaminA:    Double? // mcg
    var vitaminC:    Double? // mg
    var vitaminD:    Double? // mcg
    var vitaminE:    Double? // mg
    var vitaminK:    Double? // mcg
    var vitaminB6:   Double? // mg
    var vitaminB12:  Double? // mcg
    var folate:      Double? // mcg
    var choline:     Double? // mg
    var caffeine:    Double? // mg
}

extension USDAFoodItem {
    /// Extracts micronutrient values from the search-result `foodNutrients` array.
    /// USDA search results for SR Legacy foods include all major nutrients per 100 g.
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
            case "320": m.vitaminA   = v > 0 ? v : nil  // mcg RAE
            case "401": m.vitaminC   = v > 0 ? v : nil  // mg
            case "324": m.vitaminD   = v > 0 ? v : nil  // mcg
            case "323": m.vitaminE   = v > 0 ? v : nil  // mg
            case "430": m.vitaminK   = v > 0 ? v : nil  // mcg
            case "415": m.vitaminB6  = v > 0 ? v : nil  // mg
            case "418": m.vitaminB12 = v > 0 ? v : nil  // mcg
            case "417": m.folate     = v > 0 ? v : nil  // mcg
            case "421": m.choline    = v > 0 ? v : nil  // mg
            case "262": m.caffeine   = v > 0 ? v : nil  // mg
            default: break
            }
        }
        return m
    }
}*/

// MARK: - Enrichment Service

@MainActor
class LoseItEnrichmentService: ObservableObject {

    enum Phase {
        case idle
        case searching
        case reviewing
        case done
    }

    @Published var matches: [EnrichmentMatch] = []
    @Published var progress: Double = 0
    @Published var statusMessage = ""
    @Published var phase: Phase = .idle

    private var searchTask: Task<Void, Never>?

    // MARK: Parse unique foods from LoseIt CSV

    func parseUniqueFoods(from csvString: String) -> [LoseItUniqueFood] {
        let rows = CSVImporter.parseCSV(csvString)
        guard rows.count > 1 else { return [] }

        let headers = rows[0].map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        guard
            let nameIdx  = headers.firstIndex(of: "name"),
            let calIdx   = headers.firstIndex(of: "calories"),
            let qtyIdx   = headers.firstIndex(of: "quantity"),
            let unitsIdx = headers.firstIndex(of: "units")
        else { return [] }

        let deletedIdx = headers.firstIndex(of: "deleted")
        let minIdx = max(nameIdx, calIdx, qtyIdx, unitsIdx)

        var seen = Set<String>()
        var foods: [LoseItUniqueFood] = []

        for row in rows.dropFirst() {
            guard row.count > minIdx else { continue }
            if let dIdx = deletedIdx, dIdx < row.count,
               row[dIdx].trimmingCharacters(in: .whitespaces) == "1" { continue }

            let name  = row[nameIdx].trimmingCharacters(in: .whitespaces)
            let units = row[unitsIdx].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }

            let qty    = Double(row[qtyIdx].trimmingCharacters(in: .whitespaces)) ?? 1.0
            let rawCal = Double(row[calIdx].trimmingCharacters(in: .whitespaces)) ?? 0
            let calPerServing = qty > 0 ? rawCal / qty : rawCal

            let key = "\(name.lowercased())|\(units.lowercased())"
            if seen.insert(key).inserted {
                foods.append(LoseItUniqueFood(name: name, units: units, caloriesPerServing: calPerServing))
            }
        }
        return foods
    }

    // MARK: Search pass (USDA → FatSecret fallback → Claude disambiguation)

    func startSearch(for foods: [LoseItUniqueFood]) {
        matches = foods.map {
            EnrichmentMatch(
                id: UUID(), food: $0,
                topCandidate: nil, allCandidates: [], confidence: 0,
                fatSecretTopCandidate: nil, fatSecretServingData: nil, fatSecretCandidates: [],
                status: .pending
            )
        }
        progress = 0
        phase = .searching
        statusMessage = "Starting USDA search…"

        searchTask = Task {
            let total = foods.count
            let batchSize = 15  // Increased concurrency

            // --- Pass 1: USDA ---
            for batchStart in stride(from: 0, to: total, by: batchSize) {
                if Task.isCancelled { break }
                let batchEnd = min(batchStart + batchSize, total)

                await withTaskGroup(of: (Int, [USDAFoodItem]).self) { group in
                    for i in batchStart..<batchEnd {
                        group.addTask {
                            let results = (try? await USDAFoodDataService.shared.searchFoods(
                                query: foods[i].name, pageSize: 5
                            )) ?? []
                            return (i, results)
                        }
                    }
                    for await (index, candidates) in group {
                        let food = foods[index]
                        let (top, score) = Self.bestMatch(query: food.name, candidates: candidates)
                        let status: EnrichmentMatch.Status
                        if      score >= 0.70 { status = .autoMatched }
                        else if score >= 0.30 { status = .needsReview }
                        else                  { status = .noMatch }
                        matches[index] = EnrichmentMatch(
                            id: matches[index].id,
                            food: food,
                            topCandidate: top,
                            allCandidates: candidates,
                            confidence: score,
                            fatSecretTopCandidate: nil,
                            fatSecretServingData: nil,
                            fatSecretCandidates: [],
                            status: status
                        )
                    }
                }

                progress = Double(batchEnd) / Double(total) * 0.45
                statusMessage = "USDA: \(batchEnd) of \(total)…"
            }

            if Task.isCancelled { phase = .reviewing; return }

            // --- Pass 2: FatSecret fallback for .noMatch foods ---
            // FatSecret rate-limits aggressively: use small batches + inter-batch pause.
            let noMatchIndices = matches.indices.filter { matches[$0].status == .noMatch }
            let fsTotal = noMatchIndices.count
            var fsProcessed = 0
            let fsBatchSize = 3   // keep well under FatSecret's rate limit
            statusMessage = "FatSecret: 0 of \(fsTotal)…"

            for batchStart in stride(from: 0, to: max(fsTotal, 1), by: fsBatchSize) {
                if Task.isCancelled { break }
                let batchEnd = min(batchStart + fsBatchSize, fsTotal)
                guard batchStart < fsTotal else { break }
                let batchIndices = noMatchIndices[batchStart..<batchEnd]

                await withTaskGroup(of: (Int, [FatSecretFood]).self) { group in
                    for matchIdx in batchIndices {
                        group.addTask {
                            let results = (try? await FatSecretService.shared.searchFoods(
                                query: foods[matchIdx].name, maxResults: 5
                            )) ?? []
                            return (matchIdx, results)
                        }
                    }
                    for await (matchIdx, candidates) in group {
                        guard !candidates.isEmpty else { continue }
                        matches[matchIdx].fatSecretCandidates = candidates
                        let food = matches[matchIdx].food
                        let (topFS, fsScore) = Self.bestFatSecretMatch(query: food.name, candidates: candidates)
                        if let topFS, fsScore >= 0.30 {
                            matches[matchIdx].fatSecretTopCandidate = topFS
                            matches[matchIdx].status = .fatSecretMatched
                        }
                    }
                }

                fsProcessed += (batchEnd - batchStart)
                progress = 0.45 + Double(fsProcessed) / Double(max(fsTotal, 1)) * 0.20
                statusMessage = "FatSecret: \(fsProcessed) of \(fsTotal)…"

                // Pause between batches to respect FatSecret's rate limit
                if batchEnd < fsTotal {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)  // 1.5s
                }
            }

            if Task.isCancelled { phase = .reviewing; return }

            // --- Pass 3: Claude disambiguation for needsReview + fatSecretMatched + noMatch ---
            // Claude looks at all candidates and picks the best match with semantic understanding.
            let claudeService = ClaudeMatchingService.fromPlist()

            if let claude = claudeService {
                let candidateIndices = matches.indices.filter {
                    let s = matches[$0].status
                    return s == .needsReview || s == .fatSecretMatched || s == .noMatch
                }

                statusMessage = "AI matching \(candidateIndices.count) foods…"

                let inputs: [ClaudeFoodInput] = candidateIndices.map { idx in
                    let m = matches[idx]
                    return ClaudeFoodInput(
                        cacheKey: m.food.cacheKey,
                        name: m.food.name,
                        units: m.food.units,
                        caloriesPerServing: m.food.caloriesPerServing,
                        usdaCandidates: m.allCandidates.map { $0.description },
                        fatSecretCandidates: m.fatSecretCandidates.map { $0.foodName }
                    )
                }

                let picks = await claude.disambiguate(inputs)
                progress = 0.85

                // Apply Claude's picks
                for idx in candidateIndices {
                    let m = matches[idx]
                    guard let pick = picks[m.food.cacheKey] else { continue }
                    switch pick {
                    case .usda(let candidateIdx):
                        if candidateIdx < m.allCandidates.count {
                            matches[idx].topCandidate = m.allCandidates[candidateIdx]
                            matches[idx].status = .autoMatched
                            matches[idx].confidence = 0.85  // Claude-elevated
                        }
                    case .fatSecret(let candidateIdx):
                        if candidateIdx < m.fatSecretCandidates.count {
                            let fsFood = m.fatSecretCandidates[candidateIdx]
                            matches[idx].fatSecretTopCandidate = fsFood
                            matches[idx].status = .fatSecretMatched
                        }
                    case .none:
                        matches[idx].status = .noMatch
                    }
                }

                // Fetch FatSecret details for newly confirmed FatSecret matches (no prior detail fetch)
                let newFSIndices = matches.indices.filter {
                    matches[$0].status == .fatSecretMatched &&
                    matches[$0].fatSecretServingData == nil &&
                    matches[$0].fatSecretTopCandidate != nil
                }

                statusMessage = "Fetching FatSecret details for \(newFSIndices.count) foods…"
                var detailsProcessed = 0
                for batchStart in stride(from: 0, to: max(newFSIndices.count, 1), by: 3) {
                    if Task.isCancelled { break }
                    let batchEnd = min(batchStart + 3, newFSIndices.count)
                    guard batchStart < newFSIndices.count else { break }
                    let batchSlice = newFSIndices[batchStart..<batchEnd]

                    await withTaskGroup(of: (Int, FatSecretServingData?).self) { group in
                        for matchIdx in batchSlice {
                            guard let fsFood = matches[matchIdx].fatSecretTopCandidate else { continue }
                            group.addTask {
                                let detail = try? await FatSecretService.shared.getFoodDetails(foodId: fsFood.foodId)
                                return (matchIdx, detail?.servings?.first)
                            }
                        }
                        for await (matchIdx, servingData) in group {
                            matches[matchIdx].fatSecretServingData = servingData
                        }
                    }
                    detailsProcessed += (batchEnd - batchStart)
                    progress = 0.85 + Double(detailsProcessed) / Double(max(newFSIndices.count, 1)) * 0.15
                    if batchEnd < newFSIndices.count {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                    }
                }
            } else {
                // No Claude key — fall back to fetching FatSecret details for word-overlap matches
                let fsDetailIndices = matches.indices.filter {
                    matches[$0].status == .fatSecretMatched &&
                    matches[$0].fatSecretServingData == nil &&
                    matches[$0].fatSecretTopCandidate != nil
                }
                for batchStart in stride(from: 0, to: max(fsDetailIndices.count, 1), by: 5) {
                    if Task.isCancelled { break }
                    let batchEnd = min(batchStart + 5, fsDetailIndices.count)
                    guard batchStart < fsDetailIndices.count else { break }
                    let batchSlice = fsDetailIndices[batchStart..<batchEnd]

                    await withTaskGroup(of: (Int, FatSecretServingData?).self) { group in
                        for matchIdx in batchSlice {
                            guard let fsFood = matches[matchIdx].fatSecretTopCandidate else { continue }
                            group.addTask {
                                let detail = try? await FatSecretService.shared.getFoodDetails(foodId: fsFood.foodId)
                                return (matchIdx, detail?.servings?.first)
                            }
                        }
                        for await (matchIdx, servingData) in group {
                            matches[matchIdx].fatSecretServingData = servingData
                        }
                    }
                    progress = 0.65 + Double(batchEnd) / Double(max(fsDetailIndices.count, 1)) * 0.35
                    statusMessage = "FatSecret details: \(batchEnd) of \(fsDetailIndices.count)…"
                }
            }

            let auto    = matches.filter { $0.status == .autoMatched }.count
            let review  = matches.filter { $0.status == .needsReview }.count
            let fs      = matches.filter { $0.status == .fatSecretMatched }.count
            let noMatch = matches.filter { $0.status == .noMatch }.count
            let aiNote  = claudeService != nil ? " (AI-assisted)" : ""
            statusMessage = "\(auto) USDA · \(fs) FatSecret · \(review) review · \(noMatch) no match\(aiNote)"
            phase = .reviewing
        }
    }

    func cancelSearch() {
        searchTask?.cancel()
        phase = .idle
    }

    // MARK: Review helpers

    var needsReviewMatches: [EnrichmentMatch] {
        matches.filter { $0.status == .needsReview }
    }

    var autoMatchedMatches: [EnrichmentMatch] {
        matches.filter { $0.status == .autoMatched }
    }

    var fatSecretMatchedMatches: [EnrichmentMatch] {
        matches.filter { $0.status == .fatSecretMatched }
    }

    var noMatchMatches: [EnrichmentMatch] {
        matches.filter { $0.status == .noMatch }
    }

    func accept(matchID: UUID) {
        guard let i = matches.firstIndex(where: { $0.id == matchID }) else { return }
        matches[i].status = .userAccepted
    }

    func skip(matchID: UUID) {
        guard let i = matches.firstIndex(where: { $0.id == matchID }) else { return }
        matches[i].status = .userSkipped
    }

    func swapCandidate(matchID: UUID, to candidate: USDAFoodItem) {
        guard let i = matches.firstIndex(where: { $0.id == matchID }) else { return }
        matches[i].topCandidate = candidate
        matches[i].status = .userAccepted
    }

    func saveManualOverride(matchID: UUID, override: ManualNutrientOverride) {
        guard let i = matches.firstIndex(where: { $0.id == matchID }) else { return }
        matches[i].manualOverride = override
        matches[i].status = override.isEmpty ? .noMatch : .manuallyEnriched
    }

    func swapToFatSecret(matchID: UUID, food: FatSecretFood, serving: FatSecretServingData?) {
        guard let i = matches.firstIndex(where: { $0.id == matchID }) else { return }
        matches[i].fatSecretTopCandidate = food
        matches[i].fatSecretServingData = serving
        matches[i].topCandidate = nil
        matches[i].status = .fatSecretMatched
    }

    // MARK: Build enrichment maps for import

    func buildEnrichmentMap() -> [String: USDAFoodItem] {
        var map: [String: USDAFoodItem] = [:]
        for match in matches {
            if let candidate = match.effectiveCandidate {
                map[match.food.cacheKey] = candidate
            }
        }
        return map
    }

    func buildFatSecretMap() -> [String: FatSecretServingData] {
        var map: [String: FatSecretServingData] = [:]
        for match in matches {
            if let data = match.effectiveFatSecretData {
                map[match.food.cacheKey] = data
            }
        }
        return map
    }

    /// Builds a map of cacheKey → FallbackSourceInfo covering all accepted matches
    /// (USDA autoMatched/userAccepted and FatSecret fatSecretMatched).
    /// Passed to `CSVImporter.importLoseItEnriched` to create FallbackSource records.
    func buildFallbackSourceMap() -> [String: FallbackSourceInfo] {
        var map: [String: FallbackSourceInfo] = [:]
        for match in matches {
            if let usda = match.effectiveCandidate {
                map[match.food.cacheKey] = FallbackSourceInfo(
                    sourceType: "usda",
                    externalID: String(usda.fdcId),
                    externalName: usda.description,
                    confidence: match.confidence
                )
            } else if match.status == .fatSecretMatched,
                      let fsFood = match.fatSecretTopCandidate {
                map[match.food.cacheKey] = FallbackSourceInfo(
                    sourceType: "fatsecret",
                    externalID: fsFood.foodId,
                    externalName: fsFood.foodName,
                    confidence: 0.0
                )
            }
        }
        return map
    }

    func buildManualMap() -> [String: ManualNutrientOverride] {
        var map: [String: ManualNutrientOverride] = [:]
        for match in matches {
            if let data = match.effectiveManualOverride {
                map[match.food.cacheKey] = data
            }
        }
        return map
    }

    var manuallyEnrichedMatches: [EnrichmentMatch] {
        matches.filter { $0.status == .manuallyEnriched }
    }

    var enrichedCount: Int {
        matches.filter {
            $0.effectiveCandidate != nil ||
            $0.effectiveFatSecretData != nil ||
            $0.effectiveManualOverride != nil
        }.count
    }
    var skippedCount: Int {
        matches.filter { $0.status == .userSkipped || $0.status == .noMatch }.count
    }

    // MARK: Confidence scoring

    static func bestMatch(query: String, candidates: [USDAFoodItem]) -> (USDAFoodItem?, Double) {
        guard !candidates.isEmpty else { return (nil, 0) }

        let q = query.lowercased()
        let qWords = Set(q.split(separator: " ").map(String.init))

        var best: USDAFoodItem?
        var bestScore: Double = 0

        for candidate in candidates {
            let desc   = candidate.description.lowercased()
            let dWords = Set(desc.split(separator: " ").map(String.init))

            var score: Double
            if desc == q {
                score = 1.0
            } else {
                let overlap = Double(qWords.intersection(dWords).count)
                let denom   = Double(max(qWords.count, dWords.count))
                score = denom > 0 ? overlap / denom : 0
                if desc.hasPrefix(q)    { score = min(1.0, score + 0.15) }
                else if desc.contains(q) { score = min(1.0, score + 0.10) }
                if dWords.count > qWords.count * 3 { score *= 0.75 }
            }

            if score > bestScore {
                bestScore = score
                best = candidate
            }
        }
        return (best, bestScore)
    }

    static func bestFatSecretMatch(query: String, candidates: [FatSecretFood]) -> (FatSecretFood?, Double) {
        guard !candidates.isEmpty else { return (nil, 0) }

        let q = query.lowercased()
        let qWords = Set(q.split(separator: " ").map(String.init))

        var best: FatSecretFood?
        var bestScore: Double = 0

        for candidate in candidates {
            let desc   = candidate.foodName.lowercased()
            let dWords = Set(desc.split(separator: " ").map(String.init))

            var score: Double
            if desc == q {
                score = 1.0
            } else {
                let overlap = Double(qWords.intersection(dWords).count)
                let denom   = Double(max(qWords.count, dWords.count))
                score = denom > 0 ? overlap / denom : 0
                if desc.hasPrefix(q)     { score = min(1.0, score + 0.15) }
                else if desc.contains(q) { score = min(1.0, score + 0.10) }
                if dWords.count > qWords.count * 3 { score *= 0.75 }
            }

            if score > bestScore {
                bestScore = score
                best = candidate
            }
        }
        return (best, bestScore)
    }
}
