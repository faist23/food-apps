//
//  CanonicalFoodMatcher.swift
//  BiteLedger
//
//  Created by Craig Faist on 3/14/26.
//

import SwiftData
import Foundation

// MARK: - CanonicalFoodMatcher

/// Matches a food name against the seeded CanonicalFood catalog.
///
/// Used at food creation time (import, manual entry, picker) to link
/// `FoodItem.canonicalFoodID` so the edit view can retrieve food-specific
/// unit → gram conversions (e.g., Peanut Butter: 1 tbsp = 16g instead of
/// the generic 15g/tbsp density estimate).
///
/// Matching priority:
///   1. Exact (case-insensitive) match on the canonical name
///   2. Food name *contains* the full canonical name (longest match wins)
///      e.g. "Skippy Peanut Butter Creamy" → "Peanut Butter"
///   3. Word-overlap ≥ 75 % of canonical name words appear in the food name
///      e.g. "Oat Milk Barista Edition" → "Oat Milk" (2/2 words)
public enum CanonicalFoodMatcher {

    // MARK: - Matching

    /// Returns the best-matching CanonicalFood for `foodName` from a pre-fetched list,
    /// or `nil` when no match clears the minimum threshold.
    public static func match(foodName: String, in canonicalFoods: [CanonicalFood]) -> CanonicalFood? {
        let normalized = foodName.lowercased()

        // 1. Exact match.
        if let exact = canonicalFoods.first(where: { $0.canonicalName == normalized }) {
            return exact
        }

        // 2. Canonical name is a substring of food name — prefer the longest match
        //    so "Peanut Butter" wins over "Butter" for "Jif Peanut Butter".
        let byContains = canonicalFoods.filter { normalized.contains($0.canonicalName) }
        if let best = byContains.max(by: { $0.canonicalName.count < $1.canonicalName.count }) {
            return best
        }

        // 3. Word-overlap: count what fraction of the canonical name's meaningful words
        //    appear in the food name. Only consider words longer than 2 chars to skip
        //    articles / prepositions. Require ≥ 75 % overlap.
        let foodWords = Set(
            normalized
                .components(separatedBy: .whitespaces)
                .filter { $0.count > 2 }
        )

        var bestScore = 0.0
        var bestMatch: CanonicalFood?

        for canonical in canonicalFoods {
            let canonWords = Set(
                canonical.canonicalName
                    .components(separatedBy: .whitespaces)
                    .filter { $0.count > 2 }
            )
            guard !canonWords.isEmpty else { continue }
            let overlap = Double(foodWords.intersection(canonWords).count)
                        / Double(canonWords.count)
            if overlap >= 0.75, overlap > bestScore {
                bestScore = overlap
                bestMatch = canonical
            }
        }

        return bestMatch
    }

    /// Convenience overload: fetches canonical foods from `context` and matches.
    ///
    /// Use the `in:` overload instead when matching many foods at once (import paths)
    /// to avoid repeated fetches — fetch once, pass the list, call for each food.
    public static func match(foodName: String, context: ModelContext) -> CanonicalFood? {
        guard let canonicals = try? context.fetch(FetchDescriptor<CanonicalFood>()),
              !canonicals.isEmpty else { return nil }
        return match(foodName: foodName, in: canonicals)
    }
}
