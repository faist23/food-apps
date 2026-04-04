//
//  MealEntrySheet.swift
//  BitePlan
//
//  Multi-add sheet for building a dinner cluster in the meal planner.
//
//  Flow:
//    • "ADDED" chip strip — appears after first add to confirm items added so far.
//    • "+ Note" toolbar button — opens an inline text entry above the search tabs.
//      Tap "Add Note" → note persisted, entry clears, sheet stays open.
//    • MealPickerSearchView embedded — three tabs (Recipes, Foods, Meals).
//      Recipe/Food/Meal: tap Add → item persisted, "Added" chip appears, sheet stays open.
//    • "Done" button (nav bar trailing) — dismisses the sheet.
//    • Each onAdd call is immediately persisted by the parent (MealPlanDayRow).
//

import SwiftUI
import SwiftData
import BiteLedgerCore

struct MealEntrySheet: View {
    @Environment(\.dismiss) private var dismiss

    let mealType: MealType
    let date: Date
    /// Called once per item added. Parent persists the item immediately.
    var onAdd: (Recipe?, FoodItem?, String?, ServingSize?, Double) -> Void

    /// Names of items added so far in this session (for the "Added" chip strip).
    @State private var addedItems: [(name: String, isNote: Bool)] = []
    /// Controls inline note entry panel visibility.
    @State private var showNoteEntry = false
    @State private var noteEntryText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Added items strip — shows after first add
                    if !addedItems.isEmpty {
                        addedStrip
                        Divider().padding(.horizontal, 16)
                    }

                    // Inline note entry — shown when "+ Note" toolbar button is tapped
                    if showNoteEntry {
                        noteEntrySection
                        Divider().padding(.horizontal, 16)
                    }

                    // Search tabs (Recipes / Foods / Meals)
                    MealPickerSearchView { recipe, food, note, serving, count in
                        handleAdd(recipe: recipe, food: food, note: note, serving: serving, count: count)
                    }
                }
            }
            .navigationTitle("Add \(mealType.rawValue.capitalized)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showNoteEntry.toggle()
                            if !showNoteEntry { noteEntryText = "" }
                        }
                    } label: {
                        Label("Add Note", systemImage: "pencil")
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline)
                            .foregroundStyle(Color("BrandAccent"))
                    }
                    .accessibilityLabel(showNoteEntry ? "Cancel note" : "Add a note to this meal")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color("BrandAccent"))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Added strip

    private var addedStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ADDED")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color("TextSecondary"))
                .padding(.horizontal, 16)
                .padding(.top, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(addedItems.indices, id: \.self) { idx in
                        let item = addedItems[idx]
                        HStack(spacing: 4) {
                            if item.isNote {
                                Image(systemName: "pencil")
                                    .font(.system(size: 11))
                            }
                            Text(item.name)
                                .font(item.isNote ? .subheadline.italic() : .subheadline)
                                .lineLimit(1)
                        }
                        .foregroundStyle(Color("TextPrimary"))
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Color("SurfaceCard"), in: Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
    }

    // MARK: - Inline note entry

    private var noteEntrySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NOTE")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color("TextSecondary"))
                .padding(.horizontal, 16)
                .padding(.top, 12)

            TextField("Restaurant, reminder, free text…", text: $noteEntryText, axis: .vertical)
                .padding(14)
                .background(Color("SurfaceCard"), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
                .lineLimit(3...6)

            Button {
                let trimmed = noteEntryText.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                handleAdd(recipe: nil, food: nil, note: trimmed, serving: nil, count: 1.0)
                noteEntryText = ""
                withAnimation(.easeInOut(duration: 0.2)) { showNoteEntry = false }
            } label: {
                Text("Add Note")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        noteEntryText.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color("SurfaceCard")
                            : Color("BrandPrimary"),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                    .foregroundStyle(
                        noteEntryText.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color("TextTertiary")
                            : .white
                    )
            }
            .disabled(noteEntryText.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityHint(
                noteEntryText.trimmingCharacters(in: .whitespaces).isEmpty
                    ? "Enter some text to enable this button"
                    : ""
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Actions

    private func handleAdd(recipe: Recipe?, food: FoodItem?, note: String?, serving: ServingSize?, count: Double) {
        onAdd(recipe, food, note, serving, count)
        let name: String
        let isNote: Bool
        if let r = recipe { name = r.name; isNote = false }
        else if let f = food { name = f.name; isNote = false }
        else { name = String((note ?? "").prefix(20)); isNote = true }
        addedItems.append((name: name, isNote: isNote))
    }

}

// MARK: - OccasionSelectionView (internal — also used by MealPickerSearchView Meals tab)
//
// Checklist for picking which items from a past logged occasion to add to the plan.
// Mirrors the MealItemSelectionView pattern from BiteLedger:
//  • All items pre-selected (same as BL default)
//  • Calories shown per item and in the summary bar
//  • User toggles individual items before confirming

struct OccasionSelectionView: View {
    @Environment(\.dismiss) private var dismiss

    let occasion: DinnerOccasion
    /// Called once with the user's selected FoodLog subset on confirm.
    let onConfirm: ([FoodLog]) -> Void

    @State private var selectedIDs: Set<PersistentIdentifier> = []

    private var validLogs: [FoodLog] {
        // Logs are pre-sorted by calories desc in loadRecentOccasions
        occasion.logs.filter { $0.foodItem != nil }
    }

    private var selectedCalories: Int {
        validLogs
            .filter { selectedIDs.contains($0.persistentModelID) }
            .reduce(0) { $0 + Int($1.caloriesAtLogTime) }
    }

    private var selectedCount: Int {
        validLogs.filter { selectedIDs.contains($0.persistentModelID) }.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    ForEach(validLogs, id: \.persistentModelID) { log in
                        let isSelected = selectedIDs.contains(log.persistentModelID)
                        Button {
                            if isSelected {
                                selectedIDs.remove(log.persistentModelID)
                            } else {
                                selectedIDs.insert(log.persistentModelID)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundStyle(isSelected ? Color("BrandAccent") : Color("TextTertiary"))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(log.foodItem?.name ?? "Unknown")
                                        .font(.subheadline)
                                        .foregroundStyle(Color("TextPrimary"))
                                    if let serving = log.servingSize {
                                        Text("\(log.quantityDescription) · \(serving.label)")
                                            .font(.caption)
                                            .foregroundStyle(Color("TextSecondary"))
                                    } else {
                                        Text(log.quantityDescription)
                                            .font(.caption)
                                            .foregroundStyle(Color("TextSecondary"))
                                    }
                                }

                                Spacer()

                                Text("\(Int(log.caloriesAtLogTime)) cal")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(Color("TextSecondary"))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color("SurfacePrimary"))
                    }
                }
                .listStyle(.plain)

                // Summary bar
                HStack {
                    Text(selectedCount == 1 ? "1 item selected" : "\(selectedCount) items selected")
                        .font(.subheadline)
                        .foregroundStyle(Color("TextSecondary"))
                    Spacer()
                    Text("\(selectedCalories) cal")
                        .font(.subheadline.monospacedDigit().bold())
                        .foregroundStyle(Color("TextPrimary"))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color("SurfaceCard"))
                .overlay(alignment: .top) { Divider() }

                Button {
                    let selected = validLogs.filter { selectedIDs.contains($0.persistentModelID) }
                    onConfirm(selected)
                    dismiss()
                } label: {
                    Text("Add to Plan")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            selectedCount == 0
                                ? Color("SurfaceCard")
                                : Color("BrandPrimary"),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .foregroundStyle(selectedCount == 0 ? Color("TextTertiary") : .white)
                }
                .disabled(selectedCount == 0)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color("SurfacePrimary"))
            }
            .navigationTitle(occasion.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color("BrandAccent"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(selectedCount == validLogs.count ? "Deselect All" : "Select All") {
                        if selectedCount == validLogs.count {
                            selectedIDs = []
                        } else {
                            selectedIDs = Set(validLogs.map(\.persistentModelID))
                        }
                    }
                    .foregroundStyle(Color("BrandAccent"))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            // Pre-select all items, same as BiteLedger's MealItemSelectionView
            selectedIDs = Set(validLogs.map(\.persistentModelID))
        }
    }
}
