//
//  MealPlanDayRow.swift
//  BiteRecipe
//
//  Collapsible day row in MealPlannerView.
//  Collapsed: day pill | dinner cluster name | variety nudge | calorie badge | chevron.
//  Expanded: dinner cluster (items list + Add button) | nutrition pills | Log Day button.
//
//  v2 (SchemaV4): renders MealPlanMeal/MealPlanMealItem instead of MealPlanEntry.
//  MealEntrySheet is multi-add — each onAdd call persists one MealPlanMealItem.
//

import SwiftUI
import SwiftData
import BiteLedgerCore

struct MealPlanDayRow: View {
    @Environment(\.modelContext) private var modelContext

    let date: Date
    let mealPlan: MealPlan
    let repeatedDinnerRecipeIDs: Set<PersistentIdentifier>

    @State private var isExpanded = false
    @State private var isLogging = false
    @State private var logResult: LogResult? = nil
    @State private var showingAddSheet = false
    @State private var isEditingClusterName = false
    @State private var clusterNameText = ""

    private enum LogResult {
        case success(logged: Int, skipped: Int)
    }

    // MARK: - Computed properties

    private var dinnerMeal: MealPlanMeal? {
        mealPlan.meals.first {
            Calendar.current.isDate($0.date, inSameDayAs: date) && $0.mealType == .dinner
        }
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    private var hasVarietyNudge: Bool {
        guard let meal = dinnerMeal else { return false }
        return meal.items.compactMap(\.recipe?.persistentModelID)
            .contains { repeatedDinnerRecipeIDs.contains($0) }
    }

    // Estimated day nutrition from all valid dinner items
    private var dayNutrition: NutritionCalculator.Result {
        guard let meal = dinnerMeal else { return .zero }
        return meal.items.filter(\.isValid).reduce(.zero) { sum, item in
            if let recipe = item.recipe {
                return sum + NutritionCalculator.calculateRecipeNutrition(
                    ingredients: recipe.ingredients,
                    yield: 1.0 / max(item.servingCount, 0.5)
                )
            } else if let food = item.foodItem {
                return sum + NutritionCalculator.preview(
                    food: food,
                    serving: item.servingSize,
                    quantity: item.servingCount
                )
            }
            return sum
        }
    }

    private var hasNoValidItems: Bool {
        (dinnerMeal?.items.filter(\.isValid) ?? []).isEmpty
    }

    /// Log Day is only available for today and past days — not future dates.
    private var isFutureDay: Bool {
        Calendar.current.compare(date, to: Date(), toGranularity: .day) == .orderedDescending
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            collapsedRow
            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .sheet(isPresented: $showingAddSheet) {
            MealEntrySheet(
                mealType: .dinner,
                date: date,
                onAdd: { recipe, food, note, serving, count in
                    addItemToMeal(mealType: .dinner, recipe: recipe, food: food, note: note, serving: serving, count: count)
                }
            )
        }
    }

    // MARK: - Collapsed row

    private var collapsedRow: some View {
        Button {
            withAnimation { isExpanded.toggle() }
        } label: {
            HStack(spacing: 12) {
                // Day pill
                VStack(spacing: 1) {
                    Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isToday ? Color("BrandPrimary") : Color("TextSecondary"))
                    Text(date.formatted(.dateTime.day()))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(isToday ? Color("BrandPrimary") : Color("TextPrimary"))
                }
                .frame(width: 36)
                .padding(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isToday ? Color("BrandPrimary") : Color.clear, lineWidth: 1.5)
                )

                // Dinner cluster name
                HStack(spacing: 4) {
                    if let displayName = dinnerMeal?.displayName {
                        Text(displayName)
                            .font(.subheadline)
                            .foregroundStyle(Color("TextPrimary"))
                            .lineLimit(1)
                        if hasVarietyNudge {
                            Image(systemName: "repeat.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(.orange)
                                .accessibilityLabel("Planned multiple times this week")
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 13))
                                .foregroundStyle(Color("BrandAccent"))
                            Text("Add dinner")
                                .font(.subheadline)
                                .foregroundStyle(Color("BrandAccent"))
                        }
                    }
                }

                Spacer()

                // Calorie badge
                if dayNutrition.calories > 0 {
                    Text("\(Int(dayNutrition.calories)) cal")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color("TextSecondary"))
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color("TextTertiary"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(collapsedAccessibilityLabel)
    }

    private var collapsedAccessibilityLabel: String {
        let dayStr = date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let mealStr = dinnerMeal?.displayName ?? "not planned"
        let calStr = dayNutrition.calories > 0 ? ", \(Int(dayNutrition.calories)) calories" : ""
        return "\(dayStr), \(mealStr)\(calStr)"
    }

    // MARK: - Expanded content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().padding(.leading, 16)
            dinnerClusterSection
            nutritionPills
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            Divider().padding(.leading, 16)
            HStack {
                Spacer()
                logDayButton
                    .padding(.trailing, 16)
                    .padding(.vertical, 10)
            }
        }
        .background(Color("SurfacePrimary"))
    }

    // MARK: - Dinner cluster section

    private var dinnerClusterSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cluster header: icon + name + pencil
            HStack(spacing: 10) {
                Image(systemName: MealType.dinner.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color("TextSecondary"))
                    .frame(width: 24)
                    .padding(.leading, 16)

                if isEditingClusterName {
                    TextField("Meal name", text: $clusterNameText)
                        .font(.subheadline)
                        .foregroundStyle(Color("TextPrimary"))
                        .onSubmit { saveClusterName() }
                } else {
                    Text(dinnerMeal?.displayName ?? "Dinner")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(
                            dinnerMeal?.displayName != nil
                            ? Color("TextPrimary")
                            : Color("TextSecondary")
                        )
                        .lineLimit(1)
                }

                Button {
                    if isEditingClusterName {
                        saveClusterName()
                    } else {
                        clusterNameText = dinnerMeal?.name ?? ""
                        isEditingClusterName = true
                    }
                } label: {
                    Image(systemName: isEditingClusterName ? "checkmark" : "pencil")
                        .font(.system(size: 13))
                        .foregroundStyle(Color("BrandAccent"))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)

                // Copy to another day — only shown when this day has a planned dinner
                if let meal = dinnerMeal, !meal.items.isEmpty {
                    let otherDays = mealPlan.weekDates().filter {
                        !Calendar.current.isDate($0, inSameDayAs: date)
                    }
                    Menu {
                        ForEach(otherDays, id: \.self) { targetDay in
                            Button {
                                copyMealToDay(meal, to: targetDay)
                            } label: {
                                Label(
                                    targetDay.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
                                    systemImage: "doc.on.doc"
                                )
                            }
                        }
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 13))
                            .foregroundStyle(Color("BrandAccent"))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copy dinner to another day")
                }

                Spacer()
            }
            .padding(.vertical, 10)

            // Items list
            if let meal = dinnerMeal {
                ForEach(meal.items, id: \.persistentModelID) { item in
                    dinnerItemRow(item)
                    Divider().padding(.leading, 64)
                }
            }

            // Add to Dinner button
            Button {
                showingAddSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 16))
                    Text("Add to Dinner")
                        .font(.subheadline)
                }
                .foregroundStyle(Color("BrandAccent"))
                .padding(.leading, 64)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add item to dinner")

            Divider().padding(.leading, 16)
        }
    }

    private func dinnerItemRow(_ item: MealPlanMealItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.recipe != nil ? "fork.knife" : item.isNoteOnly ? "pencil" : "leaf")
                .font(.system(size: 13))
                .foregroundStyle(Color("TextTertiary"))
                .frame(width: 24)
                .padding(.leading, 40)

            Text(item.displayName)
                .font(.subheadline)
                .foregroundStyle(item.isValid ? Color("TextPrimary") : Color("TextTertiary"))
                .lineLimit(1)

            Spacer()

            // Serving count badge (hidden for notes and count==1)
            if !item.isNoteOnly && item.servingCount != 1.0 {
                let countStr = item.servingCount.truncatingRemainder(dividingBy: 1) == 0
                    ? "×\(Int(item.servingCount))"
                    : "×\(String(format: "%.1g", item.servingCount))"
                Text(countStr)
                    .font(.caption)
                    .foregroundStyle(Color("TextSecondary"))
            }

            // Delete button
            Button {
                modelContext.delete(item)
                try? modelContext.save()
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(.red.opacity(0.7))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Nutrition pills

    private var nutritionPills: some View {
        let n = dayNutrition
        return HStack(spacing: 8) {
            nutritionPill(label: "CAL", value: Int(n.calories), unit: "kcal")
            nutritionPill(label: "PROTEIN", value: Int(n.protein), unit: "g")
            nutritionPill(label: "CARBS", value: Int(n.carbs), unit: "g")
            nutritionPill(label: "FAT", value: Int(n.fat), unit: "g")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Estimated \(Int(n.calories)) calories, \(Int(n.protein))g protein, \(Int(n.carbs))g carbs, \(Int(n.fat))g fat"
        )
    }

    private func nutritionPill(label: String, value: Int, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color("TextSecondary"))
            Text("\(value)")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Color("TextPrimary"))
            Text(unit)
                .font(.system(size: 11))
                .foregroundStyle(Color("TextTertiary"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color("SurfaceCard"), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color("DividerSubtle"), lineWidth: 1)
        )
    }

    // MARK: - Log Day button

    private var logDayButton: some View {
        Button {
            guard !isLogging else { return }
            Task { await logDay() }
        } label: {
            HStack(spacing: 6) {
                if isLogging {
                    ProgressView().scaleEffect(0.8)
                    Text("Logging…")
                } else if case .success(let logged, let skipped) = logResult {
                    Image(systemName: "checkmark")
                    if skipped > 0 {
                        Text("\(logged) logged, \(skipped) skipped ⚠︎")
                    } else {
                        Text("Logged to BiteLedger ✓")
                    }
                } else {
                    Text("Log Day")
                }
            }
            .font(.subheadline)
            .foregroundStyle(logButtonColor)
        }
        .disabled(isLogging || hasNoValidItems || isFutureDay)
        .accessibilityHint(
            isLogging ? "Logging in progress, please wait"
            : isFutureDay ? "Log Day is only available for today and past days"
            : ""
        )
    }

    private var logButtonColor: Color {
        if case .success(_, let skipped) = logResult { return skipped > 0 ? .orange : Color("BrandAccent") }
        return (hasNoValidItems || isFutureDay) ? Color("TextTertiary") : Color("BrandAccent")
    }

    // MARK: - Log Day

    private func logDay() async {
        isLogging = true
        logResult = nil
        var logged = 0
        var skipped = 0

        let dayMeals = mealPlan.meals.filter {
            Calendar.current.isDate($0.date, inSameDayAs: date)
        }

        for meal in dayMeals {
            for item in meal.items where item.isValid {
                guard item.meal != nil else { continue }  // orphan guard
                if item.isNoteOnly {
                    print("⚠️ logDay: skipping note-only item '\(item.note ?? "")'")
                    continue
                }
                if let recipe = item.recipe {
                    for ingredient in recipe.ingredients {
                        guard let food = ingredient.foodItem else { skipped += 1; continue }
                        _ = FoodLog.create(
                            mealType: meal.mealType,
                            quantity: ingredient.quantity * item.servingCount,
                            food: food,
                            serving: ingredient.servingSize,
                            timestamp: date,
                            context: modelContext
                        )
                        logged += 1
                    }
                } else if let food = item.foodItem {
                    let serving = item.servingSize ?? food.defaultServing
                    guard serving != nil else { skipped += 1; continue }
                    _ = FoodLog.create(
                        mealType: meal.mealType,
                        quantity: item.servingCount,
                        food: food,
                        serving: serving,
                        timestamp: date,
                        context: modelContext
                    )
                    logged += 1
                }
            }
        }

        try? modelContext.save()
        logResult = .success(logged: logged, skipped: skipped)
        let announcement = skipped > 0
            ? "\(logged) meals logged, \(skipped) skipped"
            : "Day logged successfully"
        UIAccessibility.post(notification: .announcement, argument: announcement)
        try? await Task.sleep(for: .seconds(2))
        logResult = nil
        isLogging = false
    }

    // MARK: - Cluster mutations

    /// Find or create the MealPlanMeal for (targetDate, mealType).
    /// Defaults to this row's date when targetDate is nil.
    /// Secondary FetchDescriptor guard handles SwiftData lazy-load edge case.
    private func findOrCreateMeal(for mealType: MealType, on targetDate: Date? = nil) -> MealPlanMeal {
        let today = Calendar.current.startOfDay(for: targetDate ?? date)

        // Primary: check in-memory relationship
        if let existing = mealPlan.meals.first(where: {
            Calendar.current.isDate($0.date, inSameDayAs: today) && $0.mealType == mealType
        }) {
            return existing
        }

        // Secondary fetch guard (SwiftData lazy-load safety).
        // Runs whenever the in-memory lookup returned nil — covers both the fully-unloaded
        // relationship and the partially-loaded case (some meals faulted in, others not).
        // IMPORTANT: Do NOT use #Predicate with relationship traversal — unreliable at runtime.
        // Fetch all MealPlanMeal records and filter in memory using PersistentIdentifier.
        let planID = mealPlan.persistentModelID
        let stored = (try? modelContext.fetch(FetchDescriptor<MealPlanMeal>())) ?? []
        if let existing = stored
            .filter({ $0.mealPlan?.persistentModelID == planID })
            .first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) && $0.mealType == mealType }) {
            return existing
        }

        let meal = MealPlanMeal(mealPlan: mealPlan, date: today, mealType: mealType)
        modelContext.insert(meal)
        // Explicitly append so SwiftData updates the in-memory relationship immediately,
        // triggering a re-render before the next save/context merge.
        mealPlan.meals.append(meal)
        return meal
    }

    private func addItemToMeal(mealType: MealType, recipe: Recipe?, food: FoodItem?, note: String?, serving: ServingSize?, count: Double) {
        let meal = findOrCreateMeal(for: mealType)
        let item = MealPlanMealItem(meal: meal)
        item.recipe = recipe
        item.foodItem = food
        item.note = note
        item.servingSize = serving
        item.servingCount = count
        modelContext.insert(item)
        // Explicitly append so SwiftData updates the in-memory relationship immediately.
        meal.items.append(item)
        try? modelContext.save()
    }

    /// Deep-copies the current dinner meal (all items) to another day in the same week.
    /// If the target day already has a dinner meal, items are appended to it.
    private func copyMealToDay(_ meal: MealPlanMeal, to targetDay: Date) {
        let targetMeal = findOrCreateMeal(for: meal.mealType, on: targetDay)
        // Copy the user-set name if the target has no name yet
        if targetMeal.name == nil {
            targetMeal.name = meal.name
        }
        for item in meal.items {
            let newItem = MealPlanMealItem(meal: targetMeal)
            newItem.recipe = item.recipe
            newItem.foodItem = item.foodItem
            newItem.note = item.note
            newItem.servingSize = item.servingSize
            newItem.servingCount = item.servingCount
            modelContext.insert(newItem)
            targetMeal.items.append(newItem)
        }
        try? modelContext.save()
    }

    private func saveClusterName() {
        let trimmed = clusterNameText.trimmingCharacters(in: .whitespaces)
        if let meal = dinnerMeal {
            meal.name = trimmed.isEmpty ? nil : trimmed
            try? modelContext.save()
        }
        isEditingClusterName = false
    }
}
