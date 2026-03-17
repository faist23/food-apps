//
//  AddFoodView.swift
//  BiteLedger
//
//  Created by Craig Faist on 2/16/26.
//


import SwiftUI
import BiteLedgerCore

struct AddFoodView: View {
    @Environment(\.dismiss) var dismiss
    @State private var showBarcodeScanner = false
    @State private var searchText = ""
    @State private var searchResults: [ProductInfo] = []
    @State private var isSearching = false
    @State private var selectedProduct: ProductInfo?
    @State private var isLoadingProduct = false
    @State private var errorMessage: String?
    
    private let foodService = OpenFoodFactsService.shared
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Search bar
                VStack(alignment: .leading, spacing: 8) {
                    Text("Search Food")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        
                        TextField("Search by name or brand", text: $searchText)
                            .textFieldStyle(.plain)
                            .onSubmit {
                                performSearch()
                            }
                        
                        if isSearching {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else if !searchText.isEmpty {
                            Button {
                                searchText = ""
                                searchResults = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(12)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal)
                
                // Search results or quick actions
                if !searchResults.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(searchResults) { product in
                                ProductSearchRow(product: product)
                                    .onTapGesture {
                                        selectedProduct = product
                                    }
                            }
                        }
                        .padding(.horizontal)
                    }
                } else if isSearching {
                    Spacer()
                    ProgressView("Searching...")
                    Spacer()
                } else if let error = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(error)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                } else {
                    // Quick actions
                    VStack(spacing: 16) {
                        Text("Quick Add")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                        
                        // Barcode scan button
                        Button {
                            showBarcodeScanner = true
                        } label: {
                            HStack {
                                Image(systemName: "barcode.viewfinder")
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                                    .frame(width: 44)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Scan Barcode")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    
                                    Text("Quick add from product barcode")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .padding()
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal)
                        
                        // Manual entry button
                        Button {
                            // TODO: Show manual entry form
                        } label: {
                            HStack {
                                Image(systemName: "pencil")
                                    .font(.title2)
                                    .foregroundStyle(.green)
                                    .frame(width: 44)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Manual Entry")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    
                                    Text("Enter nutrition facts manually")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .padding()
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal)
                    }
                    
                    Spacer()
                }
            }
            .navigationTitle("Add Food")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .fullScreenCover(isPresented: $showBarcodeScanner) {
                BarcodeScannerView { barcode in
                    fetchProductByBarcode(barcode)
                }
            }
            .sheet(item: $selectedProduct) { product in
                ProductDetailView(product: product)
            }
            .overlay {
                if isLoadingProduct {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Loading product...")
                                .font(.headline)
                        }
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
        }
    }
    
    private func performSearch() {
        guard !searchText.isEmpty else { return }
        
        isSearching = true
        errorMessage = nil
        
        Task {
            do {
                searchResults = try await foodService.searchProducts(query: searchText)
                if searchResults.isEmpty {
                    errorMessage = "No products found for '\(searchText)'"
                }
            } catch {
                errorMessage = "Search failed: \(error.localizedDescription)"
                searchResults = []
            }
            isSearching = false
        }
    }
    
    private func fetchProductByBarcode(_ barcode: String) {
        isLoadingProduct = true
        errorMessage = nil
        
        Task {
            do {
                let product = try await foodService.fetchProduct(barcode: barcode)
                selectedProduct = product
            } catch {
                errorMessage = "Failed to load product: \(error.localizedDescription)"
            }
            isLoadingProduct = false
        }
    }
}

// MARK: - Supporting Views

struct ProductSearchRow: View {
    let product: ProductInfo
    
    var body: some View {
        HStack(spacing: 12) {
            // Product image
            if let imageUrl = product.imageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.2)
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(width: 60, height: 60)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
            
            // Product info
            VStack(alignment: .leading, spacing: 4) {
                Text(product.displayName)
                    .font(.headline)
                    .lineLimit(2)
                
                Text(product.displayBrand)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if let nutrition = product.nutriments {
                    Text("\(Int(nutrition.calories)) kcal per 100g")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    AddFoodView()
}