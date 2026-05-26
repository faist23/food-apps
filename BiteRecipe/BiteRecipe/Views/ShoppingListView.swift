//
//  ShoppingListView.swift
//  BiteRecipe
//
//  Categorized in-memory shopping list. Persists for the current app session.
//  Supports check-off, category reclassification, share sheet, and clear-all.
//

import SwiftUI
import UIKit
import BiteLedgerCore

struct ShoppingListView: View {
    @Environment(ShoppingCart.self) private var shoppingCart
    @State private var itemToReclassify: ShoppingCartItem? = nil
    @State private var showingClearConfirm = false
    @State private var activeToast: AppToastModel? = nil

    var body: some View {
        NavigationStack {
            Group {
                if shoppingCart.isEmpty {
                    emptyState
                } else {
                    listContent
                }
            }
            .navigationTitle("Shopping List")
            .toolbar {
                if !shoppingCart.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        HStack(spacing: 4) {
                            Button {
                                UIPasteboard.general.string = shoppingCart.shareText
                                withAnimation { activeToast = .success("Copied to clipboard") }
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .accessibilityLabel("Copy shopping list")

                            ShareLink(
                                item: shoppingCart.shareText,
                                preview: SharePreview("Shopping List")
                            )
                            .accessibilityLabel("Share shopping list")
                        }
                    }

                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Clear All", role: .destructive) {
                            showingClearConfirm = true
                        }
                    }
                }
            }
            .appToast($activeToast)
            .confirmationDialog(
                "Clear shopping list?",
                isPresented: $showingClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear List", role: .destructive) {
                    shoppingCart.clearAll()
                }
            }
            .sheet(item: $itemToReclassify) { item in
                ReclassifySheet(item: item) { newCategory in
                    shoppingCart.moveToCategory(item, to: newCategory)
                }
            }
        }
    }

    // MARK: - List content

    private var listContent: some View {
        List {
            ForEach(ShoppingCategory.allCases) { category in
                let catItems = shoppingCart.items.filter { $0.category == category }
                if !catItems.isEmpty {
                    Section(category.rawValue) {
                        // Unchecked items first, then checked (moved to bottom)
                        let sorted = catItems.sorted { !$0.isChecked && $1.isChecked }
                        ForEach(sorted) { item in
                            ShoppingItemRow(item: item) {
                                shoppingCart.toggleChecked(item)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    let index = shoppingCart.items.firstIndex(where: { $0.id == item.id }) ?? shoppingCart.items.count
                                    shoppingCart.removeItem(item)
                                    withAnimation {
                                        activeToast = .undo("Removed \"\(item.displayText)\"") {
                                            shoppingCart.restoreItem(item, at: index)
                                        }
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    itemToReclassify = item
                                } label: {
                                    Label("Move to…", systemImage: "arrow.right.arrow.left")
                                }
                                .tint(.indigo)
                            }
                            .accessibilityAction(named: "Move to category") {
                                itemToReclassify = item
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "cart")
                .font(.system(size: 56))
                .foregroundStyle(Color.textSecondary)
            VStack(spacing: 6) {
                Text("Your shopping list is empty")
                    .font(.title3.bold())
                Text("Scale a recipe and tap '+ Shopping' to add ingredients.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
            Spacer()
        }
    }
}

// MARK: - ShoppingItemRow

private struct ShoppingItemRow: View {
    let item: ShoppingCartItem
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isChecked ? Color.brandPrimary : Color.textSecondary)
                    .frame(minWidth: 44, minHeight: 44)

                Text(item.displayText)
                    .font(.body)
                    .foregroundStyle(item.isChecked ? Color.textTertiary : Color.textPrimary)
                    .strikethrough(item.isChecked, color: Color.textTertiary)

                Spacer()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.displayText), \(item.isChecked ? "checked" : "unchecked")")
        .accessibilityHint("Double-tap to toggle")
    }
}

// MARK: - ReclassifySheet

private struct ReclassifySheet: View {
    let item: ShoppingCartItem
    let onSelect: (ShoppingCategory) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(ShoppingCategory.allCases) { category in
                Button {
                    onSelect(category)
                    dismiss()
                } label: {
                    HStack {
                        Text(category.rawValue)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        if category == item.category {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.brandPrimary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Move to Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
