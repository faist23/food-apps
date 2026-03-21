//
//  LoseItImportView.swift
//  BiteLedger
//
//  Created by Claude on 2/20/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import BiteLedgerCore

struct LoseItImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var importType: ImportType = .logsOnly
    @State private var isImporting = false
    @State private var showingPicker = false
    @State private var importResult: CSVImporter.ImportResult?
    @State private var completeImportResult: CompleteDatabaseImporter.ImportResult?
    @State private var errorMessage: String?
    @State private var showingResult = false
    @State private var showingErrorDetails = false
    
    enum ImportType: String, CaseIterable, Identifiable {
        case logsOnly = "Food Logs Only (Single CSV)"
        case complete = "Complete Database (5 CSV Files + Images)"

        var id: String { rawValue }
    }

    private var buttonText: String {
        if isImporting {
            return "Importing..."
        } else if importType == .complete {
            return "Select All Exported Files"
        } else {
            return "Select CSV File"
        }
    }

    private var descriptionText: String {
        importType == .complete ? "Import complete database from a BiteLedger export" : "Import your food logs from a CSV file"
    }

    private var buttonIcon: String {
        importType == .complete ? "doc.on.doc.fill" : "doc.fill"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header icon
                Image(systemName: "square.and.arrow.down.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)
                    .padding(.top, 40)
                
                VStack(spacing: 12) {
                    Text("Import Data")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text(descriptionText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Instructions
                VStack(alignment: .leading, spacing: 16) {
                    Text("Import Type:")
                        .font(.headline)
                    
                    Picker("Type", selection: $importType) {
                        ForEach(ImportType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    
                    if importType == .complete {
                        Text("Select all files from your BiteLedger export: the 5 CSV files and any recipe image files (.jpg).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Supported Formats:")
                            .font(.subheadline)
                        
                        InstructionRow(number: "✓", text: "BiteLedger CSV exports")
                        InstructionRow(number: "✓", text: "LoseIt CSV exports")
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                
                Spacer()
                
                // Import button
                Button {
                    showingPicker = true
                } label: {
                    HStack {
                        if isImporting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: buttonIcon)
                        }
                        Text(buttonText)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isImporting ? Color.gray : Color.orange)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }
                .disabled(isImporting)
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
            .navigationTitle("Import Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showingPicker,
                allowedContentTypes: importType == .complete
                    ? [.commaSeparatedText, .text, .jpeg, .png, .heic]
                    : [.commaSeparatedText, .text],
                allowsMultipleSelection: importType == .complete
            ) { result in
                if importType == .complete {
                    handleMultiFileSelection(result)
                } else {
                    handleFileSelection(result)
                }
            }
            .alert("Import Complete", isPresented: $showingResult) {
                Button("OK") {
                    let hasSuccess = (importResult?.logsCreated ?? 0 > 0) || (completeImportResult?.foodsImported ?? 0 > 0)
                    if hasSuccess {
                        dismiss()
                    }
                }
                if let result = importResult, !result.errors.isEmpty {
                    Button("View Errors") {
                        showingErrorDetails = true
                    }
                }
                if let result = completeImportResult, !result.errors.isEmpty {
                    Button("View Errors") {
                        showingErrorDetails = true
                    }
                }
            } message: {
                if let result = importResult {
                    Text("Successfully imported \(result.logsCreated) log entries.\nFoods created: \(result.foodsCreated)")
                } else if let result = completeImportResult {
                    Text("Successfully imported:\n\(result.foodsImported) foods\n\(result.portionsImported) portions\n\(result.logsImported) log entries")
                } else if let error = errorMessage {
                    Text("Error: \(error)")
                }
            }
            .sheet(isPresented: $showingErrorDetails) {
                ErrorDetailsView(errors: importResult?.errors ?? [])
            }
            .overlay {
                if isImporting {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 20) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            
                            Text("Importing data...")
                                .font(.headline)
                                .foregroundStyle(.white)
                            
                            Text("This may take a few moments")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(40)
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(20)
                    }
                }
            }
        }
    }
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importCSVFile(url)
        case .failure(let error):
            errorMessage = error.localizedDescription
            showingResult = true
        }
    }
    
    private func handleMultiFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            importCompleteDatabase(from: urls)
        case .failure(let error):
            errorMessage = error.localizedDescription
            showingResult = true
        }
    }

    private func importCSVFile(_ url: URL) {
        isImporting = true
        errorMessage = nil
        importResult = nil
        
        Task {
            do {
                // Get access to the file
                let gotAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if gotAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                
                let csvString = try String(contentsOf: url, encoding: .utf8)
                let result = try CSVImporter.importAuto(csvString: csvString, context: modelContext)
                
                await MainActor.run {
                    importResult = result
                    isImporting = false
                    showingResult = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isImporting = false
                    showingResult = true
                }
            }
        }
    }
    
    private func importCompleteDatabase(from urls: [URL]) {
        isImporting = true
        errorMessage = nil
        completeImportResult = nil

        Task {
            do {
                let gotAccesses = urls.map { $0.startAccessingSecurityScopedResource() }
                defer {
                    for (url, got) in zip(urls, gotAccesses) where got {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                // Auto-detect which file is which by inspecting CSV headers.
                // Supports the legacy 3-file format, the current 5-file format,
                // and optional recipe image files ({uuid}.jpg).
                var foodsCSV: String?
                var servingsCSV: String?
                var logsCSV: String?
                var recipesCSV: String?
                var ingredientsCSV: String?
                // Image map: recipe UUID string → JPEG data
                var imageMap: [String: Data] = [:]

                for url in urls {
                    let ext = url.pathExtension.lowercased()

                    // Image file — filename is "{uuid}.jpg"
                    if ext == "jpg" || ext == "jpeg" || ext == "png" || ext == "heic" {
                        let uuidString = url.deletingPathExtension().lastPathComponent
                        if let data = try? Data(contentsOf: url), !uuidString.isEmpty {
                            imageMap[uuidString] = data
                        }
                        continue
                    }

                    let csv = try String(contentsOf: url, encoding: .utf8)
                    let firstLine = csv.components(separatedBy: .newlines).first?.lowercased() ?? ""
                    if firstLine.contains("caloriesatlogtime") {
                        logsCSV = csv
                    } else if firstLine.contains("nutritionmode") {
                        foodsCSV = csv
                    } else if firstLine.contains("gramweight") || firstLine.contains("isdefault") {
                        servingsCSV = csv
                    } else if firstLine.contains("servingsyield") || firstLine.contains("recipecategory") {
                        recipesCSV = csv
                    } else if firstLine.contains("recipeid") || firstLine.contains("recipeunit") {
                        ingredientsCSV = csv
                    }
                }

                guard let foods = foodsCSV else {
                    throw NSError(domain: "BiteLedger", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Could not find foods CSV. Make sure you select the _foods.csv file."])
                }
                guard let servings = servingsCSV else {
                    throw NSError(domain: "BiteLedger", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Could not find servings CSV. Make sure you select the _servings.csv file."])
                }
                guard let logs = logsCSV else {
                    throw NSError(domain: "BiteLedger", code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "Could not find logs CSV. Make sure you select the _logs.csv file."])
                }

                let csvResult = try await MainActor.run {
                    try CSVImporter.importBiteLedger(
                        foodsCSV: foods,
                        servingsCSV: servings,
                        logsCSV: logs,
                        recipesCSV: recipesCSV,
                        ingredientsCSV: ingredientsCSV,
                        imageMap: imageMap,
                        context: modelContext
                    )
                }

                await MainActor.run {
                    completeImportResult = CompleteDatabaseImporter.ImportResult(
                        foodsImported: csvResult.foodsCreated,
                        portionsImported: csvResult.servingsCreated,
                        logsImported: csvResult.logsCreated,
                        errors: csvResult.errors
                    )
                    isImporting = false
                    showingResult = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isImporting = false
                    showingResult = true
                }
            }
        }
    }
}

struct InstructionRow: View {
    let number: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.orange)
                .clipShape(Circle())
            
            Text(text)
                .font(.subheadline)
            
            Spacer()
        }
    }
}

struct ErrorDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    let errors: [String]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if errors.isEmpty {
                        Text("No errors to display")
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        ForEach(Array(errors.enumerated()), id: \.offset) { index, error in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Error \(index + 1)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.orange)
                                
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Import Errors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    LoseItImportView()
}
