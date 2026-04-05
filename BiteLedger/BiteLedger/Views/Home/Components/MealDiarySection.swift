//
//  MealDiarySection.swift
//  BiteLedger
//
//  Created by Craig Faist on 2/19/26.
//


import SwiftUI
import SwiftData
import BiteLedgerCore

struct MealDiarySection: View {
    
    let meal: MealType
    let logs: [FoodLog]
    let calories: Double
    let selectedDate: Date
    let hasYesterdayMeal: Bool
    let yesterdayCalories: Double

    let onAddFood: () -> Void
    let onEditLog: (FoodLog) -> Void
    let onDeleteLog: (FoodLog) -> Void
    let onTapMeal: () -> Void
    let onCopyYesterday: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            header

            if logs.isEmpty {
                emptyState
            } else {
                foodList
            }
        }
    }
}

struct SwipeableYesterdayRow: View {
    let meal: MealType
    let calories: Double
    let onAdd: () -> Void
    let selectedDate: Date
    
    @State private var offset: CGFloat = 0
    private let addThreshold: CGFloat = 120  // Swipe past this to auto-add
    
    private var relativeDayText: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let selected = calendar.startOfDay(for: selectedDate)
        
        let daysDiff = calendar.dateComponents([.day], from: selected, to: today).day ?? 0
        
        if daysDiff == 1 {
            return "Yesterday's"
        } else if daysDiff > 1 {
            return "Previous Day's"
        } else {
            return "Yesterday's" // Fallback
        }
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            // BrandPrimary background fills the full revealed area as user swipes
            HStack(spacing: 0) {
                Color.brandPrimary
                    .frame(maxWidth: max(offset, 0))
                Spacer(minLength: 0)
            }

            // Add button pinned to the left edge
            HStack {
                Button(action: {
                    onAdd()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation {
                            offset = 0
                        }
                    }
                }) {
                    Text("Add")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 80)
                }
                .frame(maxHeight: .infinity)
                .background(Color.brandPrimary)

                Spacer()
            }
            
            // Main content
            VStack(alignment: .leading, spacing: 4) {
                Text("Add \(relativeDayText) \(meal.rawValue), \(Int(calories)) calories")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textPrimary)
                
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                    Text("Swipe right to add meal")
                        .font(.system(size: 11))
                }
                .foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.dividerSubtle, lineWidth: 1)
            )
            .offset(x: offset)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        // Only respond to mostly horizontal swipes
                        let horizontalAmount = abs(value.translation.width)
                        let verticalAmount = abs(value.translation.height)
                        
                        if horizontalAmount > verticalAmount {
                            if value.translation.width > 0 {
                                // Allow swiping past the threshold for auto-add
                                offset = min(value.translation.width, addThreshold + 20)
                            } else if offset > 0 {
                                offset = max(0, offset + value.translation.width)
                            }
                        }
                    }
                    .onEnded { value in
                        let horizontalAmount = abs(value.translation.width)
                        let verticalAmount = abs(value.translation.height)
                        
                        // Only snap if it was a horizontal swipe
                        if horizontalAmount > verticalAmount {
                            if offset >= addThreshold {
                                // Swiped far enough - auto-add!
                                onAdd()
                                // Delay resetting offset so user sees the action happened
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    withAnimation {
                                        offset = 0
                                    }
                                }
                            } else if offset > 40 {
                                // Show the add button
                                withAnimation {
                                    offset = 80
                                }
                            } else {
                                // Reset to closed
                                withAnimation {
                                    offset = 0
                                }
                            }
                        }
                    }
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Subviews

private extension MealDiarySection {

    var header: some View {
        HStack {
            Label {
                Text(meal.rawValue.uppercased())
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.textPrimary)
            } icon: {
                Image(systemName: meal.icon)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            if !logs.isEmpty {
                Text("\(Int(calories))")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !logs.isEmpty {
                onTapMeal()
            }
        }
    }

    var emptyState: some View {
        VStack(spacing: 0) {
            if hasYesterdayMeal {
                SwipeableYesterdayRow(
                    meal: meal,
                    calories: yesterdayCalories,
                    onAdd: {
                        onCopyYesterday()
                    },
                    selectedDate: selectedDate
                )
                
                Divider()
                    .background(Color.dividerSubtle)
                    .padding(.vertical, 8)
            }
            
            Button(action: onAddFood) {
                HStack {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                    Text("Add Food")
                        .font(.system(size: 13))
                    Spacer()
                }
                .foregroundStyle(Color.brandPrimary)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.surfaceCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.dividerSubtle, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    var foodList: some View {
        VStack(spacing: 0) {
            ForEach(logs) { log in
                SwipeableFoodRow(
                    log: log,
                    onEdit: { onEditLog(log) },
                    onDelete: { onDeleteLog(log) }
                )
                
                if log.id != logs.last?.id {
                    Divider()
                        .background(Color.dividerSubtle)
                }
            }
            
            Button(action: onAddFood) {
                HStack {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                    Text("Add Food")
                        .font(.system(size: 13))
                    Spacer()
                }
                .foregroundStyle(Color.brandPrimary)
                .padding(.top, 8)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.surfaceCard)
                .shadow(
                    color: Color.black.opacity(0.3),
                    radius: 8,
                    x: 0,
                    y: 4
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.dividerSubtle, lineWidth: 1)
        )
    }
}

struct FoodRow: View {

    let log: FoodLog
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(log.foodItem?.name ?? "Unknown Food")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                Text(log.quantityDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            Text("\(Int(log.caloriesAtLogTime))")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
        }
    }
}
struct SwipeableFoodRow: View {
    let log: FoodLog
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var dragStartX: CGFloat = 0

    private let revealWidth: CGFloat = 70
    private let deleteThreshold: CGFloat = 150

    var body: some View {
        ZStack(alignment: .trailing) {
            // Red background fills the full revealed area as user swipes
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Color.red
                    .frame(maxWidth: max(-offset, 0))
            }

            // Trash icon pinned to the right edge
            HStack {
                Spacer()
                Image(systemName: "trash")
                    .foregroundStyle(.white)
                    .frame(width: revealWidth)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation { offset = 0 }
                        onDelete()
                    }
            }

            // Main content
            FoodRow(log: log, onEdit: onEdit, onDelete: onDelete)
                .background(Color.surfaceCard)
                .offset(x: offset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            let horizontalAmount = abs(value.translation.width)
                            let verticalAmount = abs(value.translation.height)

                            if horizontalAmount > verticalAmount {
                                if value.translation.width < 0 {
                                    // Allow swiping past deleteThreshold for auto-delete
                                    offset = max(value.translation.width, -(deleteThreshold + 20))
                                } else if offset < 0 {
                                    offset = min(0, offset + value.translation.width)
                                }
                            }
                        }
                        .onEnded { value in
                            let horizontalAmount = abs(value.translation.width)
                            let verticalAmount = abs(value.translation.height)

                            if horizontalAmount > verticalAmount {
                                if offset < -deleteThreshold {
                                    // Swiped far enough — auto-delete
                                    withAnimation {
                                        offset = -(deleteThreshold + 20)
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        onDelete()
                                    }
                                } else if offset < -35 {
                                    // Snap to reveal the trash button
                                    withAnimation {
                                        offset = -revealWidth
                                    }
                                } else {
                                    withAnimation {
                                        offset = 0
                                    }
                                }
                            }
                        }
                )
        }
    }
}

