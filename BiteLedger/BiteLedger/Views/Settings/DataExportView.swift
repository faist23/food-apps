//
//  DataExportView.swift
//  BiteLedger
//
//  Created by Claude on 2/20/26.
//

import SwiftUI
import SwiftData
import BiteLedgerCore

struct DataExportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \FoodLog.timestamp, order: .reverse) private var allLogs: [FoodLog]
    @Query(sort: \FoodItem.name) private var allFoods: [FoodItem]
    @Query(sort: \Recipe.dateAdded) private var allRecipes: [Recipe]
    
    @State private var exportType: ExportType = .logsOnly
    @State private var exportRange: ExportRange = .all
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var isExporting = false
    @State private var exportedFileURLs: [URL] = []
    @State private var showingShareSheet = false
    @State private var errorMessage: String?
    @State private var showingError = false

    enum ExportType: String, CaseIterable, Identifiable {
        case logsOnly = "Food Logs Only (CSV)"
        case complete = "Complete Database (5 CSV Files)"

        var id: String { rawValue }
    }
    
    enum ExportRange: String, CaseIterable, Identifiable {
        case all = "All Data"
        case lastWeek = "Last 7 Days"
        case lastMonth = "Last 30 Days"
        case lastThreeMonths = "Last 3 Months"
        case custom = "Custom Date Range"
        
        var id: String { rawValue }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header icon
                Image(systemName: "square.and.arrow.up.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)
                    .padding(.top, 40)
                
                VStack(spacing: 12) {
                    Text("Export Your Data")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text(exportType == .complete ? "Export complete database with foods, portions, and recipes" : "Export your food logs as a CSV file")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Export options
                VStack(alignment: .leading, spacing: 16) {
                    Text("Export Type:")
                        .font(.headline)
                    
                    Picker("Type", selection: $exportType) {
                        ForEach(ExportType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    
                    if exportType == .logsOnly {
                        Text("Select Date Range:")
                            .font(.headline)
                        
                        Picker("Range", selection: $exportRange) {
                            ForEach(ExportRange.allCases) { range in
                                Text(range.rawValue).tag(range)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }
                    
                    if exportType == .logsOnly && exportRange == .custom {
                        VStack(spacing: 12) {
                            DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                            DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }
                    
                    // Stats
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundStyle(.orange)
                        if exportType == .complete {
                            Text("\(allLogs.count) log entries, \(allFoods.count) foods, \(totalPortions) portions, \(totalRecipes) recipes")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(filteredLogsCount) entries will be exported")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                
                Spacer()
                
                // Export button
                Button {
                    exportData()
                } label: {
                    HStack {
                        if isExporting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: exportType == .complete ? "arrow.down.doc.fill" : "arrow.down.doc.fill")
                        }
                        Text(isExporting ? "Exporting..." : (exportType == .complete ? "Export Complete Database" : "Export to CSV"))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isExporting ? Color.gray : Color.green)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }
                .disabled(isExporting || (exportType == .logsOnly && filteredLogsCount == 0))
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet, onDismiss: { dismiss() }) {
                ShareSheet(items: exportedFileURLs)
            }
            .alert("Export Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
        }
    }
    
    private var filteredLogsCount: Int {
        getFilteredLogs().count
    }
    
    private var totalPortions: Int {
        allFoods.reduce(0) { $0 + $1.servingSizes.count }
    }

    private var totalRecipes: Int { allRecipes.count }
    
    private func getFilteredLogs() -> [FoodLog] {
        let calendar = Calendar.current
        let now = Date()
        
        switch exportRange {
        case .all:
            return allLogs
        case .lastWeek:
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return allLogs.filter { $0.timestamp >= weekAgo }
        case .lastMonth:
            let monthAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            return allLogs.filter { $0.timestamp >= monthAgo }
        case .lastThreeMonths:
            let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now) ?? now
            return allLogs.filter { $0.timestamp >= threeMonthsAgo }
        case .custom:
            let startOfDay = calendar.startOfDay(for: startDate)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)) ?? endDate
            return allLogs.filter { $0.timestamp >= startOfDay && $0.timestamp < endOfDay }
        }
    }
    
    private func exportData() {
        isExporting = true
        errorMessage = nil
        
        Task {
            do {
                let _: URL
                
                let fileURLs: [URL]

                if exportType == .complete {
                    let package = try await MainActor.run {
                        try CSVExporter.exportAll(context: modelContext)
                    }

                    let tempDir = FileManager.default.temporaryDirectory
                        .appendingPathComponent(package.filePrefix)
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

                    let foodsURL       = tempDir.appendingPathComponent("\(package.filePrefix)_foods.csv")
                    let servingsURL    = tempDir.appendingPathComponent("\(package.filePrefix)_servings.csv")
                    let logsURL        = tempDir.appendingPathComponent("\(package.filePrefix)_logs.csv")
                    let recipesURL     = tempDir.appendingPathComponent("\(package.filePrefix)_recipes.csv")
                    let ingredientsURL = tempDir.appendingPathComponent("\(package.filePrefix)_ingredients.csv")

                    try package.foodsCSV.write(to: foodsURL, atomically: true, encoding: .utf8)
                    try package.servingsCSV.write(to: servingsURL, atomically: true, encoding: .utf8)
                    try package.logsCSV.write(to: logsURL, atomically: true, encoding: .utf8)
                    try package.recipesCSV.write(to: recipesURL, atomically: true, encoding: .utf8)
                    try package.ingredientsCSV.write(to: ingredientsURL, atomically: true, encoding: .utf8)

                    var urls: [URL] = [foodsURL, servingsURL, logsURL, recipesURL, ingredientsURL]

                    // Write local recipe images as {uuid}.jpg files
                    if !package.recipeImages.isEmpty {
                        let imagesDir = tempDir.appendingPathComponent("images")
                        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
                        for (filename, data) in package.recipeImages {
                            let imgURL = imagesDir.appendingPathComponent(filename)
                            try data.write(to: imgURL)
                            urls.append(imgURL)
                        }
                    }

                    fileURLs = urls
                } else {
                    let logs = getFilteredLogs()
                    let csvString = CSVExporter.exportLogs(logs)
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("BiteLedger_logs_\(Int(Date().timeIntervalSince1970)).csv")
                    try csvString.write(to: tempURL, atomically: true, encoding: .utf8)
                    fileURLs = [tempURL]
                }

                await MainActor.run {
                    exportedFileURLs = fileURLs
                    isExporting = false
                    showingShareSheet = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isExporting = false
                    showingError = true
                }
            }
        }
    }
}

// Share sheet wrapper for UIActivityViewController
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    DataExportView()
}
