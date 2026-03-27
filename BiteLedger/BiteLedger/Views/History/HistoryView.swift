//
//  HistoryView.swift
//  BiteLedger
//
//  Created by Craig Faist on 2/16/26.
//

import SwiftUI
import SwiftData
import Charts
import BiteLedgerCore

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [UserPreferences]
    @State private var allLogs: [FoodLog] = []
    @State private var selectedMealFilter: MealType? = nil // nil = all meals
    @State private var isLoading = true
    @State private var calculatedStreak = 0
    @State private var oldestLogDate: Date?
    @State private var totalUniqueDaysAllTime = 0
    @State private var selectedTimeRange: TimeRange = .thirtyDays
    @AppStorage("historyExtraNutrients") private var extraNutrientKeys: String = ""
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false

    // MARK: - Nutrient Spotlight (Phase 2, Feature 1)

    // MARK: - Nutrient Spotlight state (cached to avoid recompute on every body pass)
    @State private var spotlightResults: [SpotlightResult] = []
    @State private var sevenDayLogs: [FoodLog] = []

    private func computeSpotlightResults() {
        let calendar = Calendar.current
        // value: -6 = today + 6 previous days = 7 calendar days inclusive
        let sixDaysAgo = calendar.date(
            byAdding: .day, value: -6,
            to: calendar.startOfDay(for: Date())
        ) ?? Date()
        sevenDayLogs = allLogs.filter { $0.timestamp >= sixDaysAgo }
        spotlightResults = NutrientSpotlightEngine.compute(
            logs: sevenDayLogs,
            userGoals: preferences.first?.goals ?? [:]
        )
    }

    // MARK: - Persistence helpers

    private var selectedExtraSet: Set<Nutrient> {
        Set(extraNutrientKeys.split(separator: ",").compactMap { Nutrient(rawValue: String($0)) })
    }

    private func saveExtraSet(_ set: Set<Nutrient>) {
        extraNutrientKeys = set.map { $0.rawValue }.sorted().joined(separator: ",")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading your food history...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(spacing: 0) {
                        // Sticky trends header — stays visible while scrolling
                        if !allLogs.isEmpty {
                            trendsHeader
                        }

                        ScrollView {
                            VStack(spacing: 24) {
                                statsRow

                                if !spotlightResults.isEmpty {
                                    NutrientSpotlightCard(
                                        results: Array(spotlightResults.prefix(2)),
                                        logs: sevenDayLogs
                                    )
                                }

                                if !allLogs.isEmpty {
                                    goalChartsSection
                                }

                                mealFilterButtons
                                mostLoggedFoodsSection
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                        }
                    }
                }
            }
            .background(Color("SurfacePrimary"))
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        generateAndShareRecap()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share weekly recap")
                    .disabled(allLogs.isEmpty)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: shareItems)
                    .presentationDetents([.medium, .large])
            }
            .onAppear {
                loadRecentLogs()
                computeSpotlightResults()
            }
            .onChange(of: allLogs) { _, _ in
                computeSpotlightResults()
            }
        }
    }

    // MARK: - Share Weekly Recap (NEW-1)

    @MainActor
    private func generateAndShareRecap() {
        let calendar = Calendar(identifier: .iso8601)
        // Last complete ISO week: Monday of (today - 7 days)
        let lastWeekAny = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: lastWeekAny)
        ) ?? lastWeekAny

        let recapData = WeeklyRecapData.build(
            from: allLogs,
            weekStart: weekStart,
            streak: calculatedStreak
        )

        guard let image = renderWeeklyRecapCard(recapData) else { return }

        // Mark the week as shared on UserPreferences
        if let prefs = preferences.first {
            prefs.lastShareCardGeneratedWeek = weekStart
            try? modelContext.save()
        }

        shareItems = [image]
        showShareSheet = true
    }

    // MARK: - Sticky Trends Header

    private var trendsHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Trends")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color("TextPrimary"))

                Spacer()

                Picker("Range", selection: $selectedTimeRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            .padding(.horizontal, 20)

            if !extraNutrientsForPills.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // "All" toggle
                        let allOn = extraNutrientsForPills.allSatisfy { selectedExtraSet.contains($0) }
                        Button {
                            if allOn {
                                var updated = selectedExtraSet
                                extraNutrientsForPills.forEach { updated.remove($0) }
                                saveExtraSet(updated)
                            } else {
                                var updated = selectedExtraSet
                                extraNutrientsForPills.forEach { updated.insert($0) }
                                saveExtraSet(updated)
                            }
                        } label: {
                            Text("All")
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(allOn ? Color("BrandPrimary") : Color("SurfacePrimary"))
                                .foregroundStyle(allOn ? Color.white : Color("TextPrimary"))
                                .cornerRadius(16)
                                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                        }

                        ForEach(extraNutrientsForPills, id: \.rawValue) { nutrient in
                            let isOn = selectedExtraSet.contains(nutrient)
                            Button {
                                var updated = selectedExtraSet
                                if isOn { updated.remove(nutrient) } else { updated.insert(nutrient) }
                                saveExtraSet(updated)
                            } label: {
                                Text(nutrient.rawValue)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(isOn ? Color("BrandPrimary") : Color("SurfacePrimary"))
                                    .foregroundStyle(isOn ? Color.white : Color("TextPrimary"))
                                    .cornerRadius(16)
                                    .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.vertical, 12)
        .background(Color("SurfacePrimary"))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
    
    private func loadRecentLogs() {
        Task {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let prefs = preferences.first

            // --- Streak (per-day COUNT queries, anchored on cached value) ---
            let streak: Int
            let cachedDay = prefs?.streakCachedDate.map { calendar.startOfDay(for: $0) }
            let cachedValue = prefs?.cachedStreak ?? 0

            if let anchor = cachedDay, anchor == today, cachedValue >= 0 {
                // Cache is current — free
                streak = cachedValue
            } else {
                var s = 0
                var checkDate = today
                while true {
                    if let anchor = cachedDay, checkDate == anchor, cachedValue > 0 {
                        s += cachedValue
                        break
                    }
                    let nextDay = calendar.date(byAdding: .day, value: 1, to: checkDate)!
                    let count = (try? modelContext.fetchCount(
                        FetchDescriptor<FoodLog>(predicate: #Predicate {
                            $0.timestamp >= checkDate && $0.timestamp < nextDay
                        })
                    )) ?? 0
                    if count > 0 {
                        s += 1
                        checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
                    } else {
                        break
                    }
                }
                streak = s
                if let prefs {
                    prefs.cachedStreak = streak
                    prefs.streakCachedDate = Date()
                    try? modelContext.save()
                }
            }

            // --- Oldest log date (1-row fetch) ---
            var allTimeOldestDate: Date? = nil
            var oldestDescriptor = FetchDescriptor<FoodLog>(
                sortBy: [SortDescriptor(\FoodLog.timestamp, order: .forward)]
            )
            oldestDescriptor.fetchLimit = 1
            allTimeOldestDate = (try? modelContext.fetch(oldestDescriptor))?.first?.timestamp

            // --- 2-year display window (start of day to avoid boundary-day miss) ---
            let twoYearsAgo = calendar.startOfDay(for: calendar.date(byAdding: .year, value: -2, to: Date()) ?? Date())
            let recentDescriptor = FetchDescriptor<FoodLog>(
                predicate: #Predicate { $0.timestamp >= twoYearsAgo },
                sortBy: [SortDescriptor(\FoodLog.timestamp, order: .reverse)]
            )

            do {
                let recentLogs = try modelContext.fetch(recentDescriptor)
                let uniqueDaysInWindow = Set(recentLogs.map { calendar.startOfDay(for: $0.timestamp) }).count

                // Count unique logged days BEFORE the 2-year window by walking backward
                // from the day before twoYearsAgo down to the oldest log date.
                // This is at most a few dozen COUNT queries for most users.
                var extraDays = 0
                if let oldestDate = allTimeOldestDate {
                    let oldestDay = calendar.startOfDay(for: oldestDate)
                    let twoYearsAgoDay = twoYearsAgo // already startOfDay
                    if oldestDay < twoYearsAgoDay {
                        var checkDay = calendar.date(byAdding: .day, value: -1, to: twoYearsAgoDay)!
                        while checkDay >= oldestDay {
                            let nextDay = calendar.date(byAdding: .day, value: 1, to: checkDay)!
                            let count = (try? modelContext.fetchCount(
                                FetchDescriptor<FoodLog>(predicate: #Predicate {
                                    $0.timestamp >= checkDay && $0.timestamp < nextDay
                                })
                            )) ?? 0
                            if count > 0 { extraDays += 1 }
                            checkDay = calendar.date(byAdding: .day, value: -1, to: checkDay)!
                        }
                    }
                }

                let totalDays = uniqueDaysInWindow + extraDays
                // Streak can never logically exceed total unique days logged
                let validatedStreak = min(streak, totalDays)
                if validatedStreak != streak, let prefs {
                    prefs.cachedStreak = validatedStreak
                    try? modelContext.save()
                }

                calculatedStreak = validatedStreak
                allLogs = recentLogs
                oldestLogDate = allTimeOldestDate
                totalUniqueDaysAllTime = totalDays
                isLoading = false
            } catch {
                print("Error fetching history logs: \(error)")
                calculatedStreak = streak
                allLogs = []
                oldestLogDate = allTimeOldestDate
                totalUniqueDaysAllTime = 0
                isLoading = false
            }
        }
    }
    
    // MARK: - Meal Filter Buttons
    
    private var mealFilterButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                MealFilterButton(
                    title: "All",
                    icon: "square.grid.2x2.fill",
                    isSelected: selectedMealFilter == nil
                ) {
                    selectedMealFilter = nil
                }
                
                MealFilterButton(
                    title: "Breakfast",
                    icon: "sunrise.fill",
                    isSelected: selectedMealFilter == .breakfast
                ) {
                    selectedMealFilter = .breakfast
                }
                
                MealFilterButton(
                    title: "Lunch",
                    icon: "sun.max.fill",
                    isSelected: selectedMealFilter == .lunch
                ) {
                    selectedMealFilter = .lunch
                }
                
                MealFilterButton(
                    title: "Dinner",
                    icon: "moon.stars.fill",
                    isSelected: selectedMealFilter == .dinner
                ) {
                    selectedMealFilter = .dinner
                }
                
                MealFilterButton(
                    title: "Snacks",
                    icon: "fork.knife",
                    isSelected: selectedMealFilter == .snack
                ) {
                    selectedMealFilter = .snack
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Charts List

    private var goalChartsSection: some View {
        VStack(spacing: 16) {
            ForEach(activeGoals, id: \.rawValue) { nutrient in
                let data = dailyTotals(for: nutrient)
                let isPillSelected = selectedExtraSet.contains(nutrient)
                if data.contains(where: { $0.1 > 0 }) || isPillSelected {
                    GoalChartCard(
                        nutrient: nutrient,
                        goal: userGoals[nutrient.rawValue],
                        dailyData: data,
                        timeRange: selectedTimeRange
                    )
                }
            }
        }
    }

    private static let nutritionLabelOrder: [Nutrient] = [
        .calories,
        .fat, .saturatedFat, .transFat, .polyunsaturatedFat, .monounsaturatedFat,
        .cholesterol, .sodium,
        .carbs, .fiber, .sugar,
        .protein,
        .vitaminD, .calcium, .iron, .potassium,
        .magnesium, .zinc,
        .vitaminA, .vitaminC, .vitaminE, .vitaminK,
        .vitaminB6, .vitaminB12, .folate, .choline,
        .caffeine
    ]

    private var activeGoals: [Nutrient] {
        let pinnedNutrient = preferences.first?.pinnedNutrient.flatMap { Nutrient(rawValue: $0) }
        let core = Set([Nutrient.calories, .protein, .carbs, .fat, pinnedNutrient].compactMap { $0 })
        let withGoals = Set(preferences.first?.activeGoalNutrients ?? [])
        let visible = core.union(withGoals).union(selectedExtraSet)
        return Self.nutritionLabelOrder.filter { visible.contains($0) }
    }

    private var extraNutrientsForPills: [Nutrient] {
        let pinnedNutrient = preferences.first?.pinnedNutrient.flatMap { Nutrient(rawValue: $0) }
        let core = Set([Nutrient.calories, .protein, .carbs, .fat, pinnedNutrient].compactMap { $0 })
        let withGoals = Set(preferences.first?.activeGoalNutrients ?? [])
        // Caffeine is always available as a pill regardless of goal settings
        let alwaysShown = core.union(withGoals).subtracting([Nutrient.caffeine])
        return Self.nutritionLabelOrder.filter { !alwaysShown.contains($0) }
    }
    
    private var userGoals: [String: NutrientGoal] {
        guard let prefs = preferences.first else { return [:] }
        return prefs.goals
    }
    
    private func dailyTotals(for nutrient: Nutrient) -> [(Date, Double)] {
        let calendar = Calendar.current
        let startDate: Date
        
        switch selectedTimeRange {
        case .sevenDays:
            startDate = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        case .thirtyDays:
            startDate = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        case .ninetyDays:
            startDate = calendar.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        }
        
        let recentLogs = allLogs.filter { $0.timestamp >= startDate }
        
        // Group by day
        let grouped = Dictionary(grouping: recentLogs) { log in
            calendar.startOfDay(for: log.timestamp)
        }
        
        return grouped.map { date, logs in
            let total = totalValue(for: nutrient, in: logs)
            return (date, total)
        }
        .sorted { $0.0 < $1.0 }
    }
    
    private func totalValue(for nutrient: Nutrient, in logs: [FoodLog]) -> Double {
        switch nutrient {
        case .calories:
            return logs.reduce(0) { $0 + $1.caloriesAtLogTime }
        case .protein:
            return logs.reduce(0) { $0 + $1.proteinAtLogTime }
        case .carbs:
            return logs.reduce(0) { $0 + $1.carbsAtLogTime }
        case .fat:
            return logs.reduce(0) { $0 + $1.fatAtLogTime }
        case .fiber:
            return logs.reduce(0) { $0 + ($1.fiberAtLogTime ?? 0) }
        case .sugar:
            return logs.reduce(0) { $0 + ($1.sugarAtLogTime ?? 0) }
        case .saturatedFat:
            return logs.reduce(0) { $0 + ($1.saturatedFatAtLogTime ?? 0) }
        case .sodium:
            return logs.reduce(0) { $0 + ($1.sodiumAtLogTime ?? 0) }
        case .potassium:
            return logs.reduce(0) { $0 + ($1.potassiumAtLogTime ?? 0) }
        case .calcium:
            return logs.reduce(0) { $0 + ($1.calciumAtLogTime ?? 0) }
        case .iron:
            return logs.reduce(0) { $0 + ($1.ironAtLogTime ?? 0) }
        case .magnesium:
            return logs.reduce(0) { $0 + ($1.magnesiumAtLogTime ?? 0) }
        case .zinc:
            return logs.reduce(0) { $0 + ($1.zincAtLogTime ?? 0) }
        case .vitaminC:
            return logs.reduce(0) { $0 + ($1.vitaminCAtLogTime ?? 0) }
        case .vitaminD:
            return logs.reduce(0) { $0 + ($1.vitaminDAtLogTime ?? 0) }
        case .vitaminE:
            return logs.reduce(0) { $0 + ($1.vitaminEAtLogTime ?? 0) }
        case .vitaminB6:
            return logs.reduce(0) { $0 + ($1.vitaminB6AtLogTime ?? 0) }
        case .choline:
            return logs.reduce(0) { $0 + ($1.cholineAtLogTime ?? 0) }
        case .caffeine:
            return logs.reduce(0) { $0 + ($1.caffeineAtLogTime ?? 0) }
        case .cholesterol:
            return logs.reduce(0) { $0 + ($1.cholesterolAtLogTime ?? 0) }
        case .vitaminA:
            return logs.reduce(0) { $0 + ($1.vitaminAAtLogTime ?? 0) }
        case .vitaminK:
            return logs.reduce(0) { $0 + ($1.vitaminKAtLogTime ?? 0) }
        case .vitaminB12:
            return logs.reduce(0) { $0 + ($1.vitaminB12AtLogTime ?? 0) }
        case .folate:
            return logs.reduce(0) { $0 + ($1.folateAtLogTime ?? 0) }
        default:
            return 0
        }
    }
    
    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatCard(
                title: "Streak",
                value: "\(currentStreak)",
                unit: "days",
                icon: "flame.fill",
                color: .orange
            )
            
            StatCard(
                title: "Total Days",
                value: "\(totalUniqueDaysAllTime)",
                unit: "\(loggingPercentage)% logged",
                icon: "calendar.badge.checkmark",
                color: .green
            )
            
            StatCard(
                title: "Avg Cal/Day",
                value: "\(averageCaloriesLast30Days)",
                unit: "last 30d",
                icon: "chart.line.uptrend.xyaxis",
                color: .blue
            )
        }
    }
    
    // MARK: - Most Logged Foods
    
    private var mostLoggedFoodsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Most Logged Foods")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Color("TextPrimary"))
                .padding(.horizontal, 4)
            
            // All Time
            FoodFrequencyCard(
                title: "All Time",
                foods: topFoodsAllTime,
                icon: "trophy.fill",
                color: .orange
            )
            
            // This Year
            FoodFrequencyCard(
                title: "This Year",
                foods: topFoodsThisYear,
                icon: "calendar",
                color: .blue
            )
            
            // Last Year
            if !topFoodsLastYear.isEmpty {
                FoodFrequencyCard(
                    title: "Last Year",
                    foods: topFoodsLastYear,
                    icon: "clock.arrow.circlepath",
                    color: .purple
                )
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var currentStreak: Int {
        // Use pre-calculated streak from full database scan
        return calculatedStreak
    }
    
    private var totalDaysLogged: Int {
        let calendar = Calendar.current
        let uniqueDays = Set(allLogs.map { calendar.startOfDay(for: $0.timestamp) })
        return uniqueDays.count
    }
    
    private var totalDaysSinceStart: Int {
        guard let oldestDate = oldestLogDate else { return 0 }
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: oldestDate)
        let today = calendar.startOfDay(for: Date())
        let components = calendar.dateComponents([.day], from: startDay, to: today)
        return (components.day ?? 0) + 1
    }
    
    private var loggingPercentage: Int {
        guard totalDaysSinceStart > 0 else { return 0 }
        return Int((Double(totalUniqueDaysAllTime) / Double(totalDaysSinceStart)) * 100)
    }
    
    private var averageCaloriesLast30Days: Int {
        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        
        let recentLogs = allLogs.filter { $0.timestamp >= thirtyDaysAgo }
        
        // Group by day
        let logsByDay = Dictionary(grouping: recentLogs) { log in
            calendar.startOfDay(for: log.timestamp)
        }
        
        let daysWithLogs = logsByDay.count
        guard daysWithLogs > 0 else { return 0 }
        
        let totalCalories = recentLogs.reduce(0.0) { $0 + $1.caloriesAtLogTime }
        return Int(totalCalories / Double(daysWithLogs))
    }
    
    private var filteredLogs: [FoodLog] {
        if let mealFilter = selectedMealFilter {
            return allLogs.filter { $0.mealType == mealFilter }
        }
        return allLogs
    }
    
    private var topFoodsAllTime: [(name: String, count: Int)] {
        getTopFoods(from: filteredLogs, limit: 10)
    }
    
    private var topFoodsThisYear: [(name: String, count: Int)] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let logsThisYear = filteredLogs.filter { log in
            calendar.component(.year, from: log.timestamp) == currentYear
        }
        return getTopFoods(from: logsThisYear, limit: 5)
    }
    
    private var topFoodsLastYear: [(name: String, count: Int)] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let logsLastYear = filteredLogs.filter { log in
            calendar.component(.year, from: log.timestamp) == currentYear - 1
        }
        return getTopFoods(from: logsLastYear, limit: 5)
    }
    
    private func getTopFoods(from logs: [FoodLog], limit: Int) -> [(name: String, count: Int)] {
        let foodCounts = logs.reduce(into: [String: Int]()) { counts, log in
            guard let foodName = log.foodItem?.name else { return }
            counts[foodName, default: 0] += 1
        }
        
        return foodCounts
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (name: $0.key, count: $0.value) }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color("TextPrimary"))
            
            VStack(spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color("TextSecondary"))
                
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(Color("TextTertiary"))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color("SurfacePrimary"))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
}

// MARK: - Time Range

enum TimeRange: String, CaseIterable {
    case sevenDays = "7D"
    case thirtyDays = "30D"
    case ninetyDays = "90D"
}

// MARK: - Goal Chart Card

struct GoalChartCard: View {
    let nutrient: Nutrient
    let goal: NutrientGoal?
    let dailyData: [(Date, Double)]
    let timeRange: TimeRange

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(nutrient.rawValue)
                        .font(.headline)
                        .foregroundStyle(Color("TextPrimary"))

                    if let goalDescription {
                        Text(goalDescription)
                            .font(.caption)
                            .foregroundStyle(Color("TextSecondary"))
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(averageValueFormatted)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(Color("TextPrimary"))

                    Text("avg \(nutrient.unit)/day")
                        .font(.caption2)
                        .foregroundStyle(Color("TextSecondary"))
                }
            }

            // Rolling average status — only when a goal is set
            if let goal {
                HStack(spacing: 8) {
                    Image(systemName: weeklyAverageOnTarget(goal: goal) ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(weeklyAverageOnTarget(goal: goal) ? .green : .orange)
                        .font(.caption)

                    Text(weeklyAverageStatusText(goal: goal))
                        .font(.caption)
                        .foregroundStyle(Color("TextSecondary"))
                }
            }

            // Chart
            Chart {
                ForEach(dailyData, id: \.0) { date, value in
                    AreaMark(
                        x: .value("Date", date),
                        y: .value("Amount", value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color("BrandPrimary").opacity(0.2), Color("BrandPrimary").opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }

                ForEach(rollingAverageData, id: \.0) { date, avgValue in
                    LineMark(
                        x: .value("Date", date),
                        y: .value("Average", avgValue)
                    )
                    .foregroundStyle(Color("BrandPrimary"))
                    .lineStyle(StrokeStyle(lineWidth: 3))
                    .interpolationMethod(.catmullRom)
                }

                if let goal {
                    switch goal.goalType {
                    case .minimum, .maximum:
                        RuleMark(y: .value("Goal", goal.targetValue))
                            .foregroundStyle(.green.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                    case .range:
                        RuleMark(y: .value("Min", goal.targetValue))
                            .foregroundStyle(.green.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                        RuleMark(y: .value("Max", goal.rangeMax ?? goal.targetValue * 1.1))
                            .foregroundStyle(.orange.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                    }
                } else if let dv = fdaDailyValue {
                    RuleMark(y: .value("FDA DV", dv))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }
            }
            .frame(height: 180)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: xAxisStrideDays)) { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date, format: .dateTime.month(.abbreviated).day())
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(formatValue(amount))
                                .font(.caption2)
                        }
                    }
                }
            }

            // Legend
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Rectangle()
                        .fill(Color("BrandPrimary").opacity(0.2))
                        .frame(width: 16, height: 12)
                    Text("Daily")
                        .font(.caption2)
                        .foregroundStyle(Color("TextSecondary"))
                }

                HStack(spacing: 4) {
                    Rectangle()
                        .fill(Color("BrandPrimary"))
                        .frame(width: 16, height: 3)
                    Text("7-Day Avg")
                        .font(.caption2)
                        .foregroundStyle(Color("TextSecondary"))
                }

                if let goal {
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(.green.opacity(0.6))
                            .frame(width: 16, height: 2)
                        Text(goal.goalType == .range ? "Target Range" : "Goal")
                            .font(.caption2)
                            .foregroundStyle(Color("TextSecondary"))
                    }
                } else if fdaDailyValue != nil {
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 16, height: 2)
                        Text("FDA DV")
                            .font(.caption2)
                            .foregroundStyle(Color("TextSecondary"))
                    }
                }
            }
            .padding(.top, 8)
        }
        .padding(16)
        .background(Color("SurfaceCard"))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
    
    // MARK: - Computed Properties
    
    private var rollingAverageData: [(Date, Double)] {
        guard dailyData.count >= 2 else { return dailyData }
        
        let sortedData = dailyData.sorted { $0.0 < $1.0 }
        var result: [(Date, Double)] = []
        
        for i in 0..<sortedData.count {
            // Calculate 7-day rolling average (or fewer days if not enough data)
            let startIndex = max(0, i - 6)
            let window = sortedData[startIndex...i]
            let average = window.reduce(0.0) { $0 + $1.1 } / Double(window.count)
            result.append((sortedData[i].0, average))
        }
        
        return result
    }
    
    private var overallAverage: Double {
        guard !dailyData.isEmpty else { return 0 }
        return dailyData.reduce(0.0) { $0 + $1.1 } / Double(dailyData.count)
    }
    
    private var averageValueFormatted: String {
        formatValue(overallAverage)
    }
    
    private func weeklyAverageOnTarget(goal: NutrientGoal) -> Bool {
        guard let latestAverage = rollingAverageData.suffix(7).last?.1 else { return false }
        switch goal.goalType {
        case .minimum: return latestAverage >= goal.targetValue
        case .maximum: return latestAverage <= goal.targetValue
        case .range:
            let rangeMax = goal.rangeMax ?? goal.targetValue * 1.1
            return latestAverage >= goal.targetValue && latestAverage <= rangeMax
        }
    }

    private func weeklyAverageStatusText(goal: NutrientGoal) -> String {
        if weeklyAverageOnTarget(goal: goal) {
            return "7-day rolling average on target"
        }
        switch goal.goalType {
        case .minimum: return "7-day average below target"
        case .maximum: return "7-day average above target"
        case .range:
            return overallAverage < goal.targetValue ? "7-day average below range" : "7-day average above range"
        }
    }

    private var goalDescription: String? {
        if let goal {
            switch goal.goalType {
            case .minimum: return "Goal: at least \(formatValue(goal.targetValue)) \(nutrient.unit)"
            case .maximum: return "Goal: under \(formatValue(goal.targetValue)) \(nutrient.unit)"
            case .range:
                let max = goal.rangeMax ?? goal.targetValue * 1.1
                return "Goal: \(formatValue(goal.targetValue))–\(formatValue(max)) \(nutrient.unit)"
            }
        }
        if let dv = fdaDailyValue {
            return "FDA DV: \(formatValue(dv)) \(nutrient.unit)"
        }
        return nil
    }
    
    
    private var xAxisStrideDays: Int {
        switch timeRange {
        case .sevenDays:  return 1
        case .thirtyDays: return 7
        case .ninetyDays: return 15
        }
    }
    
    private func formatValue(_ value: Double) -> String {
        if value >= 10 {
            return "\(Int(value.rounded()))"
        } else if value >= 1 {
            return String(format: "%.1f", value)
        } else {
            return String(format: "%.2f", value)
        }
    }

    /// FDA daily values in the units BiteLedger uses for each nutrient.
    private var fdaDailyValue: Double? {
        switch nutrient {
        case .calories:        return 2000
        case .protein:         return 50
        case .carbs:           return 275
        case .fat:             return 78
        case .fiber:           return 28
        case .sugar:           return nil  // BiteLedger tracks total sugar; FDA DV is for added sugars only
        case .saturatedFat:    return 20
        case .cholesterol:     return 300   // mg
        case .sodium:          return 2300
        case .potassium:       return 4700
        case .calcium:         return 1300
        case .iron:            return 18
        case .magnesium:       return 420
        case .zinc:            return 11
        case .vitaminA:        return 900   // mcg RAE
        case .vitaminC:        return 90
        case .vitaminD:        return 20
        case .vitaminE:        return 15
        case .vitaminK:        return 120   // mcg
        case .vitaminB6:       return 1.7
        case .vitaminB12:      return 2.4   // mcg
        case .folate:          return 400   // mcg DFE
        case .choline:         return 550
        default:               return nil
        }
    }
}

// MARK: - Meal Filter Button

struct MealFilterButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? Color.orange : Color("SurfacePrimary"))
            .foregroundStyle(isSelected ? .white : Color("TextPrimary"))
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
    }
}

// MARK: - Food Frequency Card

struct FoodFrequencyCard: View {
    let title: String
    let foods: [(name: String, count: Int)]
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color("TextPrimary"))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            if foods.isEmpty {
                Text("No data yet")
                    .font(.subheadline)
                    .foregroundStyle(Color("TextSecondary"))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(foods.enumerated()), id: \.offset) { index, food in
                        HStack {
                            Text("\(index + 1)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(color)
                                .frame(width: 24)
                            
                            Text(food.name)
                                .font(.subheadline)
                                .foregroundStyle(Color("TextPrimary"))
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text("\(food.count)×")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color("TextSecondary"))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        
                        if index < foods.count - 1 {
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .background(Color("SurfacePrimary"))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
}
