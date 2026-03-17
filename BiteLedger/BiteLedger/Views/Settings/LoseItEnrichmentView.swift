//
//  LoseItEnrichmentView.swift
//  BiteLedger
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import BiteLedgerCore

// MARK: - Main Enrichment View

struct LoseItEnrichmentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @StateObject private var service = LoseItEnrichmentService()

    // Phase 1 state
    @State private var showingFilePicker = false
    @State private var csvString: String?
    @State private var uniqueFoods: [LoseItUniqueFood] = []
    @State private var fileError: String?

    // Phase 4 import state
    @State private var isImporting = false
    @State private var importResult: CSVImporter.ImportResult?
    @State private var importError: String?

    // Review detail sheet
    @State private var reviewingMatch: EnrichmentMatch?

    var body: some View {
        NavigationStack {
            Group {
                switch service.phase {
                case .idle:
                    idleView
                case .searching:
                    searchingView
                case .reviewing:
                    reviewingView
                case .done:
                    doneView
                }
            }
            .navigationTitle("Enriched LoseIt Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        service.cancelSearch()
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.commaSeparatedText, .text],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
            .sheet(item: $reviewingMatch) { match in
                MatchDetailView(match: match, service: service)
            }
        }
    }

    // MARK: Phase 1 — Idle / file selection

    private var idleView: some View {
        ScrollView {
            VStack(spacing: 28) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.indigo)
                    .padding(.top, 40)

                VStack(spacing: 10) {
                    Text("Enriched Import")
                        .font(.title2).fontWeight(.bold)
                    Text("Import your LoseIt history and automatically match each food to the USDA database to add micronutrient data (vitamins, minerals, and more).")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                VStack(alignment: .leading, spacing: 14) {
                    stepRow(number: "1", text: "Select your LoseIt export CSV")
                    stepRow(number: "2", text: "USDA + FatSecret searched for each unique food")
                    if ClaudeMatchingService.fromPlist() != nil {
                        stepRow(number: "3", text: "Claude AI picks the best match for ambiguous foods")
                    } else {
                        stepRow(number: "3", text: "Add claude.plist API key to enable AI auto-matching")
                    }
                    stepRow(number: "4", text: "Review any remaining uncertain matches")
                    stepRow(number: "5", text: "Import with full micronutrient data")
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)

                if let error = fileError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                Spacer(minLength: 20)

                Button {
                    showingFilePicker = true
                } label: {
                    Label("Select LoseIt CSV", systemImage: "doc.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.indigo)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
        }
    }

    private func stepRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.caption).fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.indigo)
                .clipShape(Circle())
            Text(text)
                .font(.subheadline)
            Spacer()
        }
    }

    // MARK: Phase 2 — Searching

    private var searchingView: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.indigo)

            VStack(spacing: 12) {
                Text("Searching USDA Database")
                    .font(.title3).fontWeight(.semibold)
                Text(service.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            ProgressView(value: service.progress)
                .tint(.indigo)
                .padding(.horizontal, 40)

            Text("\(Int(service.progress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button(role: .cancel) {
                service.cancelSearch()
            } label: {
                Text("Cancel Search")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
    }

    // MARK: Phase 3 — Reviewing

    private var reviewingView: some View {
        VStack(spacing: 0) {
            // Summary bar
            HStack(spacing: 10) {
                summaryBadge(count: service.autoMatchedMatches.count, label: "USDA", color: .green)
                summaryBadge(count: service.fatSecretMatchedMatches.count, label: "FatSecret", color: .blue)
                summaryBadge(count: service.manuallyEnrichedMatches.count, label: "Manual", color: .purple)
                summaryBadge(count: service.needsReviewMatches.count, label: "Review", color: .orange)
                summaryBadge(count: service.noMatchMatches.count, label: "No Match", color: .secondary)
            }
            .padding()
            .background(Color(.systemGray6))

            List {
                // Needs review — always expanded
                if !service.needsReviewMatches.isEmpty {
                    Section {
                        ForEach(service.needsReviewMatches) { match in
                            MatchReviewRow(match: match, service: service) {
                                reviewingMatch = match
                            }
                        }
                    } header: {
                        Label("Needs Review", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                // Auto-matched — collapsible via disclosure
                if !service.autoMatchedMatches.isEmpty {
                    Section {
                        ForEach(service.autoMatchedMatches) { match in
                            MatchSummaryRow(match: match)
                        }
                    } header: {
                        Label("USDA Matched (\(service.autoMatchedMatches.count))", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                // FatSecret matched
                if !service.fatSecretMatchedMatches.isEmpty {
                    Section {
                        ForEach(service.fatSecretMatchedMatches) { match in
                            FatSecretMatchRow(match: match, service: service) {
                                reviewingMatch = match
                            }
                        }
                    } header: {
                        Label("FatSecret Matched (\(service.fatSecretMatchedMatches.count))", systemImage: "f.circle.fill")
                            .foregroundStyle(.blue)
                    }
                }

                // No match
                if !service.noMatchMatches.isEmpty {
                    Section {
                        ForEach(service.noMatchMatches) { match in
                            NoMatchRow(match: match, service: service) {
                                reviewingMatch = match
                            }
                        }
                    } header: {
                        Label("No Match (\(service.noMatchMatches.count))", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }

                // Manually entered
                if !service.manuallyEnrichedMatches.isEmpty {
                    Section {
                        ForEach(service.manuallyEnrichedMatches) { match in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(match.food.name).font(.subheadline)
                                    Text("Manually entered").font(.caption).foregroundStyle(.purple)
                                }
                                Spacer()
                                Button("Edit") { reviewingMatch = match }
                                    .buttonStyle(EnrichmentActionStyle(color: .purple))
                            }
                        }
                    } header: {
                        Label("Manually Entered (\(service.manuallyEnrichedMatches.count))", systemImage: "pencil.circle.fill")
                            .foregroundStyle(.purple)
                    }
                }
            }
            .listStyle(.insetGrouped)

            // Import bar
            VStack(spacing: 0) {
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(service.enrichedCount) foods enriched")
                            .font(.subheadline).fontWeight(.semibold)
                        Text("\(service.skippedCount) will import without micros")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        performImport()
                    } label: {
                        if isImporting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Import")
                                .fontWeight(.semibold)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.indigo)
                    .foregroundStyle(.white)
                    .cornerRadius(10)
                    .disabled(isImporting)
                }
                .padding()
            }
            .background(Color(.systemBackground))
        }
    }

    private func summaryBadge(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2).fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Phase 4 — Done

    private var doneView: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)

            if let result = importResult {
                let usdaCount    = service.autoMatchedMatches.filter { $0.effectiveCandidate != nil }.count +
                                   service.matches.filter { $0.status == .userAccepted }.count
                let fsCount      = service.fatSecretMatchedMatches.count
                let manualCount  = service.manuallyEnrichedMatches.count
                VStack(spacing: 8) {
                    Text("Import Complete")
                        .font(.title2).fontWeight(.bold)
                    Text("\(result.logsCreated) logs imported")
                        .font(.body).foregroundStyle(.secondary)
                    Text("\(result.foodsCreated) foods created")
                        .font(.body).foregroundStyle(.secondary)
                    if usdaCount > 0 {
                        Text("\(usdaCount) enriched with USDA micronutrients")
                            .font(.body).foregroundStyle(.green)
                    }
                    if fsCount > 0 {
                        Text("\(fsCount) extended with FatSecret nutrients")
                            .font(.body).foregroundStyle(.blue)
                    }
                    if manualCount > 0 {
                        Text("\(manualCount) manually entered")
                            .font(.body).foregroundStyle(.purple)
                    }
                }
            } else if let error = importError {
                VStack(spacing: 8) {
                    Text("Import Failed")
                        .font(.title2).fontWeight(.bold)
                    Text(error)
                        .font(.caption).foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.indigo)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
    }

    // MARK: Actions

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        fileError = nil
        switch result {
        case .failure(let error):
            fileError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let gotAccess = url.startAccessingSecurityScopedResource()
            defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                csvString = text
                let foods = service.parseUniqueFoods(from: text)
                if foods.isEmpty {
                    fileError = "No food rows found. Make sure this is a LoseIt CSV export."
                    return
                }
                uniqueFoods = foods
                service.startSearch(for: foods)
            } catch {
                fileError = "Could not read file: \(error.localizedDescription)"
            }
        }
    }

    private func performImport() {
        guard let csv = csvString else { return }
        isImporting = true
        let enrichmentMap    = service.buildEnrichmentMap()
        let fatSecretMap     = service.buildFatSecretMap()
        let manualMap        = service.buildManualMap()
        let fallbackSourceMap = service.buildFallbackSourceMap()
        let ctx = modelContext
        Task {
            do {
                let result = try CSVImporter.importLoseItEnriched(
                    csvString: csv,
                    enrichmentMap: enrichmentMap,
                    fatSecretMap: fatSecretMap,
                    manualMap: manualMap,
                    fallbackSourceMap: fallbackSourceMap,
                    context: ctx
                )
                await MainActor.run {
                    importResult = result
                    isImporting = false
                    service.phase = .done
                }
            } catch {
                await MainActor.run {
                    importError = error.localizedDescription
                    isImporting = false
                    service.phase = .done
                }
            }
        }
    }
}

// MARK: - Match Review Row (needs review / no-match action row)

private struct MatchReviewRow: View {
    let match: EnrichmentMatch
    let service: LoseItEnrichmentService
    let onTapDetail: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(match.food.name)
                        .font(.subheadline).fontWeight(.semibold)
                    Text(match.food.units)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                confidenceBadge
            }

            if let candidate = match.topCandidate {
                Text(candidate.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                Button("Accept") {
                    service.accept(matchID: match.id)
                }
                .buttonStyle(EnrichmentActionStyle(color: .green))

                Button("Skip") {
                    service.skip(matchID: match.id)
                }
                .buttonStyle(EnrichmentActionStyle(color: .secondary))

                Button("Swap…") {
                    onTapDetail()
                }
                .buttonStyle(EnrichmentActionStyle(color: .indigo))
            }
        }
        .padding(.vertical, 4)
    }

    private var confidenceBadge: some View {
        Text(match.confidenceLabel)
            .font(.caption2).fontWeight(.semibold)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(badgeColor.opacity(0.15))
            .foregroundStyle(badgeColor)
            .cornerRadius(6)
    }

    private var badgeColor: Color {
        switch match.status {
        case .needsReview: return .orange
        case .noMatch: return .secondary
        case .userAccepted: return .green
        case .userSkipped: return .secondary
        default: return .secondary
        }
    }
}

// MARK: - Auto-matched summary row

private struct MatchSummaryRow: View {
    let match: EnrichmentMatch

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(match.food.name)
                    .font(.subheadline)
                if let candidate = match.topCandidate {
                    Text(candidate.description)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.subheadline)
        }
    }
}

// MARK: - No match row

private struct NoMatchRow: View {
    let match: EnrichmentMatch
    let service: LoseItEnrichmentService
    let onTapSearch: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(match.food.name)
                    .font(.subheadline)
                Text(match.food.units)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Group {
                if match.status == .userAccepted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if match.status == .userSkipped {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Search…") {
                        onTapSearch()
                    }
                    .buttonStyle(EnrichmentActionStyle(color: .indigo))
                }
            }
            .font(.subheadline)
        }
    }
}

// MARK: - FatSecret matched summary row

private struct FatSecretMatchRow: View {
    let match: EnrichmentMatch
    let service: LoseItEnrichmentService
    let onTapDetail: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(match.food.name)
                    .font(.subheadline)
                if let fs = match.fatSecretTopCandidate {
                    Text(fs.foodName)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button("Swap…") { onTapDetail() }
                .buttonStyle(EnrichmentActionStyle(color: .blue))
            Button("Skip") { service.skip(matchID: match.id) }
                .buttonStyle(EnrichmentActionStyle(color: .secondary))
        }
    }
}

// MARK: - Match Detail / Swap Sheet

struct MatchDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let match: EnrichmentMatch
    let service: LoseItEnrichmentService

    enum SearchSource: String, CaseIterable {
        case usda = "USDA"
        case fatSecret = "FatSecret"
        case manual = "Manual"
    }

    @State private var searchText: String = ""
    @State private var selectedSource: SearchSource = .usda
    @State private var usdaResults: [USDAFoodItem] = []
    @State private var fatSecretResults: [FatSecretFood] = []
    @State private var isSearching = false

    // Manual entry fields
    @State private var manualPotassium  = ""
    @State private var manualCalcium    = ""
    @State private var manualIron       = ""
    @State private var manualMagnesium  = ""
    @State private var manualZinc       = ""
    @State private var manualVitaminA   = ""
    @State private var manualVitaminC   = ""
    @State private var manualVitaminD   = ""
    @State private var manualVitaminE   = ""
    @State private var manualVitaminK   = ""
    @State private var manualVitaminB6  = ""
    @State private var manualVitaminB12 = ""
    @State private var manualFolate     = ""
    @State private var manualCholine    = ""
    @State private var manualCaffeine   = ""

    var body: some View {
        NavigationStack {
            List {
                Section("LoseIt Food") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(match.food.name).fontWeight(.semibold)
                        Text("\(match.food.units) · \(Int(match.food.caloriesPerServing)) cal/serving")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Picker("Source", selection: $selectedSource) {
                        ForEach(SearchSource.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search \(selectedSource.rawValue)…", text: $searchText)
                            .submitLabel(.search)
                            .onSubmit { runSearch() }
                    }
                    if isSearching {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    }
                } header: {
                    Text("Search")
                }

                // USDA candidates
                if selectedSource == .usda {
                    let candidates = usdaResults.isEmpty ? match.allCandidates : usdaResults
                    if !candidates.isEmpty {
                        Section("USDA Candidates") {
                            ForEach(candidates, id: \.fdcId) { item in
                                Button {
                                    service.swapCandidate(matchID: match.id, to: item)
                                    dismiss()
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.description)
                                            .font(.subheadline).foregroundStyle(.primary)
                                        if let brand = item.brandOwner {
                                            Text(brand).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // FatSecret candidates
                if selectedSource == .fatSecret {
                    let candidates = fatSecretResults.isEmpty ? match.fatSecretCandidates : fatSecretResults
                    if !candidates.isEmpty {
                        Section("FatSecret Candidates") {
                            ForEach(candidates) { item in
                                Button {
                                    fetchAndSwapFatSecret(item)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.foodName)
                                            .font(.subheadline).foregroundStyle(.primary)
                                        if let brand = item.brandName {
                                            Text(brand).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Manual entry tab
                if selectedSource == .manual {
                    Section("Enter per-serving amounts") {
                        ManualNutrientRow(label: "Potassium (mg)",   value: $manualPotassium)
                        ManualNutrientRow(label: "Calcium (mg)",     value: $manualCalcium)
                        ManualNutrientRow(label: "Iron (mg)",        value: $manualIron)
                        ManualNutrientRow(label: "Magnesium (mg)",   value: $manualMagnesium)
                        ManualNutrientRow(label: "Zinc (mg)",        value: $manualZinc)
                        ManualNutrientRow(label: "Vitamin A (mcg)",  value: $manualVitaminA)
                        ManualNutrientRow(label: "Vitamin C (mg)",   value: $manualVitaminC)
                        ManualNutrientRow(label: "Vitamin D (mcg)",  value: $manualVitaminD)
                        ManualNutrientRow(label: "Vitamin E (mg)",   value: $manualVitaminE)
                        ManualNutrientRow(label: "Vitamin K (mcg)",  value: $manualVitaminK)
                        ManualNutrientRow(label: "Vitamin B6 (mg)",  value: $manualVitaminB6)
                        ManualNutrientRow(label: "Vitamin B12 (mcg)",value: $manualVitaminB12)
                        ManualNutrientRow(label: "Folate (mcg)",     value: $manualFolate)
                        ManualNutrientRow(label: "Choline (mg)",     value: $manualCholine)
                        ManualNutrientRow(label: "Caffeine (mg)",    value: $manualCaffeine)
                    }

                    Section {
                        Button("Save Manual Entry") {
                            saveManualEntry()
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(.purple)
                    }
                }

                Section {
                    Button("Skip This Food") {
                        service.skip(matchID: match.id)
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Match Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                searchText = match.food.name
                fatSecretResults = match.fatSecretCandidates
                // Pre-fill manual fields if already entered
                if let m = match.manualOverride {
                    manualPotassium  = m.potassium.map  { String($0) } ?? ""
                    manualCalcium    = m.calcium.map    { String($0) } ?? ""
                    manualIron       = m.iron.map       { String($0) } ?? ""
                    manualMagnesium  = m.magnesium.map  { String($0) } ?? ""
                    manualZinc       = m.zinc.map       { String($0) } ?? ""
                    manualVitaminA   = m.vitaminA.map   { String($0) } ?? ""
                    manualVitaminC   = m.vitaminC.map   { String($0) } ?? ""
                    manualVitaminD   = m.vitaminD.map   { String($0) } ?? ""
                    manualVitaminE   = m.vitaminE.map   { String($0) } ?? ""
                    manualVitaminK   = m.vitaminK.map   { String($0) } ?? ""
                    manualVitaminB6  = m.vitaminB6.map  { String($0) } ?? ""
                    manualVitaminB12 = m.vitaminB12.map { String($0) } ?? ""
                    manualFolate     = m.folate.map     { String($0) } ?? ""
                    manualCholine    = m.choline.map    { String($0) } ?? ""
                    manualCaffeine   = m.caffeine.map   { String($0) } ?? ""
                    selectedSource = .manual
                }
            }
        }
    }

    private func saveManualEntry() {
        let override = ManualNutrientOverride(
            potassium:  Double(manualPotassium),
            calcium:    Double(manualCalcium),
            iron:       Double(manualIron),
            magnesium:  Double(manualMagnesium),
            zinc:       Double(manualZinc),
            vitaminA:   Double(manualVitaminA),
            vitaminC:   Double(manualVitaminC),
            vitaminD:   Double(manualVitaminD),
            vitaminE:   Double(manualVitaminE),
            vitaminK:   Double(manualVitaminK),
            vitaminB6:  Double(manualVitaminB6),
            vitaminB12: Double(manualVitaminB12),
            folate:     Double(manualFolate),
            choline:    Double(manualCholine),
            caffeine:   Double(manualCaffeine)
        )
        service.saveManualOverride(matchID: match.id, override: override)
        dismiss()
    }

    private func runSearch() {
        guard !searchText.isEmpty else { return }
        isSearching = true
        Task {
            switch selectedSource {
            case .usda:
                let results = (try? await USDAFoodDataService.shared.searchFoods(
                    query: searchText, pageSize: 10
                )) ?? []
                await MainActor.run { usdaResults = results; isSearching = false }
            case .fatSecret:
                let results = (try? await FatSecretService.shared.searchFoods(
                    query: searchText, maxResults: 10
                )) ?? []
                await MainActor.run { fatSecretResults = results; isSearching = false }
            case .manual:
                await MainActor.run { isSearching = false }
            }
        }
    }

    private func fetchAndSwapFatSecret(_ food: FatSecretFood) {
        isSearching = true
        Task {
            let detail = try? await FatSecretService.shared.getFoodDetails(foodId: food.foodId)
            let serving = detail?.servings?.first
            await MainActor.run {
                service.swapToFatSecret(matchID: match.id, food: food, serving: serving)
                isSearching = false
                dismiss()
            }
        }
    }
}

// MARK: - Manual nutrient row

private struct ManualNutrientRow: View {
    let label: String
    @Binding var value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
            TextField("—", text: $value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .foregroundStyle(.purple)
        }
    }
}

// MARK: - Button style helper

private struct EnrichmentActionStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption).fontWeight(.semibold)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(color.opacity(configuration.isPressed ? 0.25 : 0.12))
            .foregroundStyle(color)
            .cornerRadius(7)
    }
}
