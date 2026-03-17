//
//  MealSection.swift
//  BiteLedger
//
//  Created by Craig Faist on 2/16/26.
//


import SwiftUI
import SwiftData
import BiteLedgerCore

struct MealSection: View {
    let meal: MealType
    let logs: [FoodLog]
    
    private var totalCalories: Double {
        logs.reduce(0) { $0 + $1.caloriesAtLogTime }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(meal.rawValue, systemImage: meal.icon)
                    .font(.headline)
                
                Spacer()
                
                if !logs.isEmpty {
                    Text("\(Int(totalCalories)) cal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            if logs.isEmpty {
                Text("No items logged")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                ForEach(logs) { log in
                    FoodLogRow(log: log)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct FoodLogRow: View {
    let log: FoodLog
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(log.foodItem?.name ?? "Unknown Food")
                    .font(.subheadline)
                
                Text(log.quantityDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text("\(Int(log.caloriesAtLogTime)) cal")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    MealSection(
        meal: .breakfast,
        logs: []
    )
    .padding()
}