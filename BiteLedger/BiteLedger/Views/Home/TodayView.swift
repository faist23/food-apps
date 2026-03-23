//
//  TodayView.swift
//  BiteLedger
//

import SwiftUI
import SwiftData
import BiteLedgerCore

struct TodayView: View {

    @Binding var selectedTab: Int

    @Environment(\.modelContext) private var modelContext
    @State private var logs: [FoodLog] = []
    @State private var preferences: UserPreferences?

    @State private var selectedMeal: MealType?
    @State private var editingLog: FoodLog?
    @State private var showingDailyNutrition = false
    @State private var showingMealNutrition: MealType?
    @State private var selectedDate = Date()
    @State private var showingDatePicker = false
    @State private var currentStreak = 0
    @State private var yesterdayLogs: [FoodLog] = []
    @AppStorage("firstRunBannerDismissed") private var firstRunBannerDismissed: Bool = false
    @State private var streakMilestoneToast: Int?  // T-03
    @State private var showFirstLogCelebration = false  // T-08

    // MARK: - Nutrient Spotlight (Phase 2, Feature 1)
    @State private var spotlightResults: [SpotlightResult] = []
    @AppStorage("spotlightChipDismissedDate") private var spotlightChipDismissedDate: String = ""

    // MARK: - Computed

    private var todayLogs: [FoodLog] {
        logs
    }

    private var isChipDismissedToday: Bool {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let today = fmt.string(from: Date())
        return spotlightChipDismissedDate == today
    }

    private var showSpotlightChip: Bool {
        !spotlightResults.isEmpty &&
        Set(todayLogs.map { $0.mealType }).count >= 2 &&
        !isChipDismissedToday
    }

    private func caloriesFor(meal: MealType) -> Double {
        todayLogs
            .filter { $0.mealType == meal }
            .reduce(into: 0) { $0 += $1.caloriesAtLogTime }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Sticky header with streak
                headerSection
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color("SurfacePrimary"))
                
                ScrollView {
                    VStack(spacing: 16) {
                        // D-5: First-run banner — shown until dismissed, hidden once any food is logged
                        if !firstRunBannerDismissed && todayLogs.isEmpty
                            && (preferences == nil || preferences?.goals.isEmpty == true) {
                            firstRunBanner
                                .padding(.horizontal, 20)
                        }

                        NutritionDashboard(
                            logs: todayLogs,
                            preferences: preferences,
                            onTap: {
                                showingDailyNutrition = true
                            }
                        )
                        .padding(.horizontal, 20)

                        // Nutrient Spotlight chip (Phase 2, Feature 1)
                        if showSpotlightChip, let top = spotlightResults.first {
                            spotlightChip(top: top)
                                .padding(.horizontal, 20)
                                .transition(.opacity.combined(with: .scale(0.95, anchor: .top)))
                        }

                        mealSections

                        Spacer(minLength: 60)
                    }
                    .padding(.top, 16)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showSpotlightChip)
                }
            }
            .background(Color("SurfacePrimary"))
            .navigationBarHidden(true)
            .gesture(
                DragGesture(minimumDistance: 50)
                    .onEnded { value in
                        if value.translation.width > 0 {
                            // Swipe right - go to previous day
                            selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                            loadLogsForSelectedDate()
                        } else if value.translation.width < 0 {
                            // Swipe left - go to next day (unless today)
                            if !Calendar.current.isDateInToday(selectedDate) {
                                selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                                loadLogsForSelectedDate()
                            }
                        }
                    }
            )
            .onAppear {
                loadLogsForSelectedDate()
                loadPreferences()  // must run before loadStreak so cache is available
                loadStreak()
                loadSevenDayLogs()
            }
            .onChange(of: currentStreak) { _, newStreak in
                checkStreakMilestone(newStreak)
            }
        }
        .overlay(alignment: .top) {
            // T-03: Streak milestone toast — auto-dismisses after 2 seconds
            if let milestone = streakMilestoneToast {
                StreakMilestoneToast(days: milestone)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 12)
                    .zIndex(999)
            }
        }
        .overlay(alignment: .top) {
            // T-08: First-log micro-celebration — fires exactly once, auto-dismisses after 2s
            if showFirstLogCelebration {
                FirstLogCelebrationToast {
                    withAnimation { showFirstLogCelebration = false }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 12)
                .zIndex(1000)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: streakMilestoneToast)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showFirstLogCelebration)
        .sheet(item: $selectedMeal) { meal in
            FoodSearchView(mealType: meal) { addedItem in
                let timestamp: Date

                if Calendar.current.isDateInToday(selectedDate) {
                    timestamp = Date()
                } else {
                    var components = Calendar.current.dateComponents([.year, .month, .day], from: selectedDate)
                    components.hour = 12
                    timestamp = Calendar.current.date(from: components) ?? selectedDate
                }

                // Only insert FoodItem if it's not already in the context
                // (e.g., when copying from an existing log, the FoodItem already exists)
                if addedItem.foodItem.modelContext == nil {
                    modelContext.insert(addedItem.foodItem)
                    // Link to canonical food for authoritative unit→gram conversions.
                    if addedItem.foodItem.canonicalFoodID == nil {
                        addedItem.foodItem.canonicalFoodID = CanonicalFoodMatcher.match(
                            foodName: addedItem.foodItem.name, context: modelContext
                        )?.id
                    }
                    try? modelContext.save()
                }

                let foodLog = FoodLog.create(
                    mealType: meal,
                    quantity: addedItem.quantity,
                    food: addedItem.foodItem,
                    serving: addedItem.servingSize,
                    timestamp: timestamp,
                    loggedAmount: addedItem.loggedAmount,
                    loggedUnit: addedItem.loggedUnit,
                    context: modelContext
                )

                modelContext.insert(foodLog)
                try? modelContext.save()
                loadLogsForSelectedDate()
                loadSevenDayLogs()

                // T-08: First-log micro-celebration — fire exactly once when the flag is nil.
                // Set the flag immediately before showing the overlay to prevent double-trigger.
                if let prefs = preferences, prefs.hasSeenFirstLogCelebration == nil {
                    prefs.hasSeenFirstLogCelebration = true
                    try? modelContext.save()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation { showFirstLogCelebration = true }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { showFirstLogCelebration = false }
                    }
                }

                // Invalidate the streak cache so the next loadStreak() recomputes.
                // Only needed when logging for today — past-date edits don't change
                // the streak display until the user navigates back to today anyway.
                if Calendar.current.isDateInToday(selectedDate), let prefs = preferences {
                    prefs.streakCachedDate = nil
                    try? modelContext.save()
                }
                loadStreak()
            }
        }
        .sheet(item: $editingLog) { log in
            if let foodItem = log.foodItem {
                FoodLogEditView(log: log, foodItem: foodItem) { updatedLog in
                    log.quantity = updatedLog.quantity
                    log.servingSize = updatedLog.servingSize
                    try? modelContext.save()
                    loadLogsForSelectedDate()
                }
            }
        }
        .sheet(isPresented: $showingDailyNutrition) {
            DetailedNutritionView(title: "Daily Nutrition", logs: todayLogs, preferences: preferences)
        }
        .sheet(item: $showingMealNutrition) { meal in
            DetailedNutritionView(
                title: "\(meal.rawValue) Nutrition",
                logs: todayLogs.filter { $0.mealType == meal },
                preferences: preferences
            )
        }
        .sheet(isPresented: $showingDatePicker) {
            NavigationStack {
                VStack {
                    DatePicker("Select Date", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding()
                    Spacer()
                }
                .navigationTitle("Select Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Today") {
                            selectedDate = Date()
                            showingDatePicker = false
                            loadLogsForSelectedDate()
                        }
                        .disabled(Calendar.current.isDateInToday(selectedDate))
                        .foregroundStyle(Calendar.current.isDateInToday(selectedDate) ? Color.secondary : Color("BrandPrimary"))
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showingDatePicker = false
                            loadLogsForSelectedDate()
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
    
    // MARK: - Data Loading

    /// Loads the rolling 7-day window anchored to real today (not selectedDate).
    /// value: -6 = today + 6 previous days = 7 calendar days inclusive.
    /// Called on appear and after every food log creation.
    private func loadSevenDayLogs() {
        let calendar = Calendar.current
        let sixDaysAgo = calendar.date(
            byAdding: .day, value: -6,
            to: calendar.startOfDay(for: Date())
        ) ?? Date()
        let descriptor = FetchDescriptor<FoodLog>(
            predicate: #Predicate { $0.timestamp >= sixDaysAgo }
        )
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        spotlightResults = NutrientSpotlightEngine.compute(logs: fetched)
    }

    private func dismissChip() {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        spotlightChipDismissedDate = fmt.string(from: Date())
    }

    private func loadLogsForSelectedDate() {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfDay)!

        let todayDescriptor = FetchDescriptor<FoodLog>(
            predicate: #Predicate { log in
                log.timestamp >= startOfDay && log.timestamp < endOfDay
            },
            sortBy: [SortDescriptor(\FoodLog.timestamp, order: .reverse)]
        )

        let yesterdayDescriptor = FetchDescriptor<FoodLog>(
            predicate: #Predicate { log in
                log.timestamp >= startOfYesterday && log.timestamp < startOfDay
            }
        )

        do {
            logs = try modelContext.fetch(todayDescriptor)
            yesterdayLogs = try modelContext.fetch(yesterdayDescriptor)
        } catch {
            logs = []
            yesterdayLogs = []
        }
    }

    private func hasYesterdayMeal(_ meal: MealType) -> Bool {
        yesterdayLogs.contains { $0.mealType == meal }
    }

    private func yesterdayCalories(for meal: MealType) -> Double {
        yesterdayLogs.filter { $0.mealType == meal }.reduce(0) { $0 + $1.caloriesAtLogTime }
    }
    
    private func loadStreak() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Instant return: cache is already current for today
        if let prefs = preferences,
           let cachedDate = prefs.streakCachedDate,
           calendar.startOfDay(for: cachedDate) == today {
            currentStreak = prefs.cachedStreak
            return
        }

        // Walk backward from today one COUNT query per day.
        // Each query is O(1) with a timestamp index — no full table scan.
        // When we reach the cached date we trust the stored value for that day
        // and everything before it, so we stop early. For a typical "opened the
        // app this morning" session this costs exactly 1–2 queries.
        Task {
            let cachedDay = preferences?.streakCachedDate.map { calendar.startOfDay(for: $0) }
            let cachedValue = preferences?.cachedStreak ?? 0

            var streak = 0
            var checkDate = today

            while true {
                // Short-circuit: we've walked back to the cached anchor day.
                // Since that day was already verified when we wrote the cache,
                // just add the stored count for it and everything before.
                if let anchor = cachedDay, checkDate == anchor, cachedValue > 0 {
                    streak += cachedValue
                    break
                }

                let nextDay = calendar.date(byAdding: .day, value: 1, to: checkDate)!
                let count = (try? modelContext.fetchCount(
                    FetchDescriptor<FoodLog>(predicate: #Predicate {
                        $0.timestamp >= checkDate && $0.timestamp < nextDay
                    })
                )) ?? 0

                if count > 0 {
                    streak += 1
                    checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
                } else if checkDate == today {
                    // Today is in progress — no logs yet doesn't break the streak
                    checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
                } else {
                    break
                }
            }

            currentStreak = streak

            if let prefs = preferences {
                prefs.cachedStreak = streak
                prefs.streakCachedDate = Date()
                try? modelContext.save()
            }
        }
    }
    
    // T-03: Check if the new streak value hits a milestone that hasn't been celebrated yet.
    private func checkStreakMilestone(_ streak: Int) {
        let milestones = [3, 7, 14, 30, 60, 100]
        guard let milestone = milestones.last(where: { streak >= $0 }) else { return }
        let alreadyCelebrated = preferences?.lastCelebratedMilestone ?? 0
        guard milestone > alreadyCelebrated else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation { streakMilestoneToast = milestone }
        preferences?.lastCelebratedMilestone = milestone
        try? modelContext.save()

        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { streakMilestoneToast = nil }
        }
    }

    private func loadPreferences() {
        let descriptor = FetchDescriptor<UserPreferences>()
        do {
            let results = try modelContext.fetch(descriptor)
            if let existing = results.first {
                preferences = existing
            } else {
                // Create default preferences
                let newPreferences = UserPreferences()
                modelContext.insert(newPreferences)
                try? modelContext.save()
                preferences = newPreferences
            }
        } catch {
            print("Error loading preferences: \(error)")
            let newPreferences = UserPreferences()
            modelContext.insert(newPreferences)
            try? modelContext.save()
            preferences = newPreferences
        }
    }
    
    private func copyMealFromYesterday(meal: MealType) {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        let startOfYesterday = calendar.startOfDay(for: yesterday)
        let endOfYesterday = calendar.date(byAdding: .day, value: 1, to: startOfYesterday)!
        
        // Fetch all logs from yesterday, then filter by meal in memory
        // (SwiftData predicates can't use captured MealType values)
        let descriptor = FetchDescriptor<FoodLog>(
            predicate: #Predicate { log in
                log.timestamp >= startOfYesterday && 
                log.timestamp < endOfYesterday
            }
        )
        
        do {
            let allYesterdayLogs = try modelContext.fetch(descriptor)
            let yesterdayLogs = allYesterdayLogs.filter { $0.mealType == meal }
            
            for oldLog in yesterdayLogs {
                guard let foodItem = oldLog.foodItem else { continue }
                
                let timestamp: Date
                if Calendar.current.isDateInToday(selectedDate) {
                    timestamp = Date()
                } else {
                    var components = Calendar.current.dateComponents([.year, .month, .day], from: selectedDate)
                    components.hour = 12
                    timestamp = Calendar.current.date(from: components) ?? selectedDate
                }
                
                guard let servingSize = oldLog.servingSize else { continue }
                
                // Create new log with same serving size and quantity
                let newLog = FoodLog.create(
                    mealType: meal,
                    quantity: oldLog.quantity,
                    food: foodItem,
                    serving: servingSize,
                    timestamp: timestamp,
                    context: modelContext
                )
                
                // Override with cached nutrition from original log to preserve exact values
                newLog.caloriesAtLogTime = oldLog.caloriesAtLogTime
                newLog.proteinAtLogTime = oldLog.proteinAtLogTime
                newLog.carbsAtLogTime = oldLog.carbsAtLogTime
                newLog.fatAtLogTime = oldLog.fatAtLogTime
                newLog.fiberAtLogTime = oldLog.fiberAtLogTime
                newLog.sugarAtLogTime = oldLog.sugarAtLogTime
                newLog.sodiumAtLogTime = oldLog.sodiumAtLogTime
                newLog.saturatedFatAtLogTime = oldLog.saturatedFatAtLogTime
                newLog.transFatAtLogTime = oldLog.transFatAtLogTime
                newLog.monounsaturatedFatAtLogTime = oldLog.monounsaturatedFatAtLogTime
                newLog.polyunsaturatedFatAtLogTime = oldLog.polyunsaturatedFatAtLogTime
                newLog.cholesterolAtLogTime = oldLog.cholesterolAtLogTime
                newLog.magnesiumAtLogTime = oldLog.magnesiumAtLogTime
                newLog.zincAtLogTime = oldLog.zincAtLogTime
                newLog.vitaminAAtLogTime = oldLog.vitaminAAtLogTime
                newLog.vitaminCAtLogTime = oldLog.vitaminCAtLogTime
                newLog.vitaminDAtLogTime = oldLog.vitaminDAtLogTime
                newLog.vitaminEAtLogTime = oldLog.vitaminEAtLogTime
                newLog.vitaminKAtLogTime = oldLog.vitaminKAtLogTime
                newLog.vitaminB6AtLogTime = oldLog.vitaminB6AtLogTime
                newLog.vitaminB12AtLogTime = oldLog.vitaminB12AtLogTime
                newLog.folateAtLogTime = oldLog.folateAtLogTime
                newLog.cholineAtLogTime = oldLog.cholineAtLogTime
                newLog.calciumAtLogTime = oldLog.calciumAtLogTime
                newLog.ironAtLogTime = oldLog.ironAtLogTime
                newLog.potassiumAtLogTime = oldLog.potassiumAtLogTime
                newLog.caffeineAtLogTime = oldLog.caffeineAtLogTime
                
                modelContext.insert(newLog)
            }
            
            try? modelContext.save()
            loadLogsForSelectedDate()
            if let prefs = preferences {
                prefs.streakCachedDate = nil
                try? modelContext.save()
            }
            loadStreak()
        } catch {
            print("Error copying meals: \(error)")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                loadLogsForSelectedDate()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundStyle(Color("TextSecondary"))
            }

            Spacer()

            Button {
                showingDatePicker = true
            } label: {
                VStack(spacing: 2) {
                    HStack(spacing: 8) {
                        Text(dateDisplayText)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color("TextPrimary"))
                        
                        if currentStreak > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.orange)
                                Text("\(currentStreak)")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    Text("Daily Ledger")
                        .font(.caption)
                        .foregroundStyle(Color("TextTertiary"))
                }
            }

            Spacer()

            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                loadLogsForSelectedDate()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .foregroundStyle(Color("TextSecondary"))
            }
            .disabled(Calendar.current.isDateInToday(selectedDate))
            .opacity(Calendar.current.isDateInToday(selectedDate) ? 0.3 : 1)
            

        }
    }

    // MARK: - Meals

    // MARK: - First-Run Banner (D-5)

    private var firstRunBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color("BrandPrimary"))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to BiteLedger")
                    .font(.headline)
                    .foregroundStyle(Color("TextPrimary"))
                Text("Tap any meal below to log your first food. No judgment — just awareness.")
                    .font(.subheadline)
                    .foregroundStyle(Color("TextSecondary"))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    firstRunBannerDismissed = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss welcome message")
        }
        .padding(14)
        .background(Color("SurfaceCard"))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color("DividerSubtle"), lineWidth: 1)
        )
    }

    private var mealSections: some View {
        VStack(spacing: 16) {
            ForEach(MealType.allCases, id: \.self) { meal in
                MealDiarySection(
                    meal: meal,
                    logs: todayLogs.filter { $0.mealType == meal },
                    calories: caloriesFor(meal: meal),
                    selectedDate: selectedDate,
                    hasYesterdayMeal: hasYesterdayMeal(meal),
                    yesterdayCalories: yesterdayCalories(for: meal),
                    onAddFood: { selectedMeal = meal },
                    onEditLog: { editingLog = $0 },
                    onDeleteLog: { log in
                        modelContext.delete(log)
                        try? modelContext.save()
                        loadLogsForSelectedDate()
                    },
                    onTapMeal: {
                        if !todayLogs.filter({ $0.mealType == meal }).isEmpty {
                            showingMealNutrition = meal
                        }
                    },
                    onCopyYesterday: {
                        copyMealFromYesterday(meal: meal)
                    }
                )
            }
        }
    }

    // MARK: - Nutrient Spotlight Chip

    @ViewBuilder
    private func spotlightChip(top: SpotlightResult) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color("BrandPrimary"))

            Text(top.message)
                .font(.subheadline)
                .foregroundStyle(Color("TextPrimary"))
                .lineLimit(1)

            Spacer(minLength: 4)

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    dismissChip()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color("TextSecondary"))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color("SurfaceCard"))
        )
        .overlay(
            Capsule()
                .stroke(Color("DividerSubtle"), lineWidth: 1)
        )
        .onTapGesture {
            selectedTab = 1
        }
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { _ in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        dismissChip()
                    }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(top.message). Tap to see details in History.")
        .accessibilityAction(.default) { selectedTab = 1 }
        .accessibilityAction(named: "Dismiss") {
            dismissChip()
        }
    }

    // MARK: - Date Formatting

    private var dateDisplayText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(selectedDate) { return "Today" }
        if calendar.isDateInYesterday(selectedDate) { return "Yesterday" }
        if calendar.isDateInTomorrow(selectedDate) { return "Tomorrow" }

        let formatter = DateFormatter()
        let currentYear = calendar.component(.year, from: Date())
        let selectedYear = calendar.component(.year, from: selectedDate)
        
        // Show year if it's not the current year
        if selectedYear != currentYear {
            formatter.dateFormat = "EEE, MMM d, yyyy"
        } else {
            formatter.dateFormat = "EEE, MMM d"
        }
        
        return formatter.string(from: selectedDate)
    }
}

// MARK: - T-03: Streak Milestone Toast

private struct StreakMilestoneToast: View {
    let days: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .foregroundStyle(.orange)
            Text("\(days) day streak! Keep it going")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color("TextPrimary"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule().fill(Color("SurfaceElevated"))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        )
        .accessibilityLabel("\(days) day logging streak milestone")
    }
}

// T-08: First-log micro-celebration — shown exactly once after the user's first ever food log.
private struct FirstLogCelebrationToast: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
            Text("You logged your first meal!")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color("TextPrimary"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule().fill(Color("SurfaceElevated"))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        )
        .onTapGesture { onDismiss() }
        .accessibilityLabel("You logged your first meal")
    }
}

