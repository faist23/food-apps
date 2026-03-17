import SwiftUI
import BiteLedgerCore

/// Debug view to test search
struct SearchDebugView: View {
    @State private var searchText = "honey"
    @State private var results: String = ""
    @State private var isSearching = false
    
    private let foodService = OpenFoodFactsService.shared
    
    var body: some View {
        VStack(spacing: 20) {
            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding()
            
            Button("Search") {
                performSearch()
            }
            .buttonStyle(.bordered)
            
            if isSearching {
                ProgressView("Searching...")
            }
            
            ScrollView {
                Text(results)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
    }
    
    private func performSearch() {
        isSearching = true
        results = "Searching..."
        
        Task {
            do {
                let products = try await foodService.searchProducts(query: searchText)
                
                await MainActor.run {
                    var output = "Found \(products.count) products:\n\n"
                    
                    for (index, product) in products.prefix(5).enumerated() {
                        output += "[\(index + 1)] \(product.displayName)\n"
                        output += "Code: \(product.code)\n"
                        
                        if let n = product.nutriments {
                            output += "Calories: \(n.calories)\n"
                            output += "  energyKcal100g: \(n.energyKcal100g?.value ?? 0)\n"
                            output += "  energyKcalComputed: \(n.energyKcalComputed ?? 0)\n"
                            output += "  Protein: \(n.proteins100g?.value ?? 0)\n"
                            output += "  Carbs: \(n.carbohydrates100g?.value ?? 0)\n"
                            output += "  Fat: \(n.fat100g?.value ?? 0)\n"
                        } else {
                            output += "NO NUTRIMENTS\n"
                        }
                        output += "\n"
                    }
                    
                    let filtered = products.filter { 
                        if let nutriments = $0.nutriments {
                            return nutriments.calories > 0
                        }
                        return false
                    }
                    
                    output += "\n\nAfter filtering (calories > 0): \(filtered.count) products\n"
                    
                    results = output
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    results = "Error: \(error.localizedDescription)"
                    isSearching = false
                }
            }
        }
    }
}

#Preview {
    SearchDebugView()
}
