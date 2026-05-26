//
//  RecipesListView.swift
//  BiteRecipe
//

import SwiftUI
import SwiftData
import BiteLedgerCore

// MARK: - Sort Order

enum RecipeSortOrder: String, CaseIterable, Identifiable {
    case name     = "A–Z"
    case cookTime = "Cook Time"
    case newest   = "Newest"

    var id: String { rawValue }
}

// MARK: - RecipesListView

struct RecipesListView: View {
    /// When non-nil, this view is operating as an iPad NavigationSplitView sidebar.
    /// Card taps set the binding instead of pushing a NavigationLink.
    var selectedRecipe: Binding<Recipe?>? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.sizeCategory) private var sizeCategory
    @Query private var allRecipes: [Recipe]

    @State private var searchText = ""
    @State private var sortOrder: RecipeSortOrder = .name
    @State private var showingNewRecipe = false
    @State private var showingImport = false
    @State private var showingOCRImport = false
    @State private var showingSettings = false
    @State private var pendingImportURL: String? = nil
    @State private var activeToast: AppToastModel? = nil
    @State private var toastDismissTask: Task<Void, Never>? = nil

    // MARK: Computed

    private var displayedRecipes: [Recipe] {
        let filtered: [Recipe]
        if searchText.isEmpty {
            filtered = allRecipes
        } else {
            filtered = allRecipes.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return sorted(filtered)
    }

    private func sorted(_ recipes: [Recipe]) -> [Recipe] {
        switch sortOrder {
        case .name:
            return recipes.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .cookTime:
            return recipes.sorted { lhs, rhs in
                let l = lhs.totalMinutes ?? lhs.cookMinutes ?? Int.max
                let r = rhs.totalMinutes ?? rhs.cookMinutes ?? Int.max
                return l < r
            }
        case .newest:
            return recipes.sorted { $0.dateAdded > $1.dateAdded }
        }
    }

    private var gridColumns: [GridItem] {
        let columnCount: Int
        if sizeCategory >= .accessibilityMedium {
            columnCount = 1
        } else if sizeClass == .regular {
            columnCount = 3
        } else {
            columnCount = 2
        }
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: columnCount)
    }

    private var isSidebarMode: Bool { selectedRecipe != nil }

    // MARK: Body

    var body: some View {
        let coreContent = ZStack(alignment: .bottom) {
            Group {
                if allRecipes.isEmpty {
                    recipeEmptyState
                } else if !searchText.isEmpty && displayedRecipes.isEmpty {
                    noResultsState
                } else {
                    recipeGrid
                }
            }
            .navigationTitle("Recipes")
            .searchable(text: $searchText, prompt: "Search recipes")
            .navigationSubtitle(!searchText.isEmpty && !displayedRecipes.isEmpty
                ? "\(displayedRecipes.count) recipe\(displayedRecipes.count == 1 ? "" : "s")"
                : ""
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !isSidebarMode {
                        Button { showingSettings = true } label: {
                            Image(systemName: "gear")
                        }
                        .accessibilityLabel("Settings")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("Sort by", selection: $sortOrder) {
                            ForEach(RecipeSortOrder.allCases) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("Sort recipes")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showingImport = true } label: {
                            Label("Import from URL", systemImage: "link.badge.plus")
                        }
                        Button { showingOCRImport = true } label: {
                            Label("Scan Recipe Card", systemImage: "camera.viewfinder")
                        }
                        Button { showingNewRecipe = true } label: {
                            Label("Create Manually", systemImage: "square.and.pencil")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add recipe")
                }
            }
            .sheet(isPresented: $showingImport, onDismiss: { pendingImportURL = nil }) {
                ImportRecipeView(prefilledURL: pendingImportURL)
            }
            .sheet(isPresented: $showingOCRImport) {
                OCRRecipeImportView()
            }
            .sheet(isPresented: $showingNewRecipe) {
                RecipeEditorView(recipe: nil)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .biteRecipeImportURL)) { note in
                if let url = note.userInfo?["url"] as? URL {
                    pendingImportURL = url.absoluteString
                    showingImport = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .biteRecipeBundleImported)) { note in
                guard let id = note.userInfo?["recipeID"] as? UUID,
                      let name = note.userInfo?["recipeName"] as? String else { return }
                showBundleImportToast(id: id, name: name)
            }

            // AppToast overlay — replaces ImportedToastView
            if let toast = activeToast {
                AppToastView(model: toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 8)
            }
        }
        .animation(.spring(duration: 0.3), value: activeToast?.id)

        if isSidebarMode {
            // iPad sidebar: no NavigationStack (NavigationSplitView provides the nav context)
            coreContent
        } else {
            // iPhone: wrap in NavigationStack
            NavigationStack {
                coreContent
            }
        }
    }

    // MARK: - Grid

    private var recipeGrid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(displayedRecipes) { recipe in
                    recipeCell(for: recipe)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func recipeCell(for recipe: Recipe) -> some View {
        if let binding = selectedRecipe {
            // iPad sidebar: tapping selects into detail column
            Button {
                binding.wrappedValue = recipe
            } label: {
                RecipeCardView(recipe: recipe)
            }
            .buttonStyle(.plain)
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            // iPhone: NavigationLink push
            NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                RecipeCardView(recipe: recipe)
            }
            .buttonStyle(.plain)
            .frame(maxHeight: .infinity, alignment: .top)
            .contextMenu {
                Button(role: .destructive) {
                    deleteRecipe(recipe)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Empty States

    private var recipeEmptyState: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Text("No Recipes Yet")
                    .font(.title2.bold())
                Text("Add your first recipe one of three ways:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 12) {
                Button { showingImport = true } label: {
                    Label("Import from URL", systemImage: "link.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button { showingOCRImport = true } label: {
                    Label("Scan Recipe Card", systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                Button { showingNewRecipe = true } label: {
                    Label("Create Manually", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }

    private var noResultsState: some View {
        ContentUnavailableView.search(text: searchText)
    }

    // MARK: - Actions

    private func deleteRecipe(_ recipe: Recipe) {
        if let url = recipe.imageURL { RecipeImportService.deleteLocalImage(urlString: url) }
        modelContext.delete(recipe)
    }

    private func showBundleImportToast(id: UUID, name: String) {
        let capturedID = id
        toastDismissTask?.cancel()
        withAnimation { activeToast = .undo("Added \"\(name)\"") { [self] in
            toastDismissTask?.cancel()
            withAnimation { activeToast = nil }
            undoImport(id: capturedID)
        }}
        toastDismissTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await MainActor.run { withAnimation { activeToast = nil } }
        }
    }

    private func undoImport(id: UUID) {
        let descriptor = FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == id })
        guard let recipe = try? modelContext.fetch(descriptor).first else { return }
        deleteRecipe(recipe)
    }
}

// MARK: - Photo

/// Loads a recipe photo from either a remote https:// URL (via AsyncImage) or a
/// local file:// URL (via UIImage(contentsOfFile:)). AsyncImage silently fails
/// on file:// URLs in some iOS versions; using UIImage avoids that issue.
struct RecipePhotoView<Placeholder: View>: View {
    let urlString: String?
    let contentMode: ContentMode
    @ViewBuilder let placeholder: () -> Placeholder

    var body: some View {
        if let urlStr = urlString {
            if urlStr.hasPrefix("file://"),
               let url = URL(string: urlStr),
               let path = url.path.removingPercentEncoding,
               let uiImage = UIImage(contentsOfFile: path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable()
                            .aspectRatio(contentMode: contentMode)
                            .transition(.opacity.animation(.easeIn(duration: 0.25)))
                    } else {
                        placeholder()
                    }
                }
            } else {
                placeholder()
            }
        } else {
            placeholder()
        }
    }
}
