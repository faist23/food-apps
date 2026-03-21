//
//  RecipeEditorView.swift
//  RecipeCard
//

import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import BiteLedgerCore

struct RecipeEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let existingRecipe: Recipe?

    @State private var name: String
    @State private var servingsYield: String
    @State private var sourceURL: String
    @State private var directions: [String]
    @State private var ingredients: [RecipeIngredient]
    @State private var newDirection: String = ""
    @State private var showingIngredientPicker = false

    // Metadata fields (model fields already exist — pure UI addition)
    @State private var recipeDesc: String
    @State private var prepMinutes: String
    @State private var cookMinutes: String
    @State private var totalMinutes: String
    @State private var recipeCategory: String
    @State private var recipeCuisine: String
    /// Tracks the last auto-computed total so we don't clobber a user's manual edit.
    @State private var prevAutoTotal: Int

    // Photo editing
    @State private var currentImageURL: String?       // existing saved URL (remote or file://)
    @State private var pendingImage: UIImage?         // new selection — written to disk on save
    @State private var photoItem: PhotosPickerItem?
    @State private var showingCamera = false

    static let categoryOptions = [
        "Appetizer", "Breakfast", "Bread", "Dessert", "Drink",
        "Main Dish", "Salad", "Sauce", "Side Dish", "Snack", "Soup"
    ]

    static let cuisineOptions = [
        "American", "BBQ", "British", "Caribbean", "Chinese",
        "French", "Greek", "Indian", "Italian", "Japanese",
        "Korean", "Mediterranean", "Mexican", "Middle Eastern",
        "Spanish", "Thai", "Vietnamese"
    ]

    init(recipe: Recipe?) {
        self.existingRecipe = recipe
        _name             = State(initialValue: recipe?.name ?? "")
        _servingsYield    = State(initialValue: recipe.map { String(Int($0.servingsYield)) } ?? "1")
        _sourceURL        = State(initialValue: recipe?.sourceURL ?? "")
        _directions       = State(initialValue: recipe?.directions ?? [])
        _ingredients      = State(initialValue: recipe?.sortedIngredients ?? [])
        _currentImageURL  = State(initialValue: recipe?.imageURL)
        _recipeDesc       = State(initialValue: recipe?.recipeDescription ?? "")
        _prepMinutes      = State(initialValue: recipe?.prepMinutes.map(String.init) ?? "")
        _cookMinutes      = State(initialValue: recipe?.cookMinutes.map(String.init) ?? "")
        _totalMinutes     = State(initialValue: recipe?.totalMinutes.map(String.init) ?? "")
        _recipeCategory   = State(initialValue: recipe?.recipeCategory ?? "")
        _recipeCuisine    = State(initialValue: recipe?.recipeCuisine ?? "")
        let p = recipe?.prepMinutes ?? 0
        let c = recipe?.cookMinutes ?? 0
        _prevAutoTotal    = State(initialValue: p + c)
    }

    private var totals: NutritionCalculator.Result {
        ingredients.reduce(.zero) { acc, ing in
            guard let food = ing.foodItem else { return acc }
            return acc + NutritionCalculator.calculate(food: food, serving: ing.servingSize, quantity: ing.quantity)
        }
    }

    private var perServing: NutritionCalculator.Result {
        let d = Double(Int(servingsYield) ?? 1)
        return NutritionCalculator.Result(
            calories: totals.calories / d, protein: totals.protein / d,
            carbs: totals.carbs / d, fat: totals.fat / d,
            fiber: totals.fiber.map { $0 / d }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Photo
                Section("Photo") {
                    // Preview
                    Group {
                        if let img = pendingImage {
                            Image(uiImage: img)
                                .resizable().scaledToFill()
                        } else if currentImageURL != nil {
                            RecipePhotoView(urlString: currentImageURL, contentMode: .fill) {
                                Color.secondary.opacity(0.1)
                            }
                        } else {
                            ZStack {
                                Color.secondary.opacity(0.1)
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: 180)
                    .clipped()
                    .listRowInsets(EdgeInsets())

                    // Actions
                    HStack(spacing: 0) {
                        Button {
                            showingCamera = true
                        } label: {
                            Label("Camera", systemImage: "camera")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderless)

                        Divider().frame(height: 32)

                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("Library", systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderless)

                        if pendingImage != nil || currentImageURL != nil {
                            Divider().frame(height: 32)
                            Button(role: .destructive) {
                                pendingImage = nil
                                currentImageURL = nil
                            } label: {
                                Label("Remove", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                Section("Recipe Info") {
                    TextField("Name", text: $name)
                    HStack {
                        Text("Servings")
                        Spacer()
                        TextField("1", text: $servingsYield)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }
                    TextField("Source URL (optional)", text: $sourceURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }

                Section("Details") {
                    TextField("Description (optional)", text: $recipeDesc, axis: .vertical)
                        .lineLimit(2...4)
                    HStack {
                        Text("Prep Time")
                        Spacer()
                        TextField("0", text: $prepMinutes)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("min")
                            .foregroundStyle(Color("TextSecondary"))
                    }
                    HStack {
                        Text("Cook Time")
                        Spacer()
                        TextField("0", text: $cookMinutes)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("min")
                            .foregroundStyle(Color("TextSecondary"))
                    }
                    HStack {
                        Text("Total Time")
                        Spacer()
                        TextField("0", text: $totalMinutes)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("min")
                            .foregroundStyle(Color("TextSecondary"))
                    }
                    Picker("Category", selection: $recipeCategory) {
                        Text("None").tag("")
                        ForEach(RecipeEditorView.categoryOptions, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                    .pickerStyle(.menu)
                    Picker("Cuisine", selection: $recipeCuisine) {
                        Text("None").tag("")
                        ForEach(RecipeEditorView.cuisineOptions, id: \.self) { cuisine in
                            Text(cuisine).tag(cuisine)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Ingredients") {
                    ForEach(ingredients) { ing in
                        IngredientEditorRow(ingredient: ing)
                    }
                    .onDelete { offsets in
                        for i in offsets { modelContext.delete(ingredients[i]) }
                        ingredients.remove(atOffsets: offsets)
                    }
                    .onMove { from, to in ingredients.move(fromOffsets: from, toOffset: to) }
                    Button {
                        showingIngredientPicker = true
                    } label: {
                        Label("Add Ingredient", systemImage: "plus.circle.fill")
                    }
                }

                if !ingredients.isEmpty {
                    Section("Nutrition Per Serving") {
                        NutritionRow(label: "Calories", value: perServing.calories, unit: "")
                        NutritionRow(label: "Protein",  value: perServing.protein,  unit: "g")
                        NutritionRow(label: "Carbs",    value: perServing.carbs,    unit: "g")
                        NutritionRow(label: "Fat",      value: perServing.fat,      unit: "g")
                        if let fiber = perServing.fiber {
                            NutritionRow(label: "Fiber", value: fiber, unit: "g")
                        }
                    }
                }

                Section("Directions") {
                    ForEach(Array(directions.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(i + 1).").foregroundStyle(.secondary)
                            Text(step)
                        }
                    }
                    .onDelete { directions.remove(atOffsets: $0) }
                    .onMove { directions.move(fromOffsets: $0, toOffset: $1) }

                    HStack {
                        TextField("Add a step…", text: $newDirection, axis: .vertical)
                            .lineLimit(2...4)
                        Button {
                            let trimmed = newDirection.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            directions.append(trimmed)
                            newDirection = ""
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newDirection.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle(existingRecipe == nil ? "New Recipe" : "Edit Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showingIngredientPicker) {
                IngredientPickerView { food, serving, qty in
                    let ing = RecipeIngredient(quantity: qty, sortOrder: ingredients.count)
                    ing.foodItem = food
                    ing.servingSize = serving
                    modelContext.insert(ing)
                    ingredients.append(ing)
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                EditorCameraPickerView { image in
                    pendingImage = image
                    currentImageURL = nil
                }
                .ignoresSafeArea()
            }
            .onChange(of: prepMinutes) { _, _ in autoUpdateTotal() }
            .onChange(of: cookMinutes) { _, _ in autoUpdateTotal() }
            .onChange(of: photoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        pendingImage = image
                        currentImageURL = nil
                    }
                    photoItem = nil
                }
            }
        }
    }

    /// Auto-fills Total when Prep or Cook changes, unless the user has manually set Total
    /// to a value different from the previously auto-computed sum.
    private func autoUpdateTotal() {
        let p = Int(prepMinutes) ?? 0
        let c = Int(cookMinutes) ?? 0
        let newSum = p + c
        let currentTotal = Int(totalMinutes)
        if totalMinutes.isEmpty || currentTotal == prevAutoTotal {
            totalMinutes = newSum > 0 ? String(newSum) : ""
            prevAutoTotal = newSum
        }
    }

    private func save() {
        let yield = Double(Int(servingsYield) ?? 1)
        let url = sourceURL.trimmingCharacters(in: .whitespaces).isEmpty ? nil : sourceURL.trimmingCharacters(in: .whitespaces)

        // Resolve the final imageURL:
        // - New photo selected: write to disk, delete the old local file if any.
        // - Photo cleared (both nil): delete the old local file if any.
        // - No change: keep currentImageURL as-is.
        let resolvedImageURL: String?
        if let newImage = pendingImage {
            if let old = existingRecipe?.imageURL { RecipeImportService.deleteLocalImage(urlString: old) }
            let data = newImage.jpegData(compressionQuality: 0.82)
            resolvedImageURL = data.flatMap { RecipeImportService.saveImageDataLocally($0, appGroupIdentifier: "group.com.ridepro.biteledger") }
        } else if currentImageURL == nil, let old = existingRecipe?.imageURL {
            // User cleared the photo
            RecipeImportService.deleteLocalImage(urlString: old)
            resolvedImageURL = nil
        } else {
            resolvedImageURL = currentImageURL
        }

        let descTrimmed = recipeDesc.trimmingCharacters(in: .whitespaces)

        if let recipe = existingRecipe {
            recipe.name = name.trimmingCharacters(in: .whitespaces)
            recipe.servingsYield = yield
            recipe.sourceURL = url
            recipe.directions = directions
            recipe.imageURL = resolvedImageURL
            recipe.recipeDescription = descTrimmed.isEmpty ? nil : descTrimmed
            recipe.prepMinutes       = Int(prepMinutes)
            recipe.cookMinutes       = Int(cookMinutes)
            recipe.totalMinutes      = Int(totalMinutes)
            recipe.recipeCategory    = recipeCategory.isEmpty ? nil : recipeCategory
            recipe.recipeCuisine     = recipeCuisine.trimmingCharacters(in: .whitespaces).isEmpty ? nil : recipeCuisine.trimmingCharacters(in: .whitespaces)
            for (i, ing) in ingredients.enumerated() { ing.sortOrder = i; ing.recipe = recipe }
        } else {
            let recipe = Recipe(
                name: name.trimmingCharacters(in: .whitespaces),
                servingsYield: yield,
                sourceURL: url,
                directions: directions
            )
            recipe.imageURL          = resolvedImageURL
            recipe.recipeDescription = descTrimmed.isEmpty ? nil : descTrimmed
            recipe.prepMinutes       = Int(prepMinutes)
            recipe.cookMinutes       = Int(cookMinutes)
            recipe.totalMinutes      = Int(totalMinutes)
            recipe.recipeCategory    = recipeCategory.isEmpty ? nil : recipeCategory
            recipe.recipeCuisine     = recipeCuisine.trimmingCharacters(in: .whitespaces).isEmpty ? nil : recipeCuisine.trimmingCharacters(in: .whitespaces)
            for (i, ing) in ingredients.enumerated() { ing.sortOrder = i; ing.recipe = recipe }
            modelContext.insert(recipe)
        }
        try? modelContext.save()
        dismiss()
    }
}

private struct IngredientEditorRow: View {
    @Bindable var ingredient: RecipeIngredient
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(ingredient.displayLabel).font(.body)
                if ingredient.rawText != nil, let food = ingredient.foodItem {
                    Text("→ \(food.name)").font(.caption).foregroundStyle(.secondary)
                } else if ingredient.rawText == nil {
                    Text(ingredient.servingSize?.label ?? "1 serving").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            // Only show quantity for manually-added ingredients (no rawText).
            // URL-imported / OCR ingredients store quantity as an internal gram-based
            // serving count — meaningless to the user. rawText is their source of truth.
            if ingredient.foodItem != nil && ingredient.rawText == nil {
                TextField("Qty", value: $ingredient.quantity, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
            }
        }
    }
}

private struct NutritionRow: View {
    let label: String; let value: Double; let unit: String
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(Int(value))\(unit)").foregroundStyle(.secondary)
        }
    }
}

// MARK: - Camera picker

private struct EditorCameraPickerView: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void
        init(onImage: @escaping (UIImage) -> Void) { self.onImage = onImage }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)
            if let img = info[.originalImage] as? UIImage { onImage(img) }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
