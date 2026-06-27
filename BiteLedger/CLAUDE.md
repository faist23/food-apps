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

Any `Nutriments` built for a `per100g` food must set **all `*Serving` fields to `nil`**:
```swift
energyKcalServing: nil, proteinsServing: nil, carbohydratesServing: nil,
sugarsServing: nil, fatServing: nil, saturatedFatServing: nil,
fiberServing: nil, sodiumServing: nil
```
Any non-nil `*Serving` field causes `ImprovedServingPicker.nutritionMultiplier` to take
the `hasServingData = true` branch, returning `resolvedServingCount` × the serving value —
producing wildly wrong calories (e.g. 22,857 cal for 60g of Life cereal instead of ~228).

This rule applies to **every code path** that constructs a `ProductInfo`/`Nutriments` for
an existing `FoodItem` with `nutritionMode == .per100g`:
- `USDAFoodDetail.toProductInfo()` — USDA SR Legacy and Foundation API results
- `onFoodSelected` in `searchTabContent` (Recent foods tab)
- `onFoodSelected` in `myFoodsTabContent` (My Foods tab)
- `searchMyFoods()` — Search tab My Foods sub-results

Pattern used in `onFoodSelected` closures:
```swift
energyKcalServing: foodItem.nutritionMode == .per100g ? nil : FlexibleDouble(foodItem.calories),
```

**Exception — USDA Branded Foods and `perServing` foods:** these carry a declared serving size
and must populate `*Serving` fields. `toProductInfo()` computes `*Serving = nutrientPer100g ×
(servingSize / 100)` for Branded foods only. The `*100g` fields are also populated so
the per-100g path still works for free entry.

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

## FoodSearchView — Search Algorithms (Do Not Regress)

### My Foods tab — SQL predicate (active search) + hybrid browse (empty query)

**Active search (`searchText` non-empty):** `MyFoodsListView.startMyFoodsSearch()` fires a
debounced (300ms) `FetchDescriptor<FoodItem>` with `localizedStandardContains` predicate against
**both `name` and `brand`** (`name OR brand?.contains(firstWord)`), covering the full store with
no recency cap. Results are filtered in-memory with a three-tier rule:

1. **Catalog exclusion** — always drop `usda_seed_*` and `built_in_*`
2. **User-created allowlist** — always keep `source.isEmpty`, `"Manual"`, `"Quick Add"`,
   `recipe*`, `LoseIt*`, `CSV Import*` (backfill may be incomplete; trust source type)
3. **API-fetched guard** — everything else (`usda_*`, `fatsecret_*`, OFacts barcodes)
   requires `loggedIDs` membership to exclude BitePlan ghost foods

The in-memory filter passes `"name brand"` combined text to `matchesQuery` so every search
word is tested against both fields. Results are sorted by **most recently used** (via
`sqlLastUsedDates`), not alphabetically.

Last-used dates are pre-computed in the same Task via a three-pass strategy:
FoodHistoryEntry index → allLogs buffer → `food.foodLogs` fallback for any remainder.
Stored in `sqlLastUsedDates`; `lastUsedDates` switches to it when search is active.

**Do NOT replace** the SQL predicate path with an in-memory filter over `allLogs` — that
regresses to a 1000-entry recency cap and hides foods logged more than ~3 months ago.

**Browse mode (`searchText` empty):** hybrid merge of `FoodHistoryEntry` @Query (all
history, no cap) + `allLogs` (recent 1000, fills backfill gaps), sorted by `lastLoggedDate`.

### Last-used serving display — `FoodItemRow` + `onFoodQuickAdded`

`FoodItemRow` accepts an optional `lastLog: FoodLog?` parameter. When present, the subtitle
shows the actual last-logged serving (`loggedAmount`/`loggedUnit` if stored, otherwise the
`servingSize.label`) and `caloriesAtLogTime` — not the food's default serving per-100g display.

Both `RecentFoodsForMealView` and `MyFoodsListView` pre-compute a `lastLogs: [UUID: FoodLog]`
dictionary (keyed by food ID) from `allLogs` and pass it to `FoodItemRow`.

`onFoodQuickAdded` in both tabs must use the last log's serving, quantity, `loggedAmount`, and
`loggedUnit` — NOT `defaultServing` at `quantity: 1.0`. This ensures the `+` button re-logs
exactly what the user had last time.

`onFoodSelected` `initAmount`/`initUnit` must prefer `log.loggedAmount`/`log.loggedUnit` (the
stored display values) over parsing `servingSize.label` via `ServingSizeParser`. Label parsing
is kept only as a fallback for older logs that predate the `loggedAmount`/`loggedUnit` fields.

The **Meals tab "Add Foods" copy path** (`MealItemSelectionView` → `onAdd`) must also carry
`log.loggedAmount`/`log.loggedUnit` into the `AddedFoodItem` it builds. Omitting them lets
`FoodLog.create` reconstruct display via the `quantity` / `serving.unit` fallback, which drifts
for amounts that don't map 1:1 to the serving (e.g. a "150 g" log re-displays as "1.5 serving").
Nutrition is unaffected (it derives from `quantity × serving`), but the display amount/unit must
be preserved.

### Meals tab — per-word SQL + intersection + timestamp-range DB fetch

**Minimum query length:** `startMealSearch` requires at least **2 characters** before firing.
Single-character queries match virtually every row in the store and were the primary cause of
multi-second main-thread freezes.

**Threading:** all fetches run inside `MealSearchActor` (`Services/MealSearchActor.swift`), a
`@ModelActor` with its own background `ModelContext`. `startMealSearch` `await`s the actor,
then re-fetches the matched logs by UUID on the main context so SwiftUI observation works
correctly. The main thread is never blocked.

`MealSearchActor.search(query:)` runs a pair of SQL queries **for each query word**, intersects
the resulting meal keys, then fetches the full meal content from the DB.

For each word:
1. **Name query** — `FetchDescriptor<FoodLog>` where `foodItem?.name.localizedStandardContains(word)`.
   No fetchLimit — full history.
2. **Brand query** — `FetchDescriptor<FoodItem>` where `brand?.localizedStandardContains(word)`,
   then `brandFoods.flatMap { $0.foodLogs }` for full log history via relationship traversal.
   **Do NOT put brand in the FoodLog predicate** — CoreData cannot generate SQL for
   `CONTAINS[cdl]` through an optional relationship and crashes with "bad RHS".
   Relationship faulting happens on the background context so the main thread stays free.

Each word's matching logs are unioned (deduplicated), mapped to a `mealKey` (day + mealType),
and added to `perWordMealKeys`. The final `matchedMealKeys` is the **intersection** of all
per-word sets — a meal only qualifies if it contains at least one food matching **every** query
word.

**Meal content fetch — always use a timestamp-range DB query, never `allLogs`.**
`allMatchingLogs` (the union of all per-word SQL results) provides anchor timestamps for every
matched meal. A single `FetchDescriptor<FoodLog>` covering `minTimestamp...maxTimestamp` fetches
all logs in the matched date range; the result is filtered by `matchedMealKeys`.

**Do NOT use `allLogs` (capped at 1000) to fill matched meal content.** A meal may have some
logs inside the cap and others outside it. Using `allLogs` and marking a meal "covered" once
any one of its logs appears causes the older logs to be silently dropped — e.g. "spinach" from
a smoothie logged months ago would be missing even though "strawberries" from the same meal
is recent. The timestamp-range DB fetch is uncapped and correct for all meal ages.

The actor returns `[UUID]` (not model objects — `@Model` types are not `Sendable`). `startMealSearch`
re-fetches on the main context using `#Predicate { matchedIDs.contains($0.id) }`, which translates
to a fast indexed `IN` query bounded by the result set size.

The Search tab's API results are also filtered by `matchesQuery(displayName + brands, query)`
after the network call — only items matching all search words are shown.

### Recipes tab — in-memory `matchesQuery`

Recipes filter in memory via `matchesQuery(_:query:)` (free function at the top of
`FoodSearchView.swift`):

1. **Exact phrase** — `text.contains(query)` fast path
2. **All words, any order** — `query.split(separator: " ").allSatisfy { text.contains($0) }`

This means "margherita pizza" correctly finds "pizza, margherita". Do not replace with a
bare `contains` or `localizedCaseInsensitiveContains` — that regresses to phrase-only matching.

The Search tab's My Foods sub-search (inside `searchMyFoods`) uses word-split on combined
name+brand text independently and is correct as-is.

## MyFoodsManagementView — Filter Invariant (Do Not Regress)

`loadFoods()` and `startMyFoodsSearch()` use identical three-tier filter logic:

1. Exclude `usda_seed_*` and `built_in_*` (catalog)
2. Always include known user-created sources: `isEmpty`, `"Manual"`, `"Quick Add"`,
   `recipe*`, `LoseIt*`, `CSV Import*`
3. Require `loggedIDs` for all other sources (API-fetched ghost food guard)

**`loggedIDs` is built with `hasPrefix` matching** (`usda_*`, `fatsecret_*`), NOT exact
strings like `"USDA"` or `"FatSecret"`. Real source values are `"usda_<fdcId>"` and
`"fatsecret_<id>"` — exact-string matching silently never fires.

Last-used sort uses FoodHistoryEntry + `food.foodLogs` fallback (two-pass). Do not
revert to FoodHistoryEntry-only — foods logged before T-14 launched have no entry.

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
- **Meal search runs on `MealSearchActor`** — a `@ModelActor` with a dedicated background
  `ModelContext` created in `.task {}` via `MealSearchActor(modelContainer: modelContext.container)`.
  All `FetchDescriptor` calls (name scan, brand relationship traversal, timestamp-range fetch)
  execute on the background context. `startMealSearch` `await`s the actor and re-fetches
  matched UUIDs on the main context. Minimum 2-character guard prevents single-char
  full-table queries. Do NOT move these fetches back to the main-context `Task {}` path.
- **`MealDiarySection`** receives `hasYesterdayMeal` and `yesterdayCalories`
  as `let` params from `TodayView` — does not fetch from the DB itself.
  Avoids 4× per-section DB queries on every log change.
- **`TodayView` food logging uses optimistic UI, split into `stageLog` + `commitLogs`** —
  `stageLog(_:meal:)` is the cheap synchronous half: it creates + inserts the `FoodLog`
  and inserts it at its sorted position in the in-memory `logs` array immediately, with
  **no `modelContext.save()`** on the critical path (a synchronous save here blocks the
  badge render and the dismiss animation). `commitLogs(_:)` is the deferred half — it runs
  `FoodHistoryEntry.upsert()` + canonical match per item, then **one** `modelContext.save()`
  and **one** `loadSevenDayLogs()` / `loadStreak()` for the whole batch. Do NOT reintroduce
  a synchronous save in `stageLog`; the unstructured `Task` in `commitLogs` persists the
  pending inserts a main-actor hop later (same optimistic durability window the index/streak
  work already accepts).
- **Multi-item meal adds use the `onFoodsBatchAdded` sink on `FoodSearchView`** — the
  meal-selection ("Add Foods") path delivers all chosen items at once so `TodayView` runs
  `commitLogs` a single time. Looping per-item `onFoodAdded` instead would schedule N
  deferred save + `loadSevenDayLogs` + `loadStreak` passes (the multi-item freeze). Single
  adds fall back to `onFoodAdded` → `stageLog` + `commitLogs([one])`.
- **The meal sheet must not force keyboard focus** — drop `isSearchFocused = false` before
  presenting the meal sheet and do NOT set `isSearchFocused = true` in its `onDismiss`.
  A programmatic refocus restores the search field as first responder mid-dismiss, which
  re-summons the keyboard and makes iOS fall back to the system keyboard instead of the
  user's chosen one. Let the keyboard return only on a deliberate user tap.
- **`FoodLog.create(context:)`** — `context` is optional (default `nil`). Pass
  `nil` when the caller will handle `FoodHistoryEntry.upsert()` separately
  (e.g. TodayView's deferred task). Pass the model context in bulk-create paths
  (CSVImporter, `copyMealFromYesterday`, `MealEntryView`) to keep the index current.
- **`TodayView.loadStreak()`** short-circuits via the `streakCachedDate`/`cachedStreak`
  cache — if the cache is current for today it returns immediately with no DB query.

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
