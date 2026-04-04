//
//  SettingsView.swift
//  BiteRecipe
//
//  App settings sheet for BiteRecipe. Presented from RecipesListView
//  via the gear icon in the [•••] toolbar menu.
//

import SwiftUI
import BiteLedgerCore

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        BackupRestoreView()
                    } label: {
                        HStack {
                            Image(systemName: "externaldrive.fill")
                                .foregroundStyle(Color("BrandPrimary"))
                            Text("Backup & Restore")
                                .foregroundStyle(.primary)
                        }
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Export all your recipes as a backup, or restore from a previous backup.")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
