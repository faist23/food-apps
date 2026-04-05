//
//  BiteRecipeApp.swift
//  BiteRecipe
//
//  Created by Craig Faist on 3/14/26.
//

import SwiftUI
import SwiftData
import UIKit
import BiteLedgerCore

extension Notification.Name {
    static let biteRecipeImportURL = Notification.Name("biteRecipeImportURL")
}

// E-2: App store error types for graceful failure handling.
enum BiteRecipeError: LocalizedError {
    case appGroupNotConfigured(String)

    var errorDescription: String? {
        switch self {
        case .appGroupNotConfigured(let id):
            return "App Group '\(id)' is not configured. Please reinstall the app or contact support if this persists."
        }
    }
}

// E-2: Graceful error screen replacing fatalError for store init failures.
private struct BiteRecipeErrorView: View {
    let error: Error
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.orange)
            Text("Unable to Load Data")
                .font(.title2.bold())
            Text(error.localizedDescription)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button("Retry", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }
}

@main
struct BiteRecipeApp: App {
    // E-2: State-driven container — no fatalError or force-unwrap on failure.
    @State private var modelContainer: ModelContainer?
    @State private var storeError: Error?
    @State private var shoppingCart = ShoppingCart()

    var body: some Scene {
        WindowGroup {
            Group {
                if let error = storeError {
                    BiteRecipeErrorView(error: error) {
                        storeError = nil
                        loadContainer()
                    }
                } else if let container = modelContainer {
                    BiteRecipeRootView()
                        .environment(shoppingCart)
                        .modifier(SeedingModifier(container: container))
                        .modelContainer(container)
                        .onOpenURL { url in
                            // Launched via biterecipe://import from the Share Extension.
                            // The extension already wrote the URL to shared UserDefaults.
                            guard url.scheme == "biterecipe", url.host == "import" else { return }
                            consumePendingRecipeURL()
                        }
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                            // Also check when returning to foreground in case the app was already open.
                            consumePendingRecipeURL()
                        }
                } else {
                    Color.surfacePrimary
                        .ignoresSafeArea()
                        .task { loadContainer() }
                }
            }
        }
    }

    @MainActor
    private func loadContainer() {
        let groupID = "group.com.ridepro.biteledger"
        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            storeError = BiteRecipeError.appGroupNotConfigured(groupID)
            return
        }
        let storeURL = containerURL.appendingPathComponent("biteledger.store")
        do {
            let schema = Schema(versionedSchema: BiteRecipeSchemaV4.self)
            let config = ModelConfiguration(schema: schema, url: storeURL)
            // NOTE: migrationPlan intentionally omitted — see BiteLedgerApp.swift for explanation.
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            storeError = error
        }
    }

    private func consumePendingRecipeURL() {
        let defaults = UserDefaults(suiteName: "group.com.ridepro.biteledger")
        guard let urlString = defaults?.string(forKey: "pendingRecipeURL"),
              let url = URL(string: urlString) else { return }
        // Do NOT remove the key here — ImportRecipeView reads it directly on appear
        // and removes it there, avoiding a race where the key is gone before the view loads.
        NotificationCenter.default.post(
            name: .biteRecipeImportURL,
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
