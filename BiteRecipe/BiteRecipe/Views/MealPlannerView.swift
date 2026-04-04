//
//  MealPlannerView.swift
//  BiteRecipe
//
//  Root view for the "Plan" tab.
//  7-day week planner with collapsible dinner-cluster rows,
//  nutrition preview, and shopping list generation.
//
//  v2 (SchemaV4): uses MealPlanMeal + MealPlanMealItem cluster model.
//  DinnerOccasion history loaded once per week-load, passed to all rows.
//

import SwiftUI
import SwiftData
import BiteLedgerCore

// MARK: - DinnerOccasion

/// Ephemeral struct representing a group of FoodLog records for one meal type on one day.
/// Used for "Recently Made" chips in MealEntrySheet. Not persisted.
struct DinnerOccasion: Identifiable {
    let id = UUID()
    let date: Date
    let mealType: MealType
    let logs: [FoodLog]

    /// Logs are pre-sorted by calories desc; logs[0] is the main dish.
    var displayName: String {
        let names = logs.compactMap { $0.foodItem?.name }
        let dateStr = date.formatted(.dateTime.month(.abbreviated).day())
        guard !names.isEmpty else { return "\(mealType.rawValue.capitalized) · \(dateStr)" }
        if names.count == 1 { return "\(names[0]) · \(dateStr)" }
        return "\(names[0]) +\(names.count - 1) · \(dateStr)"
    }
}

// MARK: - MealPlannerView

struct MealPlannerView: View {
    @Binding var selectedTab: Int
    @Environment(\.modelContext) private var modelContext
    @Environment(ShoppingCart.self) private var shoppingCart

    @State private var weekStart: Date = MealPlan.startOfWeek()
    @State private var currentPlan: MealPlan? = nil
    @State private var planLoadError: Error? = nil
    @State private var showReplaceCartAlert = false
    @State private var showEmptyPlanAlert = false
    @State private var showCopyConfirm = false

    // MARK: - Computed properties

    private var weekDays: [Date] {
        currentPlan?.weekDates() ?? (0..<7).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: weekStart)
        }
    }

    private var weekMeals: [MealPlanMeal] {
        currentPlan?.meals ?? []
    }

    /// Count of days with at least one valid dinner item planned.
    private var dinnerCount: Int {
        weekMeals.filter {
            $0.mealType == .dinner && $0.items.contains(where: \.isValid)
        }.count
    }

    /// Recipe IDs that appear in 3+ dinner slots this week — triggers variety nudge.
    private var repeatedDinnerRecipeIDs: Set<PersistentIdentifier> {
        let dinnerRecipes = weekMeals
            .filter { $0.mealType == .dinner }
            .flatMap { $0.items }
            .compactMap(\.recipe)
        let groups = Dictionary(grouping: dinnerRecipes, by: \.persistentModelID)
        return Set(groups.filter { $0.value.count >= 3 }.keys)
    }

    private var hasValidMeals: Bool {
        weekMeals.contains { $0.items.contains(where: \.isValid) }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if let error = planLoadError {
                    planErrorView(error: error)
                } else if let plan = currentPlan {
                    planView(plan: plan)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color("SurfacePrimary"))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .top) { weekNavigationHeader }
            .safeAreaInset(edge: .bottom) { shoppingListButton }
        }
        .task(id: weekStart) {
            loadOrCreatePlan()
        }
        .alert("Replace current shopping list?", isPresented: $showReplaceCartAlert) {
            Button("Replace", role: .destructive) { generateShoppingList() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will replace the current shopping list with items from your meal plan.")
        }
        .alert("Your plan is empty", isPresented: $showEmptyPlanAlert) {
            Button("OK") { }
        } message: {
            Text("Add meals to the plan before generating a shopping list.")
        }
        .alert("Copy to next week?", isPresented: $showCopyConfirm) {
            Button("Replace", role: .destructive) { copyToNextWeek() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Replace next week's plan with a copy of this week's meals?")
        }
    }

    // MARK: - Plan view

    private func planView(plan: MealPlan) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !hasValidMeals {
                    emptyWeekBanner
                }
                ForEach(weekDays, id: \.self) { day in
                    MealPlanDayRow(
                        date: day,
                        mealPlan: plan,
                        repeatedDinnerRecipeIDs: repeatedDinnerRecipeIDs
                    )
                    Divider()
                }
            }
        }
        .background(Color("SurfacePrimary"))
    }

    // MARK: - Empty week banner

    private var emptyWeekBanner: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 28))
                .foregroundStyle(Color("BrandAccent"))
            Text("Plan your week")
                .font(.headline)
                .foregroundStyle(Color("TextPrimary"))
            Text("Add your dinners below, then generate a shopping list in one tap.")
                .font(.subheadline)
                .foregroundStyle(Color("TextSecondary"))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
    }

    // MARK: - Plan load error

    private func planErrorView(error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("Unable to load plan")
                .font(.headline)
                .foregroundStyle(Color("TextPrimary"))
            Button("Retry") {
                planLoadError = nil
                loadOrCreatePlan()
            }
            .foregroundStyle(Color("BrandAccent"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("SurfacePrimary"))
    }

    // MARK: - Week navigation header (sticky)

    private var weekNavigationHeader: some View {
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                Button {
                    weekStart = MealPlan.startOfWeek(
                        for: Calendar.current.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
                    )
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color("BrandAccent"))
                        .frame(width: 44, height: 44)
                }

                Text(weekHeaderTitle)
                    .font(.headline)
                    .foregroundStyle(Color("TextPrimary"))
                    .frame(maxWidth: .infinity)

                Button {
                    weekStart = MealPlan.startOfWeek(
                        for: Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
                    )
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color("BrandAccent"))
                        .frame(width: 44, height: 44)
                }
            }
            Text("\(dinnerCount) of 7 dinners planned")
                .font(.caption)
                .foregroundStyle(Color("TextSecondary"))
        }
        .padding(.bottom, 4)
        .background(Color("SurfacePrimary"))
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Shopping list button

    private var shoppingListButton: some View {
        Button {
            guard hasValidMeals else { showEmptyPlanAlert = true; return }
            if shoppingCart.isEmpty {
                generateShoppingList()
            } else {
                showReplaceCartAlert = true
            }
        } label: {
            Label("Generate Shopping List", systemImage: "cart")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color("BrandPrimary"), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(Color("SurfacePrimary"))
        .accessibilityLabel("Generate shopping list from this week's plan")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("Plan")
                .font(.headline)
                .foregroundStyle(Color("TextPrimary"))
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button {
                    checkAndCopyToNextWeek()
                } label: {
                    Label("Copy to next week", systemImage: "doc.on.doc")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(Color("BrandAccent"))
            }
        }
    }

    private var weekHeaderTitle: String {
        weekStart.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: - Actions

    private func generateShoppingList() {
        shoppingCart.populateFromMealPlan(meals: weekMeals)
        selectedTab = 2
    }

    private func checkAndCopyToNextWeek() {
        let nextWeekStart = MealPlan.startOfWeek(
            for: Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        )
        let descriptor = FetchDescriptor<MealPlan>(
            predicate: #Predicate { $0.weekStartDate == nextWeekStart }
        )
        let existing = try? modelContext.fetch(descriptor)
        if existing?.first?.meals.isEmpty == false {
            showCopyConfirm = true
        } else {
            copyToNextWeek()
        }
    }

    /// Deep-copies current week's MealPlanMeal + MealPlanMealItem records to next week.
    private func copyToNextWeek() {
        guard let plan = currentPlan else { return }
        let nextWeekStart = MealPlan.startOfWeek(
            for: Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        )

        let descriptor = FetchDescriptor<MealPlan>(
            predicate: #Predicate { $0.weekStartDate == nextWeekStart }
        )
        let nextPlan: MealPlan
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            // Delete all existing next-week meals before inserting copies
            for meal in existing.meals {
                for item in meal.items { modelContext.delete(item) }
                modelContext.delete(meal)
            }
            nextPlan = existing
        } else {
            nextPlan = MealPlan(weekStartDate: nextWeekStart)
            modelContext.insert(nextPlan)
        }

        // Deep copy: MealPlanMeal (date+7) → MealPlanMealItem per item
        for meal in plan.meals {
            let newDate = Calendar.current.date(byAdding: .day, value: 7, to: meal.date) ?? meal.date
            let newMeal = MealPlanMeal(mealPlan: nextPlan, date: newDate, mealType: meal.mealType)
            newMeal.name = meal.name  // preserve user-set cluster name
            modelContext.insert(newMeal)
            for item in meal.items {
                let newItem = MealPlanMealItem(meal: newMeal)
                newItem.recipe = item.recipe
                newItem.foodItem = item.foodItem
                newItem.note = item.note
                newItem.servingSize = item.servingSize
                newItem.servingCount = item.servingCount
                modelContext.insert(newItem)
            }
        }

        try? modelContext.save()
        weekStart = nextWeekStart
    }

    // MARK: - Plan loading

    private func loadOrCreatePlan() {
        let start = weekStart
        let descriptor = FetchDescriptor<MealPlan>(
            predicate: #Predicate { $0.weekStartDate == start }
        )
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                // Clear legacy MealPlanEntry records on first V4 launch
                if !existing.entries.isEmpty {
                    existing.entries.forEach { modelContext.delete($0) }
                    try? modelContext.save()
                }
                currentPlan = existing
            } else {
                let plan = MealPlan(weekStartDate: start)
                modelContext.insert(plan)
                try modelContext.save()
                currentPlan = plan
            }
        } catch {
            planLoadError = error
        }
    }

}
