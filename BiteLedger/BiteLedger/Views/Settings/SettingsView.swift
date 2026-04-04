//
//  SettingsView.swift
//  BiteLedger
//
//  Created by Craig Faist on 2/16/26.
//


import SwiftUI
import SwiftData
import BiteLedgerCore

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [UserPreferences]

    @State private var showingImport = false
    @State private var showingCleanupConfirmation = false
    @State private var cleanupResultMessage = ""
    @State private var showingCleanupResult = false
    @State private var showingBackfillConfirmation = false
    @State private var backfillResultMessage = ""
    @State private var showingBackfillResult = false
    @State private var isBackfilling = false
    @State private var pinnedNutrient: Nutrient?
    @State private var showMacroBalance: Bool = true
    @State private var goals: [String: NutrientGoal] = [:]
    @State private var editingNutrient: Nutrient?

    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Show Macro Balance Tile", isOn: $showMacroBalance)
                        .onChange(of: showMacroBalance) { _, _ in
                            updatePreferences()
                        }
                    
                    Picker("Pin Nutrient to Dashboard", selection: $pinnedNutrient) {
                        Text("None").tag(nil as Nutrient?)
                        ForEach(Nutrient.pinnableNutrients) { nutrient in
                            Text(nutrient.rawValue).tag(nutrient as Nutrient?)
                        }
                    }
                    .onChange(of: pinnedNutrient) { _, _ in
                        updatePreferences()
                    }
                } header: {
                    Text("Dashboard")
                } footer: {
                    Text("The macro balance tile shows your protein/carbs/fat breakdown. Choose an additional nutrient for the 5th tile.")
                }
                
                Section {
                    // Always show Big 4
                    GoalRow(nutrient: .calories, goals: $goals, onUpdate: updatePreferences)
                    GoalRow(nutrient: .protein, goals: $goals, onUpdate: updatePreferences)
                    GoalRow(nutrient: .carbs, goals: $goals, onUpdate: updatePreferences)
                    GoalRow(nutrient: .fat, goals: $goals, onUpdate: updatePreferences)
                    
                    // Show 5th slot if nutrient is pinned
                    if let pinned = pinnedNutrient {
                        GoalRow(nutrient: pinned, goals: $goals, onUpdate: updatePreferences)
                    }
                } header: {
                    Text("Goals")
                } footer: {
                    Text("Set goals for any nutrients on your dashboard. Progress bars will appear automatically.")
                }
                
                Section {
                    NavigationLink {
                        MyFoodsManagementView()
                    } label: {
                        HStack {
                            Image(systemName: "fork.knife")
                                .foregroundStyle(.blue)
                            Text("My Foods")
                                .foregroundStyle(.primary)
                        }
                    }
                    
                    NavigationLink {
                        BackupRestoreView()
                    } label: {
                        HStack {
                            Image(systemName: "externaldrive.fill")
                                .foregroundStyle(Color("BrandPrimary"))
                            Text("Backup & Restore")
                                .foregroundStyle(.primary)
                        }
                    }

                    NavigationLink {
                        LoseItEnrichmentView()
                    } label: {
                        HStack {
                            Image(systemName: "sparkles.rectangle.stack.fill")
                                .foregroundStyle(.indigo)
                            Text("Import LoseIt with Micronutrients")
                                .foregroundStyle(.primary)
                        }
                    }

                    Button {
                        showingCleanupConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(.purple)
                            Text("Clean Up Duplicate Foods")
                                .foregroundStyle(.primary)
                        }
                    }

                    Button {
                        showingBackfillConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "wand.and.sparkles")
                                .foregroundStyle(.teal)
                            Text("Backfill Micronutrients in Logs")
                                .foregroundStyle(.primary)
                        }
                    }

                } header: {
                    Text("Data")
                }
                
                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                loadPreferences()
            }
            .alert("Clean Up Duplicates?", isPresented: $showingCleanupConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clean Up", role: .destructive) {
                    cleanUpDuplicates()
                }
            } message: {
                Text("This will merge duplicate food items with the same barcode. All food logs will be updated to point to a single entry.")
            }
            .alert("Cleanup Complete", isPresented: $showingCleanupResult) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(cleanupResultMessage)
            }
            .alert("Backfill Micronutrients?", isPresented: $showingBackfillConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Backfill") {
                    backfillMicronutrients()
                }
            } message: {
                Text("This fills in missing micronutrient values (vitamins, minerals, caffeine) in your food logs using each log's linked food item. Calories, protein, carbs, and fat are never changed. Use this after running the LoseIt enrichment tool.")
            }
            .alert("Backfill Complete", isPresented: $showingBackfillResult) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(backfillResultMessage)
            }
            .overlay {
                if isBackfilling {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        VStack(spacing: 20) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            Text("Backfilling micronutrients...")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                        .padding(40)
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(20)
                    }
                }
            }
        }
    }
    
    private func loadPreferences() {
        if let prefs = preferences.first {
            pinnedNutrient = prefs.pinnedNutrient.flatMap { Nutrient(rawValue: $0) }
            showMacroBalance = prefs.showMacroBalanceTile ?? true // Default to true if nil
            goals = prefs.goals
        } else {
            // Create default preferences
            let newPrefs = UserPreferences()
            modelContext.insert(newPrefs)
            try? modelContext.save()
        }
    }
    
    private func updatePreferences() {
        if let prefs = preferences.first {
            prefs.pinnedNutrient = pinnedNutrient?.rawValue
            prefs.showMacroBalanceTile = showMacroBalance
            prefs.goals = goals
            try? modelContext.save()
        } else {
            let newPrefs = UserPreferences(
                pinnedNutrient: pinnedNutrient?.rawValue,
                showMacroBalanceTile: showMacroBalance
            )
            newPrefs.goals = goals
            modelContext.insert(newPrefs)
            try? modelContext.save()
        }
    }
    
    private func backfillMicronutrients() {
        isBackfilling = true

        let backfillContainer = modelContext.container
        Task {
            let updatedCount = await Task.detached(priority: .userInitiated) { () -> Int in
                let ctx = ModelContext(backfillContainer)

                let descriptor = FetchDescriptor<FoodLog>()
                guard let logs = try? ctx.fetch(descriptor) else {
                    return -1
                }

                var count = 0

                for log in logs {
                    guard let food = log.foodItem else { continue }

                    let n = NutritionCalculator.calculate(
                        food: food,
                        serving: log.servingSize ?? food.defaultServing,
                        quantity: log.quantity
                    )

                    var changed = false
                    if log.fiberAtLogTime == nil,          let v = n.fiber          { log.fiberAtLogTime = v;          changed = true }
                    if log.sugarAtLogTime == nil,          let v = n.sugar          { log.sugarAtLogTime = v;          changed = true }
                    if log.saturatedFatAtLogTime == nil,   let v = n.saturatedFat   { log.saturatedFatAtLogTime = v;   changed = true }
                    if log.transFatAtLogTime == nil,       let v = n.transFat       { log.transFatAtLogTime = v;       changed = true }
                    if log.monounsaturatedFatAtLogTime == nil, let v = n.monounsaturatedFat { log.monounsaturatedFatAtLogTime = v; changed = true }
                    if log.polyunsaturatedFatAtLogTime == nil, let v = n.polyunsaturatedFat { log.polyunsaturatedFatAtLogTime = v; changed = true }
                    if log.sodiumAtLogTime == nil,         let v = n.sodium         { log.sodiumAtLogTime = v;         changed = true }
                    if log.cholesterolAtLogTime == nil,    let v = n.cholesterol    { log.cholesterolAtLogTime = v;    changed = true }
                    if log.potassiumAtLogTime == nil,      let v = n.potassium      { log.potassiumAtLogTime = v;      changed = true }
                    if log.calciumAtLogTime == nil,        let v = n.calcium        { log.calciumAtLogTime = v;        changed = true }
                    if log.ironAtLogTime == nil,           let v = n.iron           { log.ironAtLogTime = v;           changed = true }
                    if log.magnesiumAtLogTime == nil,      let v = n.magnesium      { log.magnesiumAtLogTime = v;      changed = true }
                    if log.zincAtLogTime == nil,           let v = n.zinc           { log.zincAtLogTime = v;           changed = true }
                    if log.vitaminAAtLogTime == nil,       let v = n.vitaminA       { log.vitaminAAtLogTime = v;       changed = true }
                    if log.vitaminCAtLogTime == nil,       let v = n.vitaminC       { log.vitaminCAtLogTime = v;       changed = true }
                    if log.vitaminDAtLogTime == nil,       let v = n.vitaminD       { log.vitaminDAtLogTime = v;       changed = true }
                    if log.vitaminEAtLogTime == nil,       let v = n.vitaminE       { log.vitaminEAtLogTime = v;       changed = true }
                    if log.vitaminKAtLogTime == nil,       let v = n.vitaminK       { log.vitaminKAtLogTime = v;       changed = true }
                    if log.vitaminB6AtLogTime == nil,      let v = n.vitaminB6      { log.vitaminB6AtLogTime = v;      changed = true }
                    if log.vitaminB12AtLogTime == nil,     let v = n.vitaminB12     { log.vitaminB12AtLogTime = v;     changed = true }
                    if log.folateAtLogTime == nil,         let v = n.folate         { log.folateAtLogTime = v;         changed = true }
                    if log.cholineAtLogTime == nil,        let v = n.choline        { log.cholineAtLogTime = v;        changed = true }
                    if log.caffeineAtLogTime == nil,       let v = n.caffeine       { log.caffeineAtLogTime = v;       changed = true }

                    if changed { count += 1 }
                }

                try? ctx.save()
                return count
            }.value

            isBackfilling = false
            if updatedCount == -1 {
                backfillResultMessage = "Failed to fetch food logs."
            } else if updatedCount > 0 {
                backfillResultMessage = "Updated micronutrients in \(updatedCount) food logs."
            } else {
                backfillResultMessage = "No logs needed updating — all micronutrient fields are already populated."
            }
            showingBackfillResult = true
        }
    }

    private func cleanUpDuplicates() {
        var removedCount = 0
        var mergedGroups = 0
        
        // Create a fresh fetch to get current state
        let descriptor = FetchDescriptor<FoodItem>()
        guard let currentFoodItems = try? modelContext.fetch(descriptor) else {
            cleanupResultMessage = "Failed to fetch food items."
            showingCleanupResult = true
            return
        }
        
        // Group foods by barcode
        let groupedByBarcode = Dictionary(grouping: currentFoodItems.filter { $0.barcode != nil && !$0.barcode!.isEmpty }) { $0.barcode! }
        
        // E-5: Fetch all logs once (outside the loop) to avoid O(n²) DB scans.
        let logDescriptor = FetchDescriptor<FoodLog>()
        guard let allLogs = try? modelContext.fetch(logDescriptor) else {
            cleanupResultMessage = "Failed to fetch food logs."
            showingCleanupResult = true
            return
        }
        // Build a lookup map from foodItem.id → [FoodLog] for O(1) access per group.
        var logsByFoodID: [UUID: [FoodLog]] = [:]
        for log in allLogs {
            if let foodID = log.foodItem?.id {
                logsByFoodID[foodID, default: []].append(log)
            }
        }

        // Process each group with duplicates
        for (_, duplicates) in groupedByBarcode where duplicates.count > 1 {
            mergedGroups += 1

            // Keep the most recently added item
            let keeper = duplicates.sorted { $0.dateAdded > $1.dateAdded }.first!

            // Update all logs pointing to duplicates to point to the keeper
            for duplicate in duplicates where duplicate.id != keeper.id {
                for log in logsByFoodID[duplicate.id, default: []] {
                    log.foodItem = keeper
                }
                modelContext.delete(duplicate)
                removedCount += 1
            }
        }
        
        // Save changes
        do {
            try modelContext.save()
            
            // Show result
            if removedCount > 0 {
                cleanupResultMessage = "Removed \(removedCount) duplicate food items across \(mergedGroups) groups."
            } else {
                cleanupResultMessage = "No duplicate food items found."
            }
        } catch {
            cleanupResultMessage = "Error during cleanup: \(error.localizedDescription)"
        }
        
        showingCleanupResult = true
    }
    

}
// MARK: - Goal Row Component

struct GoalRow: View {
    let nutrient: Nutrient
    @Binding var goals: [String: NutrientGoal]
    let onUpdate: () -> Void
    
    @State private var showingEditor = false
    
    private var hasGoal: Bool {
        goals[nutrient.rawValue] != nil
    }
    
    var body: some View {
        if hasGoal, let goal = goals[nutrient.rawValue] {
            Button {
                showingEditor = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(nutrient.rawValue)
                            .foregroundStyle(.primary)
                        Text(goalDescription(for: goal))
                            .font(.caption)
                            .foregroundStyle(Color("TextSecondary"))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color("TextTertiary"))
                }
            }
            .sheet(isPresented: $showingEditor) {
                NavigationStack {
                    GoalEditorView(
                        nutrient: nutrient,
                        goal: goal,
                        onSave: { newGoal in
                            goals[nutrient.rawValue] = newGoal
                            onUpdate()
                        },
                        onDelete: {
                            goals.removeValue(forKey: nutrient.rawValue)
                            onUpdate()
                        }
                    )
                }
            }
        } else {
            Button {
                let defaultValue = nutrient.defaultGoalValue
                let defaultGoal = NutrientGoal(
                    targetValue: defaultValue,
                    goalType: nutrient.defaultGoalType,
                    rangeMax: (nutrient.defaultGoalType == .range) ? defaultValue * 1.1 : nil
                )
                goals[nutrient.rawValue] = defaultGoal
                onUpdate()
            } label: {
                HStack {
                    Text(nutrient.rawValue)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("Set Goal")
                        .font(.subheadline)
                        .foregroundStyle(Color("BrandAccent"))
                }
            }
        }
    }
    
    private func goalDescription(for goal: NutrientGoal) -> String {
        switch goal.goalType {
        case .minimum:
            return "At least \(Int(goal.targetValue)) \(nutrient.unit)"
        case .maximum:
            return "Under \(Int(goal.targetValue)) \(nutrient.unit)"
        case .range:
            let max = goal.rangeMax ?? goal.targetValue * 1.1
            return "\(Int(goal.targetValue))-\(Int(max)) \(nutrient.unit)"
        }
    }
    
}


