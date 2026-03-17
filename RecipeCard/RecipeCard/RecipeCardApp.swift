//
//  RecipeCardApp.swift
//  RecipeCard
//
//  Created by Craig Faist on 3/14/26.
//

import SwiftUI
import SwiftData
import UIKit
import BiteLedgerCore

extension Notification.Name {
    static let recipeCardImportURL = Notification.Name("recipeCardImportURL")
}

@main
struct RecipeCardApp: App {

    var sharedModelContainer: ModelContainer = {
        // Shared App Group container — same store as BiteLedger
        let schema = Schema([
            FoodItem.self,
            ServingSize.self,
            FoodLog.self,
            UserPreferences.self,
            Recipe.self,
            RecipeIngredient.self,
            CanonicalFood.self,
            ServingConversion.self,
            FallbackSource.self,
        ])
        let groupID = "group.com.ridepro.biteledger"
        let storeURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)!
            .appendingPathComponent("biteledger.store")
        let config = ModelConfiguration(schema: schema, url: storeURL)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create shared ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RecipeCardRootView()
                .modifier(SeedingModifier(container: sharedModelContainer))
                .onOpenURL { url in
                    // Launched via recipecard://import from the Share Extension.
                    // The extension already wrote the URL to shared UserDefaults.
                    guard url.scheme == "recipecard", url.host == "import" else { return }
                    consumePendingRecipeURL()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    // Also check when returning to foreground in case the app was already open.
                    consumePendingRecipeURL()
                }
        }
        .modelContainer(sharedModelContainer)
    }

    private func consumePendingRecipeURL() {
        let defaults = UserDefaults(suiteName: "group.com.ridepro.biteledger")
        guard let urlString = defaults?.string(forKey: "pendingRecipeURL"),
              let url = URL(string: urlString) else { return }
        // Do NOT remove the key here — ImportRecipeView reads it directly on appear
        // and removes it there, avoiding a race where the key is gone before the view loads.
        NotificationCenter.default.post(
            name: .recipeCardImportURL,
            object: nil,
            userInfo: ["url": url]
        )
    }
}

private struct SeedingModifier: ViewModifier {
    let container: ModelContainer
    @State private var seedingProgress: (current: Int, total: Int)? = nil

    func body(content: Content) -> some View {
        ZStack {
            content
                .task {
                    await IngredientSeeder.seedIfNeeded(container: container) { current, total in
                        seedingProgress = (current, total)
                    }
                    seedingProgress = nil
                    await CanonicalFoodSeeder.seedIfNeeded(container: container)
                }

            if let progress = seedingProgress {
                IngredientSeedingOverlay(current: progress.current, total: progress.total)
            }
        }
    }
}

private struct IngredientSeedingOverlay: View {
    let current: Int
    let total: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView(value: Double(current), total: Double(max(total, 1)))
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .frame(width: 240)
                Text("Building ingredient database…")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("\(current) of \(total)")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}
