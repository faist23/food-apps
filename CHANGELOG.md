# Changelog

All notable changes to BiteLedger and RecipeCard are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)

## [0.1.0.0] - 2026-03-20

### Added
- **T-01** 7-day rolling average hero chart in HistoryView with Catmull-Rom interpolation and FDA DV reference line
- **T-04** `rollingAverage(logs:days:nutrient:)` in `NutritionCalculator` — rolling window over logged days only, not calendar days
- **NEW-1** Weekly recap Share Card — shareable image with calorie/protein snapshot and streak, rendered with ImageRenderer
- **E-4** Unit tests for `NutritionCalculator` (17 cases: calculate, fromLog, dailyTotal, rollingAverage) and RecipeCard ingredient matching (38 cases: ingredientScore, resolveGrams, volumeToTbsp)
- **E-4** `IngredientMatching.swift` — extracted `ingredientScore`, `resolveGrams`, `volumeToTbsp` from private RecipeImportReviewView scope to module-internal for testability

### Changed
- **E-1** Backfill functions (`backfillStaleLogs`, `backfillServingUnits`, `backfillServingAmounts`) now check `UserPreferences.has*` flags and skip on subsequent launches
- **E-2** BiteLedger app startup: replaced `fatalError` with graceful `AppStoreErrorView` and retry button for App Group / ModelContainer failures
- **E-3** RecipeCard app startup: same graceful error recovery replacing fatalError
- **E-5** FDA daily values consolidated as a single `DailyValues` struct in `NutritionCalculator.swift`, eliminating duplicated constants across 3+ files
- **D-1** RecipeCard toolbar: standardized font sizes and tightened header spacing
- **D-2** Empty state views: added icon + descriptive subtitle for zero-recipe and zero-ingredient states
- **D-3** Recipe thumbnail placeholder replaced with gradient + fork-knife icon
- **D-4** VoiceOver: accessibility labels added to recipe cards, ingredient rows, and nutrition header
- **D-5** First-run onboarding banner: shown only on first launch via `UserDefaults`
- **D-6** Semantic color tokens applied throughout RecipeCard (replacing hardcoded colors)
- **D-7** `SurfaceCard` component added — consistent rounded card with shadow used in ingredient chips
- **D-8** Hero placeholder image added for recipes without a photo

### Fixed
- Schema order corrected: `ServingSize.self` moved before `FoodLog.self` in both apps to match canonical order

