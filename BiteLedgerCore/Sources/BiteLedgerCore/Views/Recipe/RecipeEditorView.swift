import SwiftUI
import SwiftData
import PhotosUI

// MARK: - RecipeEditorView

public struct RecipeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// nil = creating a new recipe; non-nil = editing an existing one.
    let recipe: Recipe?

    // MARK: Vocabulary (public for external pickers — e.g. RecipeImportReviewView)

    public static let categoryOptions = [
        "Appetizer", "Breakfast", "Bread", "Dessert", "Drink",
        "Main Dish", "Salad", "Sauce", "Side Dish", "Snack", "Soup"
    ]

    public static let cuisineOptions = [
        "American", "BBQ", "British", "Caribbean", "Chinese",
        "French", "Greek", "Indian", "Italian", "Japanese",
        "Korean", "Mediterranean", "Mexican", "Middle Eastern",
        "Spanish", "Thai", "Vietnamese"
    ]

    // MARK: Supporting Types

    public enum NutritionDisplay: String, CaseIterable {
        case perServing   = "Per Serving"
        case wholeRecipe  = "Whole Recipe"
    }

    public struct PendingIngredient: Identifiable {
        public let id: UUID = UUID()
        public let food: FoodItem
        public let serving: ServingSize
        public var quantity: Double
        /// Original recipe text (e.g. "1.5 lbs chicken breast"). Shown instead of qty×serving when set.
        public var rawText: String? = nil
        /// Parsed recipe quantity (e.g. 1.5 for "1.5 lbs"). Stored on RecipeIngredient for future display.
        public var recipeQuantity: Double? = nil
        /// Parsed recipe unit (e.g. "lbs"). Stored on RecipeIngredient for future display.
        public var recipeUnit: String? = nil
    }

    // MARK: Form State

    @State private var recipeName: String
    @State private var servingsYield: Double
    @State private var servingsYieldText: String
    @State private var sourceURL: String
    @State private var directions: [String]

    // Metadata
    @State private var recipeDesc: String
    @State private var prepMinutes: String
    @State private var cookMinutes: String
    @State private var totalMinutes: String
    @State private var recipeCategory: String
    @State private var recipeCuisine: String
    /// Tracks the last auto-computed total so we don't clobber a user's manual edit.
    @State private var prevAutoTotal: Int

    /// Local working copy of the ingredient list. Sourced from the recipe on appear;
    /// written back to the model only when Save is tapped.
    @State private var pendingIngredients: [PendingIngredient] = []

    // MARK: UI State

    @State private var showIngredientPicker = false
    @State private var showImportSheet = false
    @State private var unmatchedHints: [ImportedRecipeData.UnmatchedHint] = []
    @State private var hintBeingSearched: ImportedRecipeData.UnmatchedHint? = nil
    @State private var nutritionDisplay: NutritionDisplay = .perServing
    /// Per-serving nutrition imported from the recipe website (Schema.org). When set,
    /// this takes priority over ingredient-based calculation.
    @State private var importedNutrition: RecipeNutrition? = nil
    @State private var showAddDirection = false
    @State private var showEditDirection = false
    @State private var editingDirectionIndex: Int? = nil
    @State private var editingDirectionText: String = ""
    @State private var newDirectionText: String = ""

    // Scale
    @State private var scaleMultiplier: Double = 1.0
    @State private var baseServingsYield: Double
    @State private var baseIngredientQuantities: [UUID: Double] = [:]

    // Photo
    @State private var currentImageURL: String? = nil
    @State private var pendingImage: UIImage? = nil
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var showCamera = false
    @State private var showPhotoOptions = false
    @State private var showPhotoLibrary = false

    // MARK: - Init

    public init(recipe: Recipe?) {
        self.recipe = recipe
        let yield = recipe?.servingsYield ?? 4.0
        _recipeName        = State(initialValue: recipe?.name ?? "")
        _servingsYield     = State(initialValue: yield)
        _servingsYieldText = State(initialValue: yield.truncatingRemainder(dividingBy: 1) == 0
                                   ? String(Int(yield))
                                   : String(format: "%.1f", yield))
        _sourceURL         = State(initialValue: recipe?.sourceURL ?? "")
        _directions        = State(initialValue: recipe?.directions ?? [])
        _importedNutrition = State(initialValue: recipe?.importedNutrition)
        _recipeDesc        = State(initialValue: recipe?.recipeDescription ?? "")
        _prepMinutes       = State(initialValue: recipe?.prepMinutes.map(String.init) ?? "")
        _cookMinutes       = State(initialValue: recipe?.cookMinutes.map(String.init) ?? "")
        _totalMinutes      = State(initialValue: recipe?.totalMinutes.map(String.init) ?? "")
        _recipeCategory    = State(initialValue: recipe?.recipeCategory ?? "")
        _recipeCuisine     = State(initialValue: recipe?.recipeCuisine ?? "")
        let p = recipe?.prepMinutes ?? 0
        let c = recipe?.cookMinutes ?? 0
        _prevAutoTotal       = State(initialValue: p + c)
        _baseServingsYield   = State(initialValue: yield)
        _currentImageURL     = State(initialValue: recipe?.imageURL)
    }

    // MARK: - Computed

    private var isValid: Bool {
        !recipeName.trimmingCharacters(in: .whitespaces).isEmpty && servingsYield > 0
    }

    private var calculatedPerServing: NutritionCalculator.Result {
        if let n = importedNutrition {
            return NutritionCalculator.Result(
                calories:     n.calories,
                protein:      n.protein,
                carbs:        n.carbs,
                fat:          n.fat,
                fiber:        n.fiber,
                sugar:        n.sugar,
                saturatedFat: n.saturatedFat,
                sodium:       n.sodium,
                cholesterol:  n.cholesterol,
                potassium:    n.potassium,
                calcium:      n.calcium,
                iron:         n.iron,
                vitaminA:     n.vitaminA,
                vitaminC:     n.vitaminC
            )
        }
        guard servingsYield > 0 else { return .zero }
        let total = pendingIngredients.reduce(NutritionCalculator.Result.zero) { sum, pending in
            sum + NutritionCalculator.preview(
                food: pending.food,
                serving: pending.serving,
                quantity: pending.quantity
            )
        }
        return total.scaled(by: 1.0 / servingsYield)
    }

    private var displayedNutrition: NutritionCalculator.Result {
        switch nutritionDisplay {
        case .perServing:  return calculatedPerServing
        case .wholeRecipe: return calculatedPerServing.scaled(by: servingsYield)
        }
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    photoCard
                    basicInfoCard
                    detailsCard
                    ingredientsCard
                    directionsCard
                    nutritionLabelCard
                    if recipe != nil { metadataCard }
                }
                .padding()
            }
            .background(Color.surfacePrimary)
            .navigationTitle(recipe == nil ? "New Recipe" : "Edit Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showImportSheet = true
                    } label: {
                        Label("Import from Web", systemImage: "link")
                    }
                    .foregroundStyle(Color.brandAccent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveChanges() }
                        .disabled(!isValid)
                        .fontWeight(.semibold)
                }
            }
            .onAppear { loadIngredientsFromRecipe() }
            .onChange(of: prepMinutes) { _, _ in autoUpdateTotal() }
            .onChange(of: cookMinutes) { _, _ in autoUpdateTotal() }
            .onChange(of: scaleMultiplier) { _, newScale in
                for i in pendingIngredients.indices {
                    let base = baseIngredientQuantities[pendingIngredients[i].id] ?? pendingIngredients[i].quantity
                    pendingIngredients[i].quantity = base * newScale
                }
                let scaled = baseServingsYield * newScale
                servingsYield = scaled
                servingsYieldText = scaled.truncatingRemainder(dividingBy: 1) == 0
                    ? String(Int(scaled)) : String(format: "%.1f", scaled)
            }
            .sheet(isPresented: $showIngredientPicker, onDismiss: { hintBeingSearched = nil }) {
                RecipeIngredientPickerView(
                    initialSearch:   hintBeingSearched?.searchTerm ?? "",
                    initialQuantity: hintBeingSearched?.quantity   ?? 1.0
                ) { food, serving, quantity in
                    // quantity from picker is treated as the base (1x) amount;
                    // apply current scale immediately so it matches the rest of the list.
                    var ingredient = PendingIngredient(food: food, serving: serving, quantity: quantity)
                    baseIngredientQuantities[ingredient.id] = quantity
                    ingredient.quantity = quantity * scaleMultiplier
                    pendingIngredients.append(ingredient)
                    if let hint = hintBeingSearched {
                        unmatchedHints.removeAll { $0.id == hint.id }
                    }
                    hintBeingSearched = nil
                }
            }
            .sheet(isPresented: $showImportSheet) {
                EditorURLImportView { imported in
                    applyImport(imported)
                }
            }
            .sheet(isPresented: $showAddDirection) {
                addDirectionSheet
            }
            .sheet(isPresented: $showEditDirection) {
                editDirectionSheet
            }
            .sheet(isPresented: $showCamera) {
                EditorCameraPickerView { image in
                    pendingImage = image
                    currentImageURL = nil
                }
            }
            .photosPicker(isPresented: $showPhotoLibrary, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        pendingImage = img
                        currentImageURL = nil
                    }
                }
            }
            .confirmationDialog("Recipe Photo", isPresented: $showPhotoOptions, titleVisibility: .hidden) {
                Button("Choose from Library") { showPhotoLibrary = true }
                Button("Take Photo") { showCamera = true }
                if pendingImage != nil || currentImageURL != nil {
                    Button("Remove Photo", role: .destructive) {
                        pendingImage = nil
                        currentImageURL = nil
                    }
                }
            }
        }
    }

    // MARK: - Card: Photo

    private var photoCard: some View {
        ElevatedCard(padding: 0, cornerRadius: 20) {
            ZStack(alignment: .topTrailing) {
                if let img = pendingImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .clipped()
                } else if let urlStr = currentImageURL, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Color.surfaceCard.frame(height: 200)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipped()
                } else {
                    Button { showPhotoOptions = true } label: {
                        ZStack {
                            Color.surfaceCard
                                .frame(maxWidth: .infinity)
                                .frame(height: 140)
                            VStack(spacing: 8) {
                                Image(systemName: "camera.fill")
                                    .font(.title2)
                                    .foregroundStyle(Color.textTertiary)
                                Text("Add Photo")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                if pendingImage != nil || currentImageURL != nil {
                    HStack(spacing: 6) {
                        Button { showPhotoOptions = true } label: {
                            Image(systemName: "pencil.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.black.opacity(0.35))
                        }
                        Button {
                            pendingImage = nil
                            currentImageURL = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.black.opacity(0.35))
                        }
                    }
                    .padding(10)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: - Card: Basic Info

    private var basicInfoCard: some View {
        ElevatedCard(padding: 16, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recipe Details")
                    .font(.headline)
                    .foregroundStyle(Color.textSecondary)

                TextField("Recipe Name", text: $recipeName)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)

                HStack {
                    Text("Makes")
                        .font(.subheadline)
                    Spacer()
                    TextField("4", text: $servingsYieldText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                        .onChange(of: servingsYieldText) { _, newValue in
                            if let parsed = Double(newValue), parsed > 0 {
                                servingsYield = parsed
                            }
                        }
                    Text("serving\(servingsYield == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !sourceURL.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text("Based on \(sourceDomain(from: sourceURL))")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            sourceURL = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Card: Details

    private var detailsCard: some View {
        ElevatedCard(padding: 16, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Details")
                    .font(.headline)
                    .foregroundStyle(Color.textSecondary)

                TextField("Description (optional)", text: $recipeDesc, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)

                Divider()

                HStack {
                    Text("Prep Time").font(.subheadline)
                    Spacer()
                    TextField("0", text: $prepMinutes)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                    Text("min").font(.subheadline).foregroundStyle(.secondary)
                }

                HStack {
                    Text("Cook Time").font(.subheadline)
                    Spacer()
                    TextField("0", text: $cookMinutes)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                    Text("min").font(.subheadline).foregroundStyle(.secondary)
                }

                HStack {
                    Text("Total Time").font(.subheadline)
                    Spacer()
                    TextField("0", text: $totalMinutes)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                    Text("min").font(.subheadline).foregroundStyle(.secondary)
                }

                Divider()

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
        }
    }

    // MARK: - Card: Ingredients

    private static let scaleOptions: [(label: String, value: Double)] = [
        ("½x", 0.5), ("1x", 1.0), ("1½x", 1.5), ("2x", 2.0), ("3x", 3.0)
    ]

    private var ingredientsCard: some View {
        ElevatedCard(padding: 16, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Ingredients")
                        .font(.headline)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Button {
                        showIngredientPicker = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.brandAccent)
                    }
                    .buttonStyle(.plain)
                }

                if !pendingIngredients.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(Self.scaleOptions, id: \.value) { option in
                            Button {
                                scaleMultiplier = option.value
                            } label: {
                                Text(option.label)
                                    .font(.caption)
                                    .fontWeight(scaleMultiplier == option.value ? .semibold : .regular)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                                    .background(scaleMultiplier == option.value
                                        ? Color.brandPrimary
                                        : Color.surfaceCard)
                                    .foregroundStyle(scaleMultiplier == option.value
                                        ? Color.white
                                        : Color.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.dividerSubtle, lineWidth: 1))
                }

                if pendingIngredients.isEmpty && unmatchedHints.isEmpty {
                    Text("No ingredients added yet. Tap + to add.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(pendingIngredients.enumerated()), id: \.element.id) { index, ingredient in
                            VStack(spacing: 0) {
                                ingredientRow(ingredient, at: index)
                                if index < pendingIngredients.count - 1 || !unmatchedHints.isEmpty {
                                    thinDivider()
                                }
                            }
                        }
                        ForEach(Array(unmatchedHints.enumerated()), id: \.element.id) { index, hint in
                            VStack(spacing: 0) {
                                unmatchedHintRow(hint: hint)
                                if index < unmatchedHints.count - 1 {
                                    thinDivider()
                                }
                            }
                        }
                    }

                    if importedNutrition != nil {
                        HStack {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.caption2)
                            Text("Nutrition from website — see label below")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.top, 8)
                    } else {
                        let hasRawIngredients = pendingIngredients.contains { $0.rawText != nil }
                        if !hasRawIngredients {
                            let total = pendingIngredients.reduce(NutritionCalculator.Result.zero) { sum, p in
                                sum + NutritionCalculator.preview(food: p.food, serving: p.serving, quantity: p.quantity)
                            }
                            HStack {
                                Text("Total (all servings)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(total.calories)) cal")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                            .padding(.top, 8)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func ingredientRow(_ ingredient: PendingIngredient, at index: Int) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if let raw = ingredient.rawText, !raw.isEmpty {
                    Text(raw)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                    Text(ingredient.food.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(ingredient.food.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    let qtyStr = ingredient.quantity.truncatingRemainder(dividingBy: 1) == 0
                        ? "\(Int(ingredient.quantity))"
                        : String(format: "%.2g", ingredient.quantity)
                    Text("\(qtyStr) × \(ingredient.serving.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if ingredient.rawText == nil {
                let preview = NutritionCalculator.preview(
                    food: ingredient.food,
                    serving: ingredient.serving,
                    quantity: ingredient.quantity
                )
                Text("\(Int(preview.calories)) cal")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }

            Button(role: .destructive) {
                pendingIngredients.remove(at: index)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func unmatchedHintRow(hint: ImportedRecipeData.UnmatchedHint) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(hint.raw)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                Text("No match found — tap to search")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                hintBeingSearched = hint
                showIngredientPicker = true
            } label: {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.brandAccent)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Card: Directions

    private var directionsCard: some View {
        ElevatedCard(padding: 16, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Directions")
                        .font(.headline)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Button {
                        newDirectionText = ""
                        showAddDirection = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.brandAccent)
                    }
                    .buttonStyle(.plain)
                }

                if directions.isEmpty {
                    Text("No steps added yet. Tap + to add directions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(directions.enumerated()), id: \.offset) { index, step in
                            VStack(spacing: 0) {
                                directionRow(step, at: index)
                                if index < directions.count - 1 {
                                    thinDivider()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func directionRow(_ step: String, at index: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1).")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.brandAccent)
                .frame(width: 24, alignment: .leading)

            Text(step)
                .font(.subheadline)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .onTapGesture {
                    editingDirectionIndex = index
                    editingDirectionText = step
                    showEditDirection = true
                }

            Spacer()

            Button(role: .destructive) {
                directions.remove(at: index)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Card: Nutrition Label

    private var nutritionLabelCard: some View {
        ElevatedCard(padding: 0, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Nutrition Facts")
                            .font(.system(size: 32, weight: .black))
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        if importedNutrition != nil {
                            Label("From website", systemImage: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    Rectangle()
                        .fill(Color.textPrimary)
                        .frame(height: 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Picker("Display", selection: $nutritionDisplay) {
                    ForEach(NutritionDisplay.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 12)

                VStack(spacing: 0) {
                    nutritionFactsContent
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    private var nutritionFactsContent: some View {
        let n = displayedNutrition
        let serving = nutritionDisplay == .perServing
            ? "1 serving of \(recipeName.isEmpty ? "recipe" : recipeName)"
            : "Whole recipe (\(servingsYieldText) servings)"

        return VStack(spacing: 0) {
            Text(serving)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

            Text("Amount per serving")
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

            HStack(alignment: .firstTextBaseline) {
                Text("Calories")
                    .font(.system(size: 32, weight: .black))
                Spacer()
                Text(n.calories.truncatingRemainder(dividingBy: 1) == 0
                     ? "\(Int(n.calories))"
                     : String(format: "%.0f", n.calories))
                    .font(.system(size: 44, weight: .black))
            }
            .padding(.vertical, 4)

            Rectangle().fill(Color.textPrimary).frame(height: 6).padding(.vertical, 4)

            HStack { Spacer(); Text("% Daily Value*").font(.system(size: 12, weight: .bold)) }
                .padding(.bottom, 4)

            thinDivider()
            readOnlyRow("Total Fat",          n.fat,          "g",  dv: 78,   bold: true)
            thinDivider()
            readOnlyRowIndented("Saturated Fat",  n.saturatedFat, "g",  dv: 20)
            thinDivider()
            readOnlyRowIndented("Trans Fat",      n.transFat,     "g",  dv: nil)
            thinDivider()
            readOnlyRow("Cholesterol",         n.cholesterol,  "mg", dv: 300,  bold: true)
            thinDivider()
            readOnlyRow("Sodium",              n.sodium,       "mg", dv: 2300, bold: true)
            thinDivider()
            readOnlyRow("Total Carbohydrate",  n.carbs,        "g",  dv: 275,  bold: true)
            thinDivider()
            readOnlyRowIndented("Dietary Fiber", n.fiber,       "g",  dv: 28)
            thinDivider()
            readOnlyRowIndented("Total Sugars",  n.sugar,       "g",  dv: nil)
            thinDivider()
            readOnlyRow("Protein",             n.protein,      "g",  dv: 50,   bold: true)

            Rectangle().fill(Color.textPrimary).frame(height: 8).padding(.vertical, 4)

            Group {
                readOnlyRow("Vitamin D",  n.vitaminD,  "mcg", dv: 20)
                thinDivider()
                readOnlyRow("Calcium",    n.calcium,   "mg",  dv: 1300)
                thinDivider()
                readOnlyRow("Iron",       n.iron,      "mg",  dv: 18)
                thinDivider()
                readOnlyRow("Potassium",  n.potassium, "mg",  dv: 4700)
                thinDivider()
                readOnlyRow("Vitamin A",  n.vitaminA,  "mcg", dv: 900)
                thinDivider()
                readOnlyRow("Vitamin C",  n.vitaminC,  "mg",  dv: 90)
            }

            Rectangle().fill(Color.textPrimary).frame(height: 4).padding(.top, 4)

            Text("* The % Daily Value (DV) tells you how much a nutrient in a serving of food contributes to a daily diet. 2,000 calories a day is used for general nutrition advice.")
                .font(.system(size: 9))
                .foregroundStyle(Color.textSecondary)
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)

            if importedNutrition != nil {
                Text("Nutrition sourced from the recipe website.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            } else if pendingIngredients.isEmpty {
                Text("Add ingredients above to see calculated nutrition.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Card: Metadata (edit mode only)

    private var metadataCard: some View {
        ElevatedCard(padding: 16, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Metadata")
                    .font(.headline)
                    .foregroundStyle(Color.textSecondary)

                if let added = recipe?.dateAdded {
                    HStack {
                        Text("Date Added")
                        Spacer()
                        Text(added.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(.secondary)
                    }
                }

                if let url = recipe?.sourceURL, !url.isEmpty {
                    HStack {
                        Text("Source")
                        Spacer()
                        Link(sourceDomain(from: url), destination: URL(string: url) ?? URL(string: "https://example.com")!)
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    // MARK: - Direction Sheets

    private var addDirectionSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $newDirectionText)
                    .padding()
                    .frame(minHeight: 120)
                Divider()
                Text("Describe one step clearly. You can edit steps by tapping them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
                Spacer()
            }
            .navigationTitle("Add Step")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        newDirectionText = ""
                        showAddDirection = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmed = newDirectionText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { directions.append(trimmed) }
                        newDirectionText = ""
                        showAddDirection = false
                    }
                    .disabled(newDirectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var editDirectionSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $editingDirectionText)
                    .padding()
                    .frame(minHeight: 120)
                Divider()
                Spacer()
            }
            .navigationTitle("Edit Step")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showEditDirection = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let index = editingDirectionIndex {
                            let trimmed = editingDirectionText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty { directions[index] = trimmed }
                        }
                        showEditDirection = false
                    }
                    .disabled(editingDirectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Helper Views

    private func thinDivider() -> some View {
        Rectangle()
            .fill(Color.textPrimary)
            .frame(height: 1)
    }

    @ViewBuilder
    private func readOnlyRow(
        _ label: String,
        _ value: Double?,
        _ unit: String,
        dv: Double?,
        bold: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label)
                .font(.system(size: 14))
                .fontWeight(bold ? .black : .regular)

            Spacer()

            if let value {
                Text(value.truncatingRemainder(dividingBy: 1) == 0
                     ? "\(Int(value))\(unit)"
                     : String(format: "%.1f\(unit)", value))
                    .font(.system(size: 14))
                    .fontWeight(bold ? .bold : .regular)
            } else {
                Text("—")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }

            if let value, let dv, dv > 0 {
                Text("\(Int((value / dv * 100).rounded()))%")
                    .font(.system(size: 13))
                    .fontWeight(.light)
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 50, alignment: .trailing)
            } else {
                Text("").frame(width: 50)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func readOnlyRowIndented(
        _ label: String,
        _ value: Double?,
        _ unit: String,
        dv: Double?
    ) -> some View {
        readOnlyRow(label, value, unit, dv: dv)
            .padding(.leading, 20)
    }

    // MARK: - Helpers

    private func sourceDomain(from urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host else { return urlString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private func loadIngredientsFromRecipe() {
        guard let recipe else { return }
        pendingIngredients = recipe.sortedIngredients.compactMap { ingredient in
            guard let food = ingredient.foodItem else { return nil }
            let serving = ingredient.servingSize ?? food.defaultServing ?? food.servingSizes.first
            guard let serving else { return nil }
            return PendingIngredient(food: food, serving: serving,
                                     quantity: ingredient.quantity, rawText: ingredient.rawText,
                                     recipeQuantity: ingredient.recipeQuantity,
                                     recipeUnit: ingredient.recipeUnit)
        }
        // Surface saved ingredients that never got a food match (foodItem == nil but rawText set).
        // Without this, they silently disappear in the editor even though they're still in the recipe.
        let savedUnmatched = recipe.sortedIngredients
            .filter { $0.foodItem == nil }
            .compactMap { ingredient -> ImportedRecipeData.UnmatchedHint? in
                guard let raw = ingredient.rawText, !raw.isEmpty else { return nil }
                let qty = ingredient.recipeQuantity ?? 1.0
                let unit = ingredient.recipeUnit ?? ""
                return ImportedRecipeData.UnmatchedHint(
                    raw: raw,
                    searchTerm: searchTermFromRaw(raw, quantity: qty, unit: unit),
                    quantity: qty,
                    unit: unit
                )
            }
        // Merge with any import-time hints already present (e.g., from a fresh URL import).
        if !savedUnmatched.isEmpty {
            let existingRaws = Set(unmatchedHints.map { $0.raw })
            unmatchedHints += savedUnmatched.filter { !existingRaws.contains($0.raw) }
        }
        baseIngredientQuantities = Dictionary(uniqueKeysWithValues:
            pendingIngredients.map { ($0.id, $0.quantity) })
    }

    /// Strips the leading quantity+unit from a raw ingredient string to produce a clean search term.
    /// "1 tsp baking soda" → "baking soda"  |  "2 cups flour" → "flour"
    private func searchTermFromRaw(_ raw: String, quantity: Double, unit: String) -> String {
        guard !unit.isEmpty else { return raw }
        let qtyStr = quantity.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(quantity)) : String(format: "%.2g", quantity)
        let prefix = "\(qtyStr) \(unit) "
        if raw.lowercased().hasPrefix(prefix.lowercased()) {
            let stripped = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            return stripped.isEmpty ? raw : stripped
        }
        return raw
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

    // MARK: - Apply Import

    private func applyImport(_ imported: ImportedRecipeData) {
        recipeName         = imported.name
        let y              = imported.servingsYield
        servingsYield      = y
        baseServingsYield  = y
        servingsYieldText  = y.truncatingRemainder(dividingBy: 1) == 0
                             ? String(Int(y)) : String(format: "%.1f", y)
        sourceURL          = imported.sourceURL
        directions         = imported.directions
        unmatchedHints     = imported.unmatchedIngredients
        importedNutrition  = imported.nutrition
        scaleMultiplier    = 1.0

        for item in imported.matchedIngredients {
            let ingredient = PendingIngredient(food: item.food, serving: item.serving,
                                               quantity: item.quantity, rawText: item.rawText,
                                               recipeQuantity: item.quantity, recipeUnit: item.unit)
            baseIngredientQuantities[ingredient.id] = item.quantity
            pendingIngredients.append(ingredient)
        }
    }

    // MARK: - Save

    private func saveChanges() {
        let trimmedName = recipeName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, servingsYield > 0 else { return }

        let nutrition = calculatedPerServing
        let urlToStore = sourceURL.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil : sourceURL.trimmingCharacters(in: .whitespaces)
        let descTrimmed = recipeDesc.trimmingCharacters(in: .whitespaces)

        if let existing = recipe {
            // --- UPDATE EXISTING RECIPE ---
            existing.name = trimmedName
            existing.servingsYield = servingsYield
            existing.sourceURL = urlToStore
            existing.directions = directions
            existing.importedNutrition = importedNutrition
            existing.recipeDescription = descTrimmed.isEmpty ? nil : descTrimmed
            existing.prepMinutes       = Int(prepMinutes)
            existing.cookMinutes       = Int(cookMinutes)
            existing.totalMinutes      = Int(totalMinutes)
            existing.recipeCategory    = recipeCategory.isEmpty ? nil : recipeCategory
            existing.recipeCuisine     = recipeCuisine.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil : recipeCuisine.trimmingCharacters(in: .whitespaces)

            // Handle photo
            if let img = pendingImage, let data = img.jpegData(compressionQuality: 0.85) {
                if let old = existing.imageURL { RecipeImportService.deleteLocalImage(urlString: old) }
                existing.imageURL = RecipeImportService.saveImageDataLocally(data)
            } else if pendingImage == nil && currentImageURL == nil && existing.imageURL != nil {
                RecipeImportService.deleteLocalImage(urlString: existing.imageURL!)
                existing.imageURL = nil
            }

            // Replace ingredient list
            for old in existing.ingredients { modelContext.delete(old) }
            for (index, pending) in pendingIngredients.enumerated() {
                let ingredient = RecipeIngredient(quantity: pending.quantity, sortOrder: index)
                ingredient.foodItem       = pending.food
                ingredient.servingSize    = pending.serving
                ingredient.rawText        = pending.rawText
                ingredient.recipeQuantity = pending.recipeQuantity
                ingredient.recipeUnit     = pending.recipeUnit
                ingredient.recipe         = existing
                modelContext.insert(ingredient)
            }

            // Update associated FoodItem nutrition
            if let food = existing.foodItem {
                food.name           = trimmedName
                food.calories       = nutrition.calories
                food.protein        = nutrition.protein
                food.carbs          = nutrition.carbs
                food.fat            = nutrition.fat
                food.fiber          = nutrition.fiber
                food.sugar          = nutrition.sugar
                food.saturatedFat   = nutrition.saturatedFat
                food.transFat       = nutrition.transFat
                food.monounsaturatedFat = nutrition.monounsaturatedFat
                food.polyunsaturatedFat = nutrition.polyunsaturatedFat
                food.sodium         = nutrition.sodium
                food.cholesterol    = nutrition.cholesterol
                food.potassium      = nutrition.potassium
                food.calcium        = nutrition.calcium
                food.iron           = nutrition.iron
                food.magnesium      = nutrition.magnesium
                food.zinc           = nutrition.zinc
                food.vitaminA       = nutrition.vitaminA
                food.vitaminC       = nutrition.vitaminC
                food.vitaminD       = nutrition.vitaminD
                food.vitaminE       = nutrition.vitaminE
                food.vitaminK       = nutrition.vitaminK
                food.vitaminB6      = nutrition.vitaminB6
                food.vitaminB12     = nutrition.vitaminB12
                food.folate         = nutrition.folate
                food.choline        = nutrition.choline
                food.caffeine       = nutrition.caffeine
            }

        } else {
            // --- CREATE NEW RECIPE ---

            // 1. Create the FoodItem
            let foodItem = FoodItem(
                name:          trimmedName,
                source:        "recipe",
                nutritionMode: .perServing,
                calories:      nutrition.calories,
                protein:       nutrition.protein,
                carbs:         nutrition.carbs,
                fat:           nutrition.fat,
                fiber:         nutrition.fiber,
                sugar:         nutrition.sugar,
                saturatedFat:  nutrition.saturatedFat,
                transFat:      nutrition.transFat,
                polyunsaturatedFat: nutrition.polyunsaturatedFat,
                monounsaturatedFat: nutrition.monounsaturatedFat,
                sodium:        nutrition.sodium,
                cholesterol:   nutrition.cholesterol,
                potassium:     nutrition.potassium,
                calcium:       nutrition.calcium,
                iron:          nutrition.iron,
                magnesium:     nutrition.magnesium,
                zinc:          nutrition.zinc,
                vitaminA:      nutrition.vitaminA,
                vitaminC:      nutrition.vitaminC,
                vitaminD:      nutrition.vitaminD,
                vitaminE:      nutrition.vitaminE,
                vitaminK:      nutrition.vitaminK,
                vitaminB6:     nutrition.vitaminB6,
                vitaminB12:    nutrition.vitaminB12,
                folate:        nutrition.folate,
                choline:       nutrition.choline,
                caffeine:      nutrition.caffeine
            )
            foodItem.normalizeToPerHundredGrams(gramWeightPerServing: nil)
            let serving = ServingSize(
                label: "1 serving",
                gramWeight: 100.0,
                isDefault: true,
                sortOrder: 0,
                unit: ServingUnit.serving.rawValue
            )
            serving.foodItem = foodItem
            modelContext.insert(foodItem)
            modelContext.insert(serving)
            foodItem.servingSizes.append(serving)

            // 2. Create the Recipe
            let newRecipe = Recipe(
                name:          trimmedName,
                servingsYield: servingsYield,
                sourceURL:     urlToStore,
                directions:    directions
            )
            newRecipe.foodItem          = foodItem
            newRecipe.importedNutrition = importedNutrition
            if let img = pendingImage, let data = img.jpegData(compressionQuality: 0.85) {
                newRecipe.imageURL = RecipeImportService.saveImageDataLocally(data)
            }
            newRecipe.recipeDescription = descTrimmed.isEmpty ? nil : descTrimmed
            newRecipe.prepMinutes       = Int(prepMinutes)
            newRecipe.cookMinutes       = Int(cookMinutes)
            newRecipe.totalMinutes      = Int(totalMinutes)
            newRecipe.recipeCategory    = recipeCategory.isEmpty ? nil : recipeCategory
            newRecipe.recipeCuisine     = recipeCuisine.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil : recipeCuisine.trimmingCharacters(in: .whitespaces)
            modelContext.insert(newRecipe)

            // 3. Create RecipeIngredients
            for (index, pending) in pendingIngredients.enumerated() {
                let ingredient = RecipeIngredient(quantity: pending.quantity, sortOrder: index)
                ingredient.foodItem       = pending.food
                ingredient.servingSize    = pending.serving
                ingredient.rawText        = pending.rawText
                ingredient.recipeQuantity = pending.recipeQuantity
                ingredient.recipeUnit     = pending.recipeUnit
                ingredient.recipe         = newRecipe
                modelContext.insert(ingredient)
            }
        }

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Private: ImportedRecipeData

private struct ImportedRecipeData {
    let name: String
    let servingsYield: Double
    let sourceURL: String
    let directions: [String]
    let matchedIngredients: [(food: FoodItem, serving: ServingSize, quantity: Double, rawText: String, unit: String)]
    let unmatchedIngredients: [UnmatchedHint]
    let nutrition: RecipeNutrition?

    struct UnmatchedHint: Identifiable {
        let id       = UUID()
        let raw:        String
        let searchTerm: String
        let quantity:   Double
        let unit:       String
    }
}

// MARK: - Private: EditorURLImportView (callback-based, used by RecipeEditorView)

private struct EditorURLImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let onImport: (ImportedRecipeData) -> Void

    @State private var urlText: String = ""
    @State private var isLoading = false
    @State private var result: RecipeImportResult?
    @State private var errorMessage: String?
    @State private var matchResults: [MatchResult] = []
    @State private var editingMatchIndex: Int?

    struct MatchResult: Identifiable {
        let id: UUID
        let raw: String
        let searchTerm: String
        let quantity: Double
        let unit: String
        var matchedFood: FoodItem?
        var matchedServing: ServingSize?
    }

    private let service = RecipeImportService.fromPlist()

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    reviewPage(result)
                } else {
                    urlEntryPage
                }
            }
            .navigationTitle("Import from Web")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if result != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") {
                            withAnimation { self.result = nil; matchResults = [] }
                        }
                    }
                }
            }
        }
    }

    // MARK: Page 1: URL Entry

    private var urlEntryPage: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.brandAccent)
                Text("Paste a recipe URL")
                    .font(.title3.bold())
                Text("Works with most recipe websites that display a structured recipe card (Allrecipes, Food Network, NYT Cooking, and thousands more).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.top, 20)

            TextField("https://example.com/recipe", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button {
                Task { await fetchRecipe() }
            } label: {
                Group {
                    if isLoading {
                        HStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("Fetching…")
                        }
                    } else {
                        Text("Fetch Recipe")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading
                            ? Color.gray : Color.brandAccent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            .padding(.horizontal)

            Spacer()
        }
        .background(Color.surfacePrimary)
    }

    // MARK: Page 2: Review

    private func reviewPage(_ result: RecipeImportResult) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Recipe summary card
                ElevatedCard(padding: 16, cornerRadius: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(result.name)
                            .font(.title3.bold())
                        let yieldStr = result.servingsYield.truncatingRemainder(dividingBy: 1) == 0
                            ? "\(Int(result.servingsYield))"
                            : String(format: "%.1f", result.servingsYield)
                        Text("Makes \(yieldStr) serving\(result.servingsYield == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let domain = URL(string: result.sourceURL)?.host {
                            let clean = domain.hasPrefix("www.") ? String(domain.dropFirst(4)) : domain
                            Label(clean, systemImage: "link")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                // Ingredients card
                ElevatedCard(padding: 16, cornerRadius: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Ingredients")
                                .font(.headline)
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            Text("\(matchResults.count) found")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if matchResults.isEmpty {
                            Text("No ingredients were found on this page.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(matchResults) { match in
                                ingredientMatchRow(match)
                                if match.id != matchResults.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }

                // Directions card
                if !result.directions.isEmpty {
                    ElevatedCard(padding: 16, cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Directions")
                                    .font(.headline)
                                    .foregroundStyle(Color.textSecondary)
                                Spacer()
                                Text("\(result.directions.count) step\(result.directions.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(Array(result.directions.prefix(3).enumerated()), id: \.offset) { i, step in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(i + 1).")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.brandAccent)
                                        .frame(width: 16, alignment: .leading)
                                    Text(step)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            if result.directions.count > 3 {
                                Text("… and \(result.directions.count - 3) more step\(result.directions.count - 3 == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                // Website nutrition card
                if let n = result.nutrition {
                    ElevatedCard(padding: 16, cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                Text("Nutrition from website")
                                    .font(.headline)
                                Spacer()
                            }
                            Text("Per serving · automatically applied when saved")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 0) {
                                nutritionPill(label: "Cal", value: Int(n.calories))
                                Spacer()
                                nutritionPill(label: "Protein", value: Int(n.protein), unit: "g")
                                Spacer()
                                nutritionPill(label: "Carbs", value: Int(n.carbs), unit: "g")
                                Spacer()
                                nutritionPill(label: "Fat", value: Int(n.fat), unit: "g")
                            }
                        }
                    }
                }

                // Match summary
                let matched   = matchResults.filter { $0.matchedFood != nil }.count
                let unmatched = matchResults.count - matched
                ElevatedCard(padding: 16, cornerRadius: 20) {
                    VStack(spacing: 6) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("\(matched) ingredient\(matched == 1 ? "" : "s") matched to My Foods")
                            Spacer()
                        }
                        .font(.subheadline)
                        if unmatched > 0 {
                            HStack {
                                Image(systemName: "magnifyingglass.circle").foregroundStyle(.orange)
                                Text("\(unmatched) ingredient\(unmatched == 1 ? "" : "s") not found — add manually in the editor")
                                Spacer()
                            }
                            .font(.subheadline)
                        }
                    }
                }

                // Apply button
                Button {
                    applyRecipe(result)
                } label: {
                    Text("Apply to Recipe")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.brandAccent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding()
        }
        .background(Color.surfacePrimary)
        .sheet(isPresented: Binding(
            get: { editingMatchIndex != nil },
            set: { if !$0 { editingMatchIndex = nil } }
        )) {
            if let idx = editingMatchIndex {
                MatchFoodPickerSheet(
                    rawIngredient: matchResults[idx].raw,
                    searchTerm:    matchResults[idx].searchTerm,
                    current:       matchResults[idx].matchedFood
                ) { selectedFood in
                    matchResults[idx].matchedFood   = selectedFood
                    matchResults[idx].matchedServing = selectedFood?.defaultServing
                    editingMatchIndex = nil
                }
            }
        }
    }

    @ViewBuilder
    private func nutritionPill(label: String, value: Int, unit: String = "") -> some View {
        VStack(spacing: 2) {
            Text("\(value)\(unit)")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 56)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color(.systemBackground).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func ingredientMatchRow(_ match: MatchResult) -> some View {
        Button {
            if let idx = matchResults.firstIndex(where: { $0.id == match.id }) {
                editingMatchIndex = idx
            }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                if match.matchedFood != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                } else {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(match.raw)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let food = match.matchedFood {
                        Text("→ \(food.name)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                    } else {
                        Text("Search term: \"\(match.searchTerm)\"")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Image(systemName: "pencil.circle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: Fetch Logic

    @MainActor
    private func fetchRecipe() async {
        isLoading    = true
        errorMessage = nil

        do {
            let fetched  = try await service.importRecipe(from: urlText)
            result       = fetched
            matchResults = await buildMatchResults(for: fetched.parsedIngredients)
        } catch let e as RecipeImportError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func buildMatchResults(for parsed: [RecipeImportResult.ParsedIngredient]) async -> [MatchResult] {
        let allFoods = (try? modelContext.fetch(FetchDescriptor<FoodItem>())) ?? []

        return parsed.map { p in
            let food = autoMatch(searchTerm: p.searchTerm, in: allFoods)
            return MatchResult(
                id:             p.id,
                raw:            p.rawString,
                searchTerm:     p.searchTerm,
                quantity:       p.quantity,
                unit:           p.unit,
                matchedFood:    food,
                matchedServing: food?.defaultServing
            )
        }
    }

    private func autoMatch(searchTerm: String, in foods: [FoodItem]) -> FoodItem? {
        let term      = searchTerm.lowercased().trimmingCharacters(in: .whitespaces)
        let termWords = term.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        if let exact = foods.first(where: { $0.name.lowercased() == term }) { return exact }

        if termWords.count >= 2 {
            return foods.first { food in
                let foodWords = food.name.lowercased()
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                let allMatch = termWords.allSatisfy { tw in foodWords.contains { $0 == tw } }
                return allMatch && foodWords.count <= termWords.count + 1
            }
        }

        if term.count >= 6 {
            return foods.first { food in
                let foodLower = food.name.lowercased()
                let wordBoundaryMatch = foodLower == term || foodLower.hasPrefix(term + " ")
                return wordBoundaryMatch && food.name.count <= term.count + 12
            }
        }

        return nil
    }

    private func applyRecipe(_ result: RecipeImportResult) {
        let matched: [(food: FoodItem, serving: ServingSize, quantity: Double, rawText: String, unit: String)] = matchResults.compactMap { match in
            guard let food = match.matchedFood,
                  let serving = match.matchedServing else { return nil }
            return (food: food, serving: serving, quantity: match.quantity, rawText: match.raw, unit: match.unit)
        }

        let unmatched = matchResults
            .filter { $0.matchedFood == nil }
            .map { ImportedRecipeData.UnmatchedHint(
                raw:        $0.raw,
                searchTerm: $0.searchTerm,
                quantity:   $0.quantity,
                unit:       $0.unit
            )}

        onImport(ImportedRecipeData(
            name:                result.name,
            servingsYield:       result.servingsYield,
            sourceURL:           result.sourceURL,
            directions:          result.directions,
            matchedIngredients:  matched,
            unmatchedIngredients: unmatched,
            nutrition:           result.nutrition
        ))
        dismiss()
    }
}

// MARK: - Private: MatchFoodPickerSheet

/// Lets the user manually assign (or clear) the food match for one ingredient line.
@MainActor
private struct MatchFoodPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let rawIngredient: String
    let searchTerm: String
    let current: FoodItem?
    let onSelect: (FoodItem?) -> Void

    @State private var searchText        = ""
    @State private var myFoods: [FoodItem]          = []
    @State private var onlineResults: [ProductInfo] = []
    @State private var isSearchingOnline = false
    @State private var isSaving          = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { onSelect(nil) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                            Text("No match — skip this ingredient").foregroundStyle(.secondary)
                            Spacer()
                            if current == nil {
                                Image(systemName: "checkmark").foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                if !myFoods.isEmpty {
                    Section("My Foods") {
                        ForEach(myFoods) { food in
                            Button { onSelect(food) } label: { myFoodRow(food) }
                                .buttonStyle(.plain)
                        }
                    }
                }

                if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section {
                        if isSearchingOnline {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Searching online…").foregroundStyle(.secondary)
                            }
                        } else if let err = searchError {
                            Text(err).font(.caption).foregroundStyle(.red)
                        } else if onlineResults.isEmpty {
                            Text("No online results found.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            ForEach(onlineResults) { product in
                                Button {
                                    Task { await selectOnlineResult(product) }
                                } label: {
                                    onlineResultRow(product)
                                }
                                .buttonStyle(.plain)
                                .disabled(isSaving)
                            }
                        }
                    } header: {
                        HStack {
                            Text("Search Online")
                            if isSaving {
                                ProgressView().scaleEffect(0.75).padding(.leading, 4)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search foods or type to search online")
            .onChange(of: searchText) { _, new in
                loadMyFoods()
                scheduleOnlineSearch(query: new)
            }
            .navigationTitle("Assign Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .top) {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet").font(.caption).foregroundStyle(.secondary)
                    Text(rawIngredient).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal).padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
            }
        }
        .task {
            searchText = searchTerm
            loadMyFoods()
            scheduleOnlineSearch(query: searchTerm)
        }
    }

    @ViewBuilder
    private func myFoodRow(_ food: FoodItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name).fontWeight(.medium).foregroundStyle(.primary)
                if let brand = food.brand, !brand.isEmpty {
                    Text(brand).font(.caption).foregroundStyle(.secondary)
                }
                Text("\(Int(food.calories)) cal · \(food.source)")
                    .font(.caption2).foregroundStyle(.blue)
            }
            Spacer()
            if food.id == current?.id {
                Image(systemName: "checkmark").foregroundStyle(.blue)
            }
        }
    }

    @ViewBuilder
    private func onlineResultRow(_ product: ProductInfo) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.displayName).fontWeight(.medium).foregroundStyle(.primary)
                if let brand = product.brands, !brand.isEmpty {
                    Text(brand).font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Text(sourceLabel(product.code)).font(.caption2).foregroundStyle(.orange)
                    if let serving = product.servingSize {
                        Text(serving).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
            Image(systemName: "plus.circle").foregroundStyle(Color.brandAccent)
        }
    }

    private func sourceLabel(_ code: String) -> String {
        if code.hasPrefix("usda_")       { return "USDA" }
        if code.hasPrefix("fatsecret_")  { return "FatSecret" }
        return "Open Food Facts"
    }

    private func loadMyFoods() {
        let descriptor = FetchDescriptor<FoodItem>(sortBy: [SortDescriptor(\.name)])
        var results = (try? modelContext.fetch(descriptor)) ?? []
        if !searchText.isEmpty {
            results = results.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                || ($0.brand?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        myFoods = results
    }

    private func scheduleOnlineSearch(query: String) {
        searchTask?.cancel()
        onlineResults     = []
        searchError       = nil
        isSearchingOnline = false
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return }
        isSearchingOnline = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do {
                let results = try await UnifiedFoodSearchService.shared.searchAllDatabases(query: trimmed)
                guard !Task.isCancelled else { return }
                onlineResults     = Array(results.prefix(20))
                isSearchingOnline = false
            } catch {
                guard !Task.isCancelled else { return }
                isSearchingOnline = false
                searchError = "Search failed — check your connection."
            }
        }
    }

    private func selectOnlineResult(_ product: ProductInfo) async {
        isSaving = true
        defer { isSaving = false }

        let code = product.code
        if let existing = (try? modelContext.fetch(
            FetchDescriptor<FoodItem>(predicate: #Predicate { $0.barcode == code })
        ))?.first {
            onSelect(existing)
            return
        }

        let detailed: ProductInfo
        do { detailed = try await UnifiedFoodSearchService.shared.getProductDetails(code: code) }
        catch { detailed = product }

        onSelect(makeFoodItem(from: detailed))
    }

    private func makeFoodItem(from product: ProductInfo) -> FoodItem {
        let n           = product.nutriments
        let isFatSecret = product.code.hasPrefix("fatsecret_")
        let isUSDA      = product.code.hasPrefix("usda_")

        let servingLabel: String
        let servingGrams: Double?

        if isUSDA, let portions = product.portions, !portions.isEmpty {
            let bulk = ["package", "bag", "box", "container", "can", "pouch"]
            let sorted = portions.sorted { a, b in
                let bulkA = bulk.contains { a.modifier.lowercased().contains($0) }
                let bulkB = bulk.contains { b.modifier.lowercased().contains($0) }
                if bulkA != bulkB { return !bulkA }
                return a.gramWeight < b.gramWeight
            }
            let p = sorted[0]
            servingLabel = p.amount == 1.0 ? p.modifier
                : "\(p.amount.truncatingRemainder(dividingBy:1)==0 ? "\(Int(p.amount))" : "\(p.amount)") \(p.modifier)"
            servingGrams = p.gramWeight
        } else if let s = product.servingSize, !s.isEmpty {
            servingLabel = s
            servingGrams = gramWeightFromLabel(s)
        } else {
            servingLabel = "1 serving"
            servingGrams = nil
        }

        let calories: Double; let protein: Double; let carbs: Double; let fat: Double
        if isFatSecret {
            calories = n?.energyKcalServing?.value ?? 0
            protein  = n?.proteinsServing?.value   ?? 0
            carbs    = n?.carbohydratesServing?.value ?? 0
            fat      = n?.fatServing?.value        ?? 0
        } else if let grams = servingGrams, grams > 0,
                  let n100 = n?.energyKcal100g?.value, n100 > 0 {
            let scale = grams / 100.0
            calories = n100 * scale
            protein  = (n?.proteins100g?.value      ?? 0) * scale
            carbs    = (n?.carbohydrates100g?.value ?? 0) * scale
            fat      = (n?.fat100g?.value           ?? 0) * scale
        } else {
            calories = n?.energyKcalServing?.value    ?? 0
            protein  = n?.proteinsServing?.value      ?? 0
            carbs    = n?.carbohydratesServing?.value ?? 0
            fat      = n?.fatServing?.value           ?? 0
        }

        func gramMicro(_ per100g: FlexibleDouble?, perServing: FlexibleDouble?) -> Double? {
            if isFatSecret { return perServing?.value }
            if let grams = servingGrams, let v = per100g?.value { return v * grams / 100.0 }
            return perServing?.value
        }
        func sodiumMg() -> Double? {
            if isFatSecret { return n?.sodiumServing?.value }
            if let grams = servingGrams, let v = n?.sodium100g?.value { return v * 1000 * grams / 100.0 }
            if let v = n?.sodiumServing?.value { return v * 1000 }
            return nil
        }

        let source = isUSDA ? "USDA" : isFatSecret ? "FatSecret" : "OpenFoodFacts"
        let food = FoodItem(
            name: product.displayName, brand: product.brands, barcode: product.code,
            source: source, nutritionMode: .perServing,
            calories: calories, protein: protein, carbs: carbs, fat: fat,
            fiber:        gramMicro(n?.fiber100g,        perServing: n?.fiberServing),
            sugar:        gramMicro(n?.sugars100g,       perServing: n?.sugarsServing),
            saturatedFat: gramMicro(n?.saturatedFat100g, perServing: n?.saturatedFatServing),
            sodium:       sodiumMg()
        )
        let effectiveGrams = servingGrams ?? 100.0
        food.normalizeToPerHundredGrams(gramWeightPerServing: servingGrams)
        modelContext.insert(food)

        let servingUnit = ServingSizeParser.parse(servingLabel).flatMap { parsed in
            parsed.unit == .serving ? nil : parsed.unit.rawValue
        } ?? ServingSizeParser.parseUnit(servingLabel)?.rawValue

        let defServing = ServingSize(
            label: servingLabel, gramWeight: effectiveGrams,
            isDefault: true, sortOrder: 0, unit: servingUnit
        )
        defServing.foodItem = food
        modelContext.insert(defServing)
        food.servingSizes.append(defServing)

        if isUSDA, let portions = product.portions, portions.count > 1 {
            let bulk = ["package", "bag", "box", "container", "can", "pouch"]
            let sorted = portions.sorted { a, b in
                let bulkA = bulk.contains { a.modifier.lowercased().contains($0) }
                let bulkB = bulk.contains { b.modifier.lowercased().contains($0) }
                if bulkA != bulkB { return !bulkA }
                return a.gramWeight < b.gramWeight
            }
            for (i, p) in sorted.dropFirst().enumerated() {
                let lbl = p.amount == 1.0 ? p.modifier
                    : "\(p.amount.truncatingRemainder(dividingBy:1)==0 ? "\(Int(p.amount))" : "\(p.amount)") \(p.modifier)"
                let portionUnit = ServingSizeParser.parse(lbl).flatMap { parsed in
                    parsed.unit == .serving ? nil : parsed.unit.rawValue
                } ?? ServingSizeParser.parseUnit(lbl)?.rawValue
                let s = ServingSize(
                    label: lbl, gramWeight: p.gramWeight,
                    isDefault: false, sortOrder: i + 1, unit: portionUnit
                )
                s.foodItem = food
                modelContext.insert(s)
                food.servingSizes.append(s)
            }
        }

        return food
    }

    private func gramWeightFromLabel(_ label: String) -> Double? {
        let pattern = #"\((\d+(?:\.\d+)?)g\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
              let range = Range(match.range(at: 1), in: label) else { return nil }
        return Double(label[range])
    }
}

// MARK: - Camera Picker

private struct EditorCameraPickerView: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: EditorCameraPickerView
        init(_ parent: EditorCameraPickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage {
                parent.onImage(img)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
