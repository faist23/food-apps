# CLAUDE.md — BiteLedger

Privacy-first food & nutrition tracking app.
See `../CLAUDE.md` for shared workspace rules (schema, nutrition math,
data sources, FDA label format).

---

## Build & Run

```bash
# Build
xcodebuild -project BiteLedger.xcodeproj -scheme BiteLedger \
  -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run all tests
xcodebuild test -project BiteLedger.xcodeproj -scheme BiteLedger \
  -destination 'platform=iOS Simulator,name=iPhone 16'

# Run a single test class
xcodebuild test -project BiteLedger.xcodeproj -scheme BiteLedger \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:BiteLedgerTests/BiteLedgerTests
```

---

## View Structure

```
Views/
  Home/      — TodayView (root), NutritionDashboard, MealSection, FoodLogEditView
  AddFood/   — FoodSearchView, ProductDetailView, MealEntryView,
               ManualFoodEntryView, ImprovedServingPicker
  History/   — HistoryView
  Settings/  — SettingsView, DataExportView, LoseItImportView,
               LoseItEnrichmentView, MyFoodsManagementView, FoodItemEditorView
```

`TodayView` is the root view. It reads `FoodLog` entries for the selected date
and passes them to `NutritionDashboard` and `MealSection`.

**FDA label views:**
- `DetailedNutritionView` — full label for daily and meal totals
- `FoodLogEditView` — full label with live-updating preview as serving/quantity changes
- `ImprovedServingPicker` — full label using `NutritionFacts` data from APIs
- `ManualFoodEntryView` — editable label using `ElevatedCard(padding:0, cornerRadius:20)`;
  rows use `LabelNutrientRow` (14pt, tappable unit/% toggle)
- `FoodItemEditorView` — editable label using `ElevatedCard(padding:0, cornerRadius:20)`
  inside a `ScrollView`

---

## USDA Nutriments Invariant (Critical — Do Not Regress)

`USDAFoodDetail.toProductInfo()` must set **all `*Serving` fields to `nil`** for
SR Legacy and Foundation data types:
```swift
energyKcalServing: nil, proteinsServing: nil, carbohydratesServing: nil,
sugarsServing: nil, fatServing: nil, saturatedFatServing: nil,
fiberServing: nil, sodiumServing: nil
```
USDA SR Legacy and Foundation are per-100g databases. Any non-nil `*Serving` field
causes `ImprovedServingPicker.nutritionMultiplier` to take the `hasServingData = true`
branch, returning `resolvedServingCount` (= 1.0) × the serving value —
producing wildly wrong calories (e.g. 1452 cal for one frankfurter instead of ~142).

**Exception — USDA Branded Foods:** Branded Foods carry a declared `servingSize` (in
grams) from the FDA label. `toProductInfo()` computes `*Serving = nutrientPer100g ×
(servingSize / 100)` for Branded foods only. The `*100g` fields are also populated so
the per-100g path still works for free entry. SR Legacy and Foundation are never
affected — their `*Serving` fields remain nil.

---

## perServing-no-gramWeight Mineral/Caffeine Invariant (Critical — Do Not Regress)

For `perServing` foods with no `gramWeight` (`baseGrams = 1.0`), `mgToPer100g()`
guards `baseGrams > 1.0` and returns `nil` to prevent garbage per-100g values.
These foods rely on `*Serving` fallback fields instead:
- `Nutriments` has `potassiumServing`, `calciumServing`, `ironServing`,
  `caffeineServing` (all `FlexibleDouble? = nil`, mg/serving)
- All four `FoodSearchView` code paths that build `ProductInfo` for existing foods
  must set these when `baseGrams <= 1.0`
- `ImprovedServingPicker` displays them via `nutrientMg * resolvedServingCount`
  (the `else if` branch after the `*100g` check)
- In `searchMyFoods` (path 3): use `actualGrams = 1.0` for `perServing` foods
  without `gramWeight` (not the 100.0 fallback) so mineral `*100g` fields
  are computed correctly

---

## `displayNameForUnit(.serving)` in `ImprovedServingPicker`

Strips the leading number from `product.servingSize` (e.g. `"1 caplet"` →
`"Caplet"`) rather than running through `ServingSizeParser` which maps unknown
unit words to `.serving` and would display "Serving".

---

## CSV Import/Export

`CSVExporter` produces five files for full round-trip backup:
`foods.csv`, `servings.csv`, `logs.csv`, `recipes.csv`, `ingredients.csv`.

`CSVImporter` auto-detects format:
- **LoseIt export** — single CSV with daily logs
- **BiteLedger full export** — five-file set (foods + servings + logs + recipes + ingredients)
- **BiteLedger legacy export** — three-file set (foods + servings + logs); recipes/ingredients
  gracefully skipped (nil parameters to `importBiteLedger`)

Guarantee: export → delete app → import produces identical data.

### JSON array fields in recipes.csv
`directions`, `keywords`, `dietTags`, and `importedNutrition` are stored as
**base64-encoded JSON Data** to keep each recipe on a single CSV line without
embedded newlines breaking the parser. Decode with `Data(base64Encoded:)` on import.

### Recipe images (separate files, not in CSV)
Local `file://` images (OCR scans, camera photos) are exported as **`{recipeId}.jpg`** files
written into an `images/` subdirectory of the temp export folder alongside the 5 CSVs.
Remote `https://` images are **not** exported — `AsyncImage` re-fetches them naturally.

On import: `LoseItImportView` detects `.jpg`/`.jpeg`/`.png`/`.heic` files, reads their data,
and builds an `imageMap: [String: Data]` keyed by the UUID filename stem.
`importBiteLedger(imageMap:)` passes the map to `importBiteLedgerRecipes()`, which calls
`RecipeImportService.saveImageDataLocally()` to write each JPEG to Documents on the new device.
Dead `file://` URLs without a matching image file are left nil.

### Auto-detection signatures (LoseItImportView)
| File | Detection |
|---|---|
| foods.csv | header contains `nutritionmode` |
| servings.csv | header contains `gramweight` or `isdefault` |
| logs.csv | header contains `caloriesatlogtime` |
| recipes.csv | header contains `servingsyield` or `recipecategory` |
| ingredients.csv | header contains `recipeid` or `recipeunit` |
| `{uuid}.jpg` | file extension is `.jpg`/`.jpeg`/`.png`/`.heic`; UUID from filename stem |

---

## LoseIt Enrichment Tool

Files: `LoseItEnrichmentService.swift`, `LoseItEnrichmentView.swift`,
`ClaudeMatchingService.swift`, `CSVImporter.importLoseItEnriched`

### Three-pass matching
1. **USDA** — 15 concurrent searches, word-overlap scoring.
   `≥ 0.70` → autoMatched, `0.30–0.70` → needsReview, `< 0.30` → noMatch
2. **FatSecret fallback** — for noMatch foods only. Batch size 3, 1.5s
   inter-batch pause, retry on error code 12 (backoff: 2s / 4s / 6s)
3. **Claude AI pass** — for needsReview + fatSecretMatched + noMatch.
   Batches of 20. Picks best USDA or FatSecret candidate semantically.
   Requires `claude.plist` with `APIKey` in bundle — must be added to
   "Copy Bundle Resources" in Xcode manually.

### Data applied at import
- **USDA match:** all 15 micronutrients via calorie-based scale
  (`calPerServing / caloriesPer100g`)
- **FatSecret match:** potassium, calcium, iron, vitaminA, vitaminC —
  converted from % DV using FDA daily values

### Key details
- `EnrichmentMatch` holds both `topCandidate: USDAFoodItem?` and
  `fatSecretTopCandidate / ServingData / Candidates`
- `buildEnrichmentMap()` → USDA map; `buildFatSecretMap()` → FatSecret map;
  both passed to `importLoseItEnriched`
- `ClaudeMatchingService.fromPlist()` logs why it fails if `claude.plist`
  is missing or unconfigured
- FatSecret `executeRequest` retries error code 12 up to 3× with exponential backoff

---

## FoodSearchView — Local Search Algorithm (Do Not Regress)

My Foods, Meals, and Recipes tabs filter in memory via `matchesQuery(_:query:)` (free
function at the top of `FoodSearchView.swift`):

1. **Exact phrase** — `text.contains(query)` fast path
2. **All words, any order** — `query.split(separator: " ").allSatisfy { text.contains($0) }`

This means "margherita pizza" correctly finds "pizza, margherita". Do not replace with a
bare `contains` or `localizedCaseInsensitiveContains` — that regresses to phrase-only matching.

The Search tab's My Foods sub-search (inside `searchMyFoods`) already used word-split
independently and is correct as-is.

## FoodSearchView — Recipes Tab

`FoodSearchView` has four tabs: **Search**, **My Foods**, **Meals**, **Recipes**.

The Recipes tab loads all `Recipe` objects in `.task` (same async pattern as `allLogs` —
not `@Query`, to avoid blocking keyboard appearance). It filters by `searchText` in memory
via `matchesQuery`.

### Logging a recipe (`findOrCreateRecipeFoodItem`)
Recipes are logged via a synthetic `FoodItem` in `.perServing` mode:
- **Source prefix:** `"recipe_<UUID>"` — used to find or update the FoodItem on repeat logs.
- **Nutrition:** from `recipe.importedNutrition` if present; otherwise calculated from
  ingredients and divided by `servingsYield`.
- **Serving:** a single `ServingSize(label: "1 serving", isDefault: true)` with no `gramWeight`.
- On every log, the FoodItem's nutrition is refreshed in case ingredients changed since last time.
- `food.recipe = recipe` links back to the source Recipe.

The user picks a serving count (1–20) in `RecipeServingSheet`, then `onFoodAdded` is called
with an `AddedFoodItem` — same callback as all other tabs, so `FoodLog.create()` runs unchanged.

### Do NOT exclude recipe FoodItems from IngredientSeeder cleanup
The seeder cleans up `usda_seed_*` prefixed foods. Recipe synthetic foods use `recipe_<UUID>` —
a completely separate prefix namespace that the seeder never touches.

---

## Performance Rules

- **`FoodSearchView`** uses `@State private var allLogs` loaded in `.task {}`
  — NOT `@Query`. With 1000+ logs, `@Query` blocks the main thread on sheet
  init, delaying keyboard appearance by several seconds. The `.task` loads
  after first render so the keyboard appears immediately.
- **`MealDiarySection`** receives `hasYesterdayMeal` and `yesterdayCalories`
  as `let` params from `TodayView` — does not fetch from the DB itself.
  Avoids 4× per-section DB queries on every log change.
- **`TodayView.loadStreak()`** is guarded by `hasLoadedStreak` — runs once
  per session, not on every sheet dismiss.

---

## Streak Cache

`UserPreferences.cachedStreak` + `streakCachedDate` store a cached anchor so
per-day COUNT queries walk backward and short-circuit at the cached value.
- `deleteAllData()` resets `cachedStreak = 0` and clears `streakCachedDate`
- `loadStreak()` skips today if it has 0 logs (today is in-progress, not missed)
- `copyMealFromYesterday()` invalidates the cache and calls `loadStreak()`
  after saving

---

## USDA `sortedPortions` (Do Not Regress)

`USDAFoodDetail.toProductInfo()` sorts portions so bulk keywords
(`"package"`, `"bag"`, `"box"`) go to the end, making individual units
(e.g. `"frankfurter"`) the default selection in the serving picker.
