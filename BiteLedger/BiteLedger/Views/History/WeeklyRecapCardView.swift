//
//  WeeklyRecapCardView.swift
//  BiteLedger
//
//  NEW-1: Weekly logging recap share card.
//  Rendered via ImageRenderer to a UIImage, then shared via UIActivityViewController.
//

import SwiftUI
import BiteLedgerCore

// MARK: - Data Model

struct WeeklyRecapData {
    let weekStart: Date     // Monday of the recap week (ISO week start)
    let weekEnd: Date       // Sunday of the recap week
    let daysLogged: Int
    let avgCalories: Int
    let avgProtein: Int
    let avgCarbs: Int
    let avgFat: Int
    let streak: Int

    /// Build from a set of FoodLogs for the target ISO week.
    static func build(from logs: [FoodLog], weekStart: Date, streak: Int) -> WeeklyRecapData {
        let calendar = Calendar(identifier: .iso8601)
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart

        // Filter logs that fall within [weekStart, weekEnd] (inclusive)
        let weekLogs = logs.filter { log in
            let day = calendar.startOfDay(for: log.timestamp)
            return day >= calendar.startOfDay(for: weekStart) &&
                   day <= calendar.startOfDay(for: weekEnd)
        }

        let uniqueDays = Set(weekLogs.map { calendar.startOfDay(for: $0.timestamp) })
        let daysLogged = uniqueDays.count

        guard daysLogged > 0 else {
            return WeeklyRecapData(
                weekStart: weekStart, weekEnd: weekEnd,
                daysLogged: 0, avgCalories: 0,
                avgProtein: 0, avgCarbs: 0, avgFat: 0, streak: streak
            )
        }

        // Sum per day then average
        var calByDay: [Date: Double] = [:]
        var protByDay: [Date: Double] = [:]
        var carbsByDay: [Date: Double] = [:]
        var fatByDay: [Date: Double] = [:]

        for log in weekLogs {
            let day = calendar.startOfDay(for: log.timestamp)
            calByDay[day, default: 0]   += log.caloriesAtLogTime
            protByDay[day, default: 0]  += log.proteinAtLogTime
            carbsByDay[day, default: 0] += log.carbsAtLogTime
            fatByDay[day, default: 0]   += log.fatAtLogTime
        }

        let count = Double(daysLogged)
        return WeeklyRecapData(
            weekStart: weekStart,
            weekEnd: weekEnd,
            daysLogged: daysLogged,
            avgCalories: Int(calByDay.values.reduce(0, +) / count),
            avgProtein:  Int(protByDay.values.reduce(0, +) / count),
            avgCarbs:    Int(carbsByDay.values.reduce(0, +) / count),
            avgFat:      Int(fatByDay.values.reduce(0, +) / count),
            streak: streak
        )
    }
}

// MARK: - Share Card View (rendered to image)

/// Fixed-size card rendered via ImageRenderer for sharing.
/// Do NOT embed in a NavigationStack or ScrollView — render standalone.
struct WeeklyRecapCardView: View {
    let data: WeeklyRecapData

    // Fixed dimensions for consistent share image
    static let cardWidth: CGFloat = 390
    static let cardHeight: CGFloat = 520

    private var dateRangeLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        let start = fmt.string(from: data.weekStart)
        let end = fmt.string(from: data.weekEnd)
        return "\(start) – \(end)"
    }

    private var yearLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy"
        return fmt.string(from: data.weekEnd)
    }

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color("BrandPrimary"), Color("BrandPrimary").opacity(0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weekly Recap")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .textCase(.uppercase)
                        .tracking(1)

                    Text(dateRangeLabel)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)

                    Text(yearLabel)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.top, 44)
                .padding(.horizontal, 28)

                Spacer()

                // Days logged badge
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                        .font(.system(size: 16))
                    Text("\(data.daysLogged) of 7 days logged")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.white.opacity(0.15))
                .clipShape(Capsule())
                .padding(.horizontal, 28)
                .padding(.bottom, 24)

                // Nutrition grid
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        RecapNutrientTile(
                            label: "Avg Calories",
                            value: "\(data.avgCalories)",
                            unit: "cal/day",
                            icon: "flame.fill"
                        )
                        RecapNutrientTile(
                            label: "Avg Protein",
                            value: "\(data.avgProtein)",
                            unit: "g/day",
                            icon: "bolt.fill"
                        )
                    }
                    HStack(spacing: 12) {
                        RecapNutrientTile(
                            label: "Avg Carbs",
                            value: "\(data.avgCarbs)",
                            unit: "g/day",
                            icon: "leaf.fill"
                        )
                        RecapNutrientTile(
                            label: "Avg Fat",
                            value: "\(data.avgFat)",
                            unit: "g/day",
                            icon: "drop.fill"
                        )
                    }
                }
                .padding(.horizontal, 28)

                Spacer()

                // Footer
                HStack {
                    if data.streak > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(.orange)
                                .font(.system(size: 13))
                            Text("\(data.streak)-day streak")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    Spacer()
                    Text("BiteLedger")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
        }
        .frame(width: WeeklyRecapCardView.cardWidth, height: WeeklyRecapCardView.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

// MARK: - Nutrient Tile

private struct RecapNutrientTile: View {
    let label: String
    let value: String
    let unit: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                    Text(unit)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Image Renderer Helper

@MainActor
func renderWeeklyRecapCard(_ data: WeeklyRecapData) -> UIImage? {
    let card = WeeklyRecapCardView(data: data)
    let renderer = ImageRenderer(content: card)
    renderer.scale = 3.0   // @3x for retina-quality share image
    return renderer.uiImage
}

#Preview {
    WeeklyRecapCardView(data: WeeklyRecapData(
        weekStart: Calendar.current.date(byAdding: .day, value: -7, to: Date())!,
        weekEnd: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
        daysLogged: 6,
        avgCalories: 2150,
        avgProtein: 148,
        avgCarbs: 235,
        avgFat: 72,
        streak: 14
    ))
    .padding()
    .background(Color.gray.opacity(0.2))
}
