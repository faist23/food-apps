# Changelog

All notable changes to BiteLedger and RecipeCard are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)

## [0.1.1.0] - 2026-03-20

### Added
- **T-11 (Feature 2)** Cooking Mode — full-screen `CookingModeView` with step-by-step directions, screen-always-on, and timer detection; accessible via RecipeDetailView
- **T-11 (Feature 3)** Shopping List — persistent `ShoppingCart` (@Observable, UserDefaults-backed); `ShoppingListView` with categorized sections (Produce/Dairy/Meat/Pantry/Other), check-off, swipe-to-delete, swipe-to-reclassify, clipboard copy, and iOS share sheet; tab badge showing unchecked count
- **T-11 (Feature 3)** `ShoppingCategory.detect()` — keyword-based auto-categorization with compound-specific overrides (garlic powder → Pantry before broad "garlic" → Produce)
- **T-02** Quick-Add Recent/Frequent Foods — top-8 most-frequently logged foods per meal type in `FoodSearchView`; 3+ day gate, excludes already-logged-today foods
- **T-03** Streak Milestone Celebrations — `lastCelebratedMilestone` in `UserPreferences`; milestones [3,7,14,30,60,100] trigger haptic + toast overlay
- **T-04** `VersionedSchema` + `SchemaMigrationPlan` wired into both apps (`BiteLedgerMigrationPlan`, `RecipeCardMigrationPlan`); `RecipeCardSchema.swift` added with V1 baseline
- **T-01** 7-day rolling average hero chart in HistoryView with Catmull-Rom interpolation and FDA DV reference line
- **NEW-1** Weekly recap Share Card — shareable image with calorie/protein snapshot and streak, rendered with ImageRenderer
- **E-4** Unit tests for `NutritionCalculator` (17 cases) and RecipeCard ingredient matching (38 cases: ingredientScore, resolveGrams, volumeToTbsp)
- **E-4** `IngredientMatching.swift` — extracted `ingredientScore`, `resolveGrams`, `volumeToTbsp` to module-internal scope for testability
- Color token asset catalogs added to RecipeCard: Brand (BrandPrimary, BrandAccent, BrandGlow), Macro (MacroCarbs, MacroFat, MacroProtein), Surfaces (SurfaceCard, SurfaceElevated, SurfacePrimary), Text (TextPrimary, TextSecondary, TextTertiary), Utility (DividerSubtle, Error, Success, Warning), CookingMode (CookingModeSurface, CookingModeText)

### Changed
- **E-1** Backfill functions now use `guard let prefs =` pattern (was optional-chaining no-op on fresh install); flags persist correctly after first backfill
- **E-2** BiteLedger app startup: replaced `fatalError` with graceful `AppStoreErrorView` and retry button for App Group / ModelContainer failures
- **E-3** RecipeCard app startup: same graceful error recovery replacing fatalError
- **E-5** FDA daily values consolidated as a single `DailyValues` struct in `NutritionCalculator.swift`
- **D-1–D-8** RecipeCard design polish: toolbar font sizes, empty states with icons, gradient placeholder, VoiceOver labels, first-run banner, semantic color tokens, `SurfaceCard` component, hero placeholder image
- `T-04` `rollingAverage(logs:days:nutrient:)` added to `NutritionCalculator` — rolling window over logged days only (not calendar days)
- Local search word-order fix — `matchesQuery()` in `FoodSearchView`: exact phrase first, then all words any order (fixes "margherita pizza" → "pizza, margherita")

### Fixed
- Schema order corrected: `ServingSize.self` moved before `FoodLog.self` in both apps to match canonical order

