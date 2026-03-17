//
//  ClaudeMatchingService.swift
//  BiteLedger
//
//  Uses Claude to pick the best USDA / FatSecret candidate for each LoseIt food.
//  Runs after the USDA + FatSecret search passes in LoseItEnrichmentService.
//

import Foundation
import BiteLedgerCore

// MARK: - Per-food input sent to Claude

struct ClaudeFoodInput {
    let cacheKey: String
    let name: String
    let units: String
    let caloriesPerServing: Double
    let usdaCandidates: [String]   // description strings, index-aligned
    let fatSecretCandidates: [String] // foodName strings, index-aligned
}

// MARK: - Claude's answer for one food

enum ClaudeMatchPick {
    case usda(index: Int)
    case fatSecret(index: Int)
    case none
}

// MARK: - Service

struct ClaudeMatchingService {

    private let apiKey: String
    private let model = "claude-haiku-4-5-20251001"
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let batchSize = 20

    init?(apiKey: String) {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        self.apiKey = key
    }

    // MARK: - Public API

    /// Picks the best USDA or FatSecret candidate for each food.
    /// Returns a dictionary keyed by cacheKey → ClaudeMatchPick.
    /// Foods with no candidates are excluded from the result.
    func disambiguate(_ foods: [ClaudeFoodInput]) async -> [String: ClaudeMatchPick] {
        var results: [String: ClaudeMatchPick] = [:]

        // Filter to foods that actually have candidates to choose from
        let eligible = foods.filter {
            !$0.usdaCandidates.isEmpty || !$0.fatSecretCandidates.isEmpty
        }
        guard !eligible.isEmpty else { return results }

        // Process in batches
        for batchStart in stride(from: 0, to: eligible.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, eligible.count)
            let batch = Array(eligible[batchStart..<batchEnd])

            guard let picks = await callClaude(batch: batch) else { continue }

            for (key, pick) in picks {
                results[key] = pick
            }
        }

        return results
    }

    // MARK: - API call

    private func callClaude(batch: [ClaudeFoodInput]) async -> [String: ClaudeMatchPick]? {
        let prompt = buildPrompt(batch: batch)

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            print("❌ ClaudeMatchingService: network error")
            return nil
        }
        print("🤖 Claude status: \(http.statusCode)")
        if http.statusCode != 200 {
            if let s = String(data: data, encoding: .utf8) { print("❌ Claude error body: \(s.prefix(300))") }
            return nil
        }
        return parseResponse(data: data, batch: batch)
    }

    // MARK: - Prompt builder

    private func buildPrompt(batch: [ClaudeFoodInput]) -> String {
        var lines = [String]()
        lines.append("""
        You are matching food log entries to nutrition database records. \
        For each numbered food below, choose the BEST matching candidate or reply "none" if no candidate is a reasonable match.

        Rules:
        - Prefer USDA candidates for whole/generic foods (fruits, vegetables, grains, meats)
        - Prefer FatSecret candidates for branded or restaurant foods
        - "none" only if ALL candidates are clearly wrong foods
        - Be generous: "Peanut Butter Smooth" matches "PEANUT BUTTER, SMOOTH STYLE" even if wording differs

        Respond ONLY with a JSON array, one object per food, in order:
        [{"i":1,"src":"usda","idx":0}, {"i":2,"src":"none"}, ...]
        Fields: i=food number, src="usda"|"fatsecret"|"none", idx=0-based candidate index (omit if src=none)
        """)
        lines.append("")

        for (offset, food) in batch.enumerated() {
            let num = offset + 1
            lines.append("Food \(num): \"\(food.name)\" [\(food.units), ~\(Int(food.caloriesPerServing)) cal/serving]")
            if !food.usdaCandidates.isEmpty {
                lines.append("  USDA: " + food.usdaCandidates.enumerated()
                    .map { "\($0.offset). \($0.element)" }.joined(separator: " | "))
            }
            if !food.fatSecretCandidates.isEmpty {
                lines.append("  FatSecret: " + food.fatSecretCandidates.enumerated()
                    .map { "\($0.offset). \($0.element)" }.joined(separator: " | "))
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Response parser

    private func parseResponse(data: Data, batch: [ClaudeFoodInput]) -> [String: ClaudeMatchPick]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else { return nil }

        // Extract the JSON array from Claude's reply
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]") else { return nil }

        let jsonSlice = String(text[start...end])
        guard let arrayData = jsonSlice.data(using: .utf8),
              let picks = try? JSONSerialization.jsonObject(with: arrayData) as? [[String: Any]]
        else { return nil }

        var results: [String: ClaudeMatchPick] = [:]

        for pick in picks {
            guard let foodNum = pick["i"] as? Int,
                  foodNum >= 1, foodNum <= batch.count else { continue }

            let food = batch[foodNum - 1]
            let src = pick["src"] as? String ?? "none"

            switch src {
            case "usda":
                let idx = pick["idx"] as? Int ?? 0
                if idx < food.usdaCandidates.count {
                    results[food.cacheKey] = .usda(index: idx)
                }
            case "fatsecret":
                let idx = pick["idx"] as? Int ?? 0
                if idx < food.fatSecretCandidates.count {
                    results[food.cacheKey] = .fatSecret(index: idx)
                }
            default:
                results[food.cacheKey] = ClaudeMatchPick.none
            }
        }

        return results
    }
}

// MARK: - Credentials loader

extension ClaudeMatchingService {
    static func fromPlist() -> ClaudeMatchingService? {
        guard let path = Bundle.main.path(forResource: "claude", ofType: "plist") else {
            print("⚠️ ClaudeMatchingService: claude.plist not found in bundle")
            return nil
        }
        guard let dict = NSDictionary(contentsOfFile: path) as? [String: String] else {
            print("⚠️ ClaudeMatchingService: claude.plist could not be read as [String: String]")
            return nil
        }
        guard let key = dict["APIKey"], !key.hasPrefix("YOUR_") else {
            print("⚠️ ClaudeMatchingService: APIKey not set in claude.plist")
            return nil
        }
        print("✅ ClaudeMatchingService: API key loaded (\(key.prefix(10))…)")
        return ClaudeMatchingService(apiKey: key)
    }
}
