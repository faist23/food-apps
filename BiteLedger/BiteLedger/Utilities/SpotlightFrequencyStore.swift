//
//  SpotlightFrequencyStore.swift
//  BiteLedger
//
//  Tracks how many distinct calendar days each nutrient spotlight has been
//  shown so the app doesn't nag. Rules:
//    - Show freely until the nutrient has appeared on 2 distinct calendar days.
//    - After 2 shows, suppress for 21 days from the last shown date.
//    - After the cooldown expires, the count resets and the cycle repeats.
//
//  Both TodayView (chip) and HistoryView (card) funnel through this store.
//  Recording is deduped per calendar day, so opening both surfaces on the
//  same day counts as one show.
//

import Foundation
import BiteLedgerCore

final class SpotlightFrequencyStore {
    static let shared = SpotlightFrequencyStore()

    private let maxShows = 2
    private let cooldownDays = 21
    private let userDefaultsKey = "spotlightFrequency_v1"
    private let calendar = Calendar.current

    private struct Record: Codable {
        var showCount: Int
        var lastShownDate: Date
    }

    private var store: [String: Record] {
        get {
            guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
                  let decoded = try? JSONDecoder().decode([String: Record].self, from: data)
            else { return [:] }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
            }
        }
    }

    /// Returns false when the nutrient has been shown maxShows times and the
    /// cooldown has not yet expired.
    func shouldShow(_ nutrient: Nutrient) -> Bool {
        guard let record = store[nutrient.rawValue] else { return true }
        let daysSinceLast = calendar.dateComponents(
            [.day], from: record.lastShownDate, to: Date()
        ).day ?? 0
        if daysSinceLast >= cooldownDays { return true }
        return record.showCount < maxShows
    }

    /// Call once per surface (TodayView, HistoryView) when the nutrient is
    /// actually displayed. Deduped: multiple calls on the same calendar day
    /// only count as one show.
    func recordShown(_ nutrient: Nutrient) {
        let today = calendar.startOfDay(for: Date())
        var current = store
        if var record = current[nutrient.rawValue] {
            let daysSinceLast = calendar.dateComponents(
                [.day], from: record.lastShownDate, to: Date()
            ).day ?? 0
            let lastDay = calendar.startOfDay(for: record.lastShownDate)
            guard today != lastDay else { return } // already recorded today
            if daysSinceLast >= cooldownDays {
                record.showCount = 1
            } else {
                record.showCount += 1
            }
            record.lastShownDate = Date()
            current[nutrient.rawValue] = record
        } else {
            current[nutrient.rawValue] = Record(showCount: 1, lastShownDate: Date())
        }
        store = current
    }
}
