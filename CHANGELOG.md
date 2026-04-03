# Changelog

All notable changes to BiteLedger and RecipeCard are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)

## [0.2.0.0] - 2026-03-31

### Added
- **T-12-v2 — Meal Planner v2 (Cluster Model, SchemaV4):** `MealPlanMeal` + `MealPlanMealItem` SwiftData models; 14-model schema (SchemaV4 lightweight migration from V3); `MealPlannerView` in RecipeCard with 7-day collapsible week planner; `MealPlanDayRow` with per-day Cal/P/C/F nutrition pills, dinner cluster, recently-made chips sourced from 90-day FoodLog history, variety nudge (same recipe ≥3 times in Dinner slot), "Copy to Next Week" (deep-copies `MealPlanMeal` + `MealPlanMealItem`), "Generate Shopping List" with dedup confirmation; `MealEntrySheet` multi-add UX — stays open after each add, shows "Added" chips per item, Done button; `MealPickerSearchView` with three tabs (Recipes / Foods / Note) and live `UnifiedFoodSearchService` API search; `ShoppingCart.populateFromMealPlan()` with per-food gram accumulation for items with gram weights + separate line items for dimensionless servings; legacy `MealPlanEntry` records cleared on first V4 launch
- **35-path test suite:** `MealPlanV2Tests` (MealPlanMeal / MealPlanMealItem creation, servingCount scaling, note-only filtering, `ShoppingCart.populateFromMealPlan` dedup and gram accumulation) + `SchemaV4MigrationTests` (V3→V4 lightweight migration, legacy entry cleared, new cluster operations)

### Changed
- `NutrientSpotlightCard` and `SpotlightDetailSheet` — minor visual polish and layout updates

### Fixed
- `BiteLedgerTests.makeContainer()` — `XCTSkip` fallback for iOS 26 simulator `loadIssueModelContainer` constraint; all 9 `FoodHistoryEntryTests` skip gracefully instead of failing with infrastructure errors

## [0.1.2.0] - 2026-03-22

### Added
- **Phase 2 Feature 1 — Nutrient Spotlight:** `NutrientSpotlightEngine` pure struct computes high-side patterns for 5 nutrients (sodium, saturated fat, total fat, cholesterol, carbs) over a rolling 7-day window; injectable `minDaysAbove` (default 3) and `dvMultiplier` (default 1.2×) parameters for future calibration; `SpotlightResult` with `Sendable` `Nutrient`
- **Nutrient Spotlight — HistoryView card:** `NutrientSpotlightCard` shows up to 2 qualifying nutrients with days-above count and curiosity prompt inside `ElevatedCard`; VoiceOver combined element
- **Nutrient Spotlight — TodayView chip:** dismissible capsule chip above meal sections; shows when ≥2 distinct meal types logged; dismiss persists per local calendar day (fixed UTC timezone bug); swipe or ×-button to dismiss; tap navigates to History tab
- **Backup & Restore (both apps):** `BackupService` in `BiteLedgerCore`; `createBackup` stages manifest.json + 5 CSVs + recipe images into temp dir, zips with ZIPFoundation; `restoreBackup` extracts, validates, and imports with `.replaceAll` or `.merge` (UUID-based skip); `resetDatabase` with 4 scopes (logsOnly/allFoodData/recipesOnly/everything); BiteLedger and RecipeCard each have `BackupRestoreView` + gear icon in Settings/toolbar; `CSVImporter.importBiteLedger` gained `skipExistingUUIDs: Bool` with O(n) seed-map pre-fetch
- **T-08 First-log micro-celebration:** `hasSeenFirstLogCelebration: Bool?` in `UserPreferences`; haptic + 2-second overlay in `TodayView` fires exactly once on nil flag
- **USDA search quality:** data types expanded from SR Legacy + Survey (FNDDS) to Foundation + SR Legacy + Branded; `USDAFoodDetail.toProductInfo()` branches on Branded foods to populate `*Serving` fields from FDA label serving size; `ProductInfo` gains `dataType: String?`
- **Nutrient spotlight helpers:** `Nutrient.spotlightDisplayName` (FDA-aligned: "Total Fat", "Total Carbohydrate"); `Nutrient.value(from: FoodLog) -> Double?` extension; `Nutrient` gains `Sendable` conformance for Swift 6
- **RecipeCard toolbar & metadata:** toolbar reduced from 4 items; recipe editor gains cuisine picker, prep/cook/total time fields with auto-total logic; grid alignment fixes in `RecipesListView`

### Changed
- 3-day gate removed from `RecentFoodsForMealView` — recent foods show immediately on first log
- Rolling 7-day window corrected from 8 to 7 calendar days (value: -6 not -7)
- Spotlight chip dismissal uses local `yyyy-MM-dd` format instead of UTC ISO8601 (fixes timezone edge case for UTC+ users)
- `NutrientSpotlightCard` uses `results.first?.message` instead of force-subscript `results[0]`
- HistoryView spotlight results moved to `@State` (computed once on load + `onChange`) instead of recomputing on every body pass

### Fixed
- ZIP path traversal vulnerability in `BackupService.restoreBackup` — entries with `../` paths now skipped

### Removed
- `AddFoodView.swift` deleted (dead code; replaced by `FoodSearchView` flow)

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

