//
//  GoalEditorView.swift
//  BiteLedger
//

import SwiftUI
import BiteLedgerCore

struct GoalEditorView: View {
    let nutrient: Nutrient
    @State var goal: NutrientGoal
    let onSave: (NutrientGoal) -> Void
    let onDelete: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            Section {
                Picker("Goal Type", selection: $goal.goalType) {
                    ForEach(GoalType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                
                HStack {
                    Text("Target")
                    Spacer()
                    TextField("Value", value: $goal.targetValue, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text(nutrient.unit)
                        .foregroundStyle(Color("TextSecondary"))
                }
                
                if goal.goalType == .range {
                    HStack {
                        Text("Maximum")
                        Spacer()
                        TextField("Max", value: Binding(
                            get: { goal.rangeMax ?? goal.targetValue * 1.1 },
                            set: { goal.rangeMax = $0 }
                        ), format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text(nutrient.unit)
                            .foregroundStyle(Color("TextSecondary"))
                    }
                }
            } header: {
                Text("\(nutrient.rawValue) Goal")
            } footer: {
                Text(goalTypeDescription)
            }
            
            Section {
                Button("Delete Goal", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            }
        }
        .navigationTitle("\(nutrient.rawValue)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(goal)
                    dismiss()
                }
            }
        }
    }
    
    private var goalTypeDescription: String {
        switch goal.goalType {
        case .minimum:
            return "Track progress towards meeting at least \(Int(goal.targetValue)) \(nutrient.unit) per day."
        case .maximum:
            return "Track progress staying under \(Int(goal.targetValue)) \(nutrient.unit) per day."
        case .range:
            let max = goal.rangeMax ?? goal.targetValue * 1.1
            return "Track progress staying between \(Int(goal.targetValue))-\(Int(max)) \(nutrient.unit) per day."
        }
    }
}
