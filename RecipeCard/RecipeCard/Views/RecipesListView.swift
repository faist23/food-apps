//
//  RecipesListView.swift
//  RecipeCard
//

import SwiftUI
import SwiftData
import BiteLedgerCore

struct RecipesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @State private var showingNewRecipe = false
    @State private var showingImport = false
    @State private var showingOCRImport = false
    @State private var showingSettings = false
    @State private var pendingImportURL: String? = nil

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationStack {
            Group {
                if recipes.isEmpty {
                    recipeEmptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(recipes) { recipe in
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
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .navigationTitle("Recipes")
            .toolbar {
                // Design: [gear] leading (Settings), [+▾] trailing menu (3 add methods)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gear")
                    }
                    .accessibilityLabel("Settings")
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
            .onReceive(NotificationCenter.default.publisher(for: .recipeCardImportURL)) { note in
                if let url = note.userInfo?["url"] as? URL {
                    pendingImportURL = url.absoluteString
                    showingImport = true
                }
            }
        }
    }

    private func deleteRecipe(_ recipe: Recipe) {
        if let url = recipe.imageURL { RecipeImportService.deleteLocalImage(urlString: url) }
        modelContext.delete(recipe)
    }

    // D-2: Custom empty state with 3 import options
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
                Button {
                    showingImport = true
                } label: {
                    Label("Import from URL", systemImage: "link.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    showingOCRImport = true
                } label: {
                    Label("Scan Recipe Card", systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    showingNewRecipe = true
                } label: {
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
}

///Loads a recipe photo from either a remote https:// URL (via AsyncImage) or a
/// local file:// URL (via UIImage(contentsOfFile:)).  AsyncImage silently fails
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
                        img.resizable().aspectRatio(contentMode: contentMode)
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
