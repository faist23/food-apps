//
//  Date+Display.swift
//  BiteLedger
//

import Foundation

extension Date {
    /// Returns a human-readable last-used string:
    /// "today", "yesterday", or "EEE, MMM d" for the current year,
    /// "EEE, MMM d, yyyy" for previous years.
    public var lastUsedDisplay: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "today" }
        if calendar.isDateInYesterday(self) { return "yesterday" }
        let formatter = DateFormatter()
        let currentYear = calendar.component(.year, from: Date())
        let selfYear = calendar.component(.year, from: self)
        formatter.dateFormat = selfYear == currentYear ? "EEE, MMM d" : "EEE, MMM d, yyyy"
        return formatter.string(from: self)
    }
}
