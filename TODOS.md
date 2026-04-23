# TODOS.md — Food Apps

Tracked design and product work. Created by /plan-design-review on 2026-03-19.
Engineering items added by /plan-eng-review on 2026-03-19.
Product vision + new items added by /plan-ceo-review on 2026-03-19.
Post-v1 roadmap + iPad strategy added by /plan-ceo-review on 2026-03-20.
T-14 reframed + T-20 added by /plan-ceo-review on 2026-03-22.

---

## Product Philosophy (from /plan-ceo-review — governs all future decisions)

This app is for **reluctant loggers, not nutrition optimizers.**

- Goals are OFF by default (already implemented correctly)
- The win is logging the food, not hitting a calorie target
- 7-day rolling average > daily goal comparison
- History charts show FDA daily values as neutral reference (not personal targets)
- **No body weight, ever.** Categorically different from MyFitnessPal / Lose It
- Target user: someone who wants nutritional awareness without judgment

### Three User Segments (Architectural Constraint)
1. **BiteLedger-only** — track food, no recipe management
2. **BitePlan-only** — manage/cook recipes, no food diary
3. **Both apps** — power user who logs recipes from BitePlan into BiteLedger

Future implication: BiteLedger needs manual + URL recipe creation for segment 1.
BitePlan's differentiators: URL import, OCR, cooking mode, shopping list.

### iPad Strategy (from /plan-ceo-review 2026-03-20)
**Adaptive layout, not exclusive.** Meal planning and pantry use `horizontalSizeClass` to adapt:
- `.compact` (iPhone): simplified list views (7-day planner as list, ingredient filter chips)
- `.regular` (iPad): full grid views (week calendar with drag-and-drop, pantry inventory sidebar)
Same SwiftData models underneath. Same App Store download. iPhone users get full planning features in list form; iPad users get the full grid experience.

### Schema Compatibility Policy (from /plan-ceo-review)
Before shipping any SchemaV2+ change: verify that a SchemaV1 app can open a V2 store without crashing. If backwards compat fails, require simultaneous App Store release of both apps.

---

## P3 — Future

---

### T-MP1: Meal Planner — Copy to Next Week: Add Merge Option
**What:** Today "Copy to next week" replaces all existing entries. Add a "Merge" path that copies only the empty slots in the target week, preserving any meals already planned there.
**Why:** If a user has already planned Tuesday's breakfast for next week and uses "Copy to next week," they lose that entry. The current Replace-only alert is clear, but Merge is a much safer default for partially-planned weeks.
**Pros:** Significantly reduces accidental data loss. Merge is the expected default behavior for most calendar-style "copy" operations.
**Cons:** Merge logic requires slot-by-slot conflict resolution (what happens if both weeks have a dinner on Wednesday?). Alert needs 3 buttons (Replace / Merge / Cancel), which is at the iOS max.
**Context:** Deferred from /plan-design-review on 2026-03-30. The Replace alert text is explicit enough for v1. Ship Merge in a subsequent release once "Copy to next week" usage patterns are understood.
**Effort:** S (human: ~2 hrs / CC: ~15 min) | **Priority:** P3 | **Depends on:** Meal Planner shipped

### T-MP4: Meal Planner — Week Header Shows No Year
**What:** `weekHeaderTitle` formats as `"Mar 30"` (month + day only). When navigating past a Dec→Jan boundary, two different years' weeks display the same header string.
**Why:** Ambiguous when a user navigates to the week of Dec 28, 2026 vs Dec 28, 2027 — the header is identical.
**Fix:** Include year when the displayed week is not in the current calendar year: `weekStart.formatted(.dateTime.month(.abbreviated).day())` → conditionally append `.year()` when `Calendar.current.component(.year, from: weekStart) != Calendar.current.component(.year, from: .now)`.
**Context:** Found by Codex outside voice during /plan-eng-review on 2026-03-30.
**Effort:** XS (human: ~15 min / CC: ~5 min) | **Priority:** P3 | **Depends on:** Meal Planner shipped

---

### T-MP5: Meal Planner — Week Anchor Ignores Device Locale
**What:** `MealPlan.startOfWeek(for:)` always anchors to Sunday (Gregorian weekday 1). Devices in European locales where Monday is the first day of the week will show a Sunday-anchored week that doesn't match the user's calendar.
**Why:** `.weekday` component returns 1 for Sunday in Gregorian — correct for US, but users in Monday-first locales expect Mon–Sun weeks.
**Fix:** Use `Calendar.current.firstWeekday` to compute the correct anchor day. `daysBack = (weekday - calendar.firstWeekday + 7) % 7`.
**Context:** Found by Codex outside voice during /plan-eng-review on 2026-03-30.
**Effort:** XS (human: ~30 min / CC: ~5 min) | **Priority:** P3 | **Depends on:** Meal Planner shipped, international user demand

---

### T-MP3: Meal Planner — Add Date Predicate to Recent Entries Fetch
**What:** `loadRecentDinnerEntries()` in `MealPlanDayRow` (and `loadRecentEntries()` in `MealEntrySheet`) fetch ALL `MealPlanEntry` records with no lower-bound date predicate — just sort by date descending and filter in Swift. Add a 90-day lookback predicate: `$0.date > cutoffDate && $0.date < today`.
**Why:** A user with 6+ months of data accumulates ~10,000 entries. The full-table fetch + in-memory filter is unnecessary work when only the most recent 15 deduplicated items are ever displayed.
**Pros:** One-line predicate addition eliminates the full-table scan for long-term users.
**Cons:** None. The 90-day window covers any realistic "recently used" scenario.
**Context:** Found during /plan-eng-review on 2026-03-30. No real-world pain at launch (most users won't have 6+ months of data), so deferred.
**Effort:** XS (human: ~30 min / CC: ~5 min) | **Priority:** P3 | **Depends on:** Meal Planner shipped

---

### T-MP2: Meal Planner — iPad Adaptive Layout
**What:** Use `horizontalSizeClass` to switch between the current list view (`.compact`) and a week grid view with drag-and-drop (`.regular`). Per the iPad strategy in TODOS.md: same SwiftData models, same download, different layout.
**Why:** The 7-day collapsible list works on iPhone. On iPad it looks sparse and wastes the available width. A week-at-a-glance grid is the natural iPad pattern for a meal planner.
**Pros:** BitePlan gains an iPad-first feature with zero model changes. Drag-and-drop between days is a natural next step after the grid ships.
**Cons:** Full grid with drag-and-drop is a non-trivial implementation. The list view on iPad is acceptable for v1.
**Context:** Deferred from /plan-design-review on 2026-03-30. The iPad strategy was set in /plan-ceo-review (2026-03-20): .compact = list, .regular = grid. This is the execution of that strategy for the Meal Planner specifically.
**Effort:** L (human: ~1 week / CC: ~1 hour) | **Priority:** P3 | **Depends on:** Meal Planner shipped

---

### T-18: Nutrient Spotlight — Below-Threshold Patterns (Fiber, Protein)
**What:** Add support for nutrients consistently BELOW 80% DV. Engine gets a `thresholdDirection: .above/.below` injectable parameter. Copy: "Fiber has been low this week. Curious what foods are high in it?" Different copy logic required for low-side patterns.
**Why:** Fiber and protein are the most common nutritional gaps for the target user (reluctant logger). The high-side spotlight covers sodium/fat/cholesterol — the low-side covers the "you're missing this" awareness without judgment.
**Pros:** Doubles feature coverage. Engine is already structured for this — one parameter addition, separate copy template.
**Cons:** "Low" patterns need separate user validation — doesn't feel like judgment? The copy "has been low this week" is more ambiguous in tone than "has been high." Should not ship before high-side patterns are validated.
**Context:** Introduced as a deferred item from Nutrient Spotlight v1 design review (2026-03-21). Copy template: "{Nutrient} has been low this week. Curious what foods are high in it?" Threshold direction is separate from the high-side threshold — would be a new injectable param, not a modification of existing defaults.
**Effort:** XS (human: ~2 hrs / CC: ~10 min) | **Priority:** P3 | **Depends on:** T-17 (threshold calibration validated), Nutrient Spotlight v1 live for 4+ weeks

---

### T-17: Nutrient Spotlight — Threshold Calibration
**What:** After Nutrient Spotlight ships, log 2 weeks of real data and check what % of sessions would have triggered a spotlight with the current 120%/3-of-7 defaults. Tune `defaultMinDays` and `defaultDVMultiplier` constants if the feature is firing too frequently (noise) or not at all (invisible).
**Why:** The 120%/3-of-7 working assumptions were not validated against real log data. If too sensitive, the feature becomes noise and users learn to ignore it. If too conservative, it never fires and the feature is invisible.
**Pros:** The injectable parameters make tuning a 1-line change at the call site — no schema change, no view changes. Constants are `NutrientSpotlightEngine.defaultMinDays` and `defaultDVMultiplier`.
**Cons:** Requires 2 weeks of real-world usage before acting on it. Target: fires 1-2x per week for a regular logger.
**Context:** Introduced by Nutrient Spotlight (Phase 2, Feature 1). See design doc `craigfaist-feature-v1-ship-design-20260321-213749.md`. Open question from design doc: what threshold makes the feature feel like discovery vs. noise?
**Effort:** XS (human: ~30 min / CC: ~5 min) | **Priority:** P3 | **Depends on:** Nutrient Spotlight shipped, 2+ weeks of real log data

---

### T-16: BitePlan — Auto-total time unit tests
**What:** Unit tests for the `onChange` condition that auto-fills Total time from Prep + Cook in RecipeEditorView and RecipeImportReviewView.
**Why:** The guard "only auto-update total if total == prev sum OR total is nil" is the only non-trivial logic in the metadata PR. Without tests, a future refactor could silently break the "don't override user's manual total" invariant.
**Pros:** Protects a subtle invariant that is easy to break silently.
**Cons:** SwiftUI @State is not unit-testable directly — logic must be extracted to a pure function first (e.g., `func resolveAutoTotal(prep: Int?, cook: Int?, currentTotal: Int?) -> Int?`).
**Context:** Introduced by feature/v1-ship toolbar + metadata PR. Auto-total fires when prep or cook changes and total is nil or equals the previous prep+cook sum. The interesting edge case: user sets total=60, then edits prep to 20 (cook=30) — total must stay 60.
**Effort:** XS (human: ~1 hour / CC: ~10 min) | **Priority:** P3 | **Depends on:** metadata PR shipped

---

### T-15: RecipeDetailView — Segmented Ingredients/Directions
**What:** Add a segmented control (Ingredients | Directions) to RecipeDetailView to let users jump between sections without scrolling past 15+ ingredient rows.
**Context:** Single scroll is fine for small recipes but degrades with large ones. The scale picker already anchors the top of the view; a segmented picker below it would give clear section navigation. In-memory toggle — no schema change.
**Effort:** XS (human: ~2 hours / CC: ~10 min) | **Priority:** P3 | **Depends on:** RecipeDetailView sticky bar shipped (v1.1)

---

### T-06: HistoryView Design Overhaul
**What:** Redesign HistoryView to be the "look back" surface. Ideal: trend chart + calendar strip + day detail.
**Effort:** L | **Priority:** P3

---

### T-07: Meal Reminder Notifications
**What:** Optional push notifications at configured meal times: "Haven't logged lunch yet."
**Context:** Requires `UNUserNotificationCenter` permission request. Store reminder times in UserPreferences. Send local notifications. Must not be annoying — off by default, easy to dismiss/disable.
**Effort:** M | **Priority:** P3

---

### ~~T-08: First-Log Micro-Celebration~~ — COMPLETED feature/v1-ship
**What:** ~~A brief, delightful animation when the user logs their very first food item ever.~~
**Shipped:** `hasSeenFirstLogCelebration: Bool?` in `UserPreferences`; haptic + 2-second overlay in `TodayView`; fires on nil flag only.

---

### T-09: HealthKit Integration
**What:** Write nutrition data to Apple Health on every FoodLog creation (opt-in via `healthKitEnabled: Bool = false` in UserPreferences).
**Context:** Deferred until app is stable. `FoodLog.create()` is the single correct hook. Requires HealthKit entitlement + Info.plist usage descriptions in both apps. `healthKitEnabled` should be a SchemaV3 field.
**Effort:** M | **Priority:** P2 (post-ship) | **Depends on:** SchemaV3

---

### ~~T-10: Recipe Creation in BiteLedger (Manual + URL)~~ ✓ SHIPPED 2026-04-22
**What:** Allow BiteLedger-only users to create recipes — both manual and URL import. No OCR, no photos (BiteRecipe differentiators).
**Shipped:** Moved `IngredientMatching`, `ImportRecipeView`, and `RecipeImportReviewView` from BiteRecipe into `BiteLedgerCore` (all public). `MyRecipesView` now shows a `+` menu with "Import from URL" and "Create Manually". BiteRecipe gets the views automatically via `import BiteLedgerCore`. Renamed private `ImportRecipeView` in `RecipeEditorView` to `EditorURLImportView` to resolve name collision.
**Effort:** L | **Priority:** P3 | **Depends on:** Stable BiteRecipe recipe model + SchemaV3

---

### T-11: Log to BiteLedger (v1.2 — Feature 4 only)
**What:** Allow BitePlan users to log a recipe directly into BiteLedger's food diary from RecipeDetailView.
- Build RecipeServingSheet (meal type + quantity picker)
- BiteLedger declares `biteledger://` URL scheme in Info.plist
- BitePlan adds `biteledger` to LSApplicationQueriesSchemes
- RecipeDetailView shows "Log to BiteLedger" button when `UIApplication.canOpenURL(biteledger://)` returns true
- `FoodLog.create(food: recipe.foodItem, serving: nil, quantity: selectedQty)` writes to shared store
**Effort:** M | **Priority:** P1 (v1.2) | **Depends on:** v1.1 shipped (done)

---

### T-12: Meal Planning (iPhone-first v1) ✓ SHIPPED 2026-03-29
**What:** 7-day collapsible list planner in BitePlan. History fast-path chips (from past MealPlanEntry records, first-use fallback: all Recipes) + full API search via MealPickerSearchView. Per-day nutrition preview (4 pills: Cal/P/C/F). "Generate Shopping List" with confirmation + dedup. "Log Day" button per day. "Copy to next week" (week header). Variety nudge (SF Symbol when same Recipe in Dinner slot 3+ times in week).
**Context:** SchemaV3 required — adds `MealPlan` + `MealPlanEntry` (12 models total). Lightweight migration — do NOT wire `migrationPlan:` into ModelContainer. Coordinated release with BiteLedger (both apps must register all 12 models). iPad calendar grid with drag-and-drop is deferred (see T-12-iPad below). CEO plan + design doc: `~/.gstack/projects/faist23-food-apps/ceo-plans/2026-03-29-meal-planning.md`
**Note:** Superseded by T-12-v2 (cluster model). The skeleton was real work; v2 replaces the single-item model.
**Effort:** L (human: ~1.5 weeks / CC: ~1.5 hours) | **Priority:** P1 | **Depends on:** T-11 ✓, T-14/SchemaV2 ✓

---

### ~~T-12-v2: Meal Planning v2 — Cluster Model~~ — COMPLETED feature/v1-ship (2026-03-30)
**Shipped:** SchemaV4 (MealPlanMeal + MealPlanMealItem, 14-model schema). Multi-item dinner clusters with user-editable name. FoodLog-based "Recently Made" history (90-day window). Live API search via UnifiedFoodSearchService in MealPickerSearchView (3 tabs: Recipes, Foods, Note). Multi-add sheet UX (stays open, Added chips, Done button). copyToNextWeek() deep-copies MealPlanMeal + MealPlanMealItem. Legacy MealPlanEntry records cleared on first V4 launch. 35-path test suite (MealPlanV2Tests + SchemaV4MigrationTests).

---

### ~~T-12-RestoreUpdate: SchemaV5 + Meal Plan Backup Round-Trip~~ ✓ SHIPPED 2026-04-16
**What:** Add meal plan data to the backup ZIP (3 new CSV files: `meal_plans.csv`, `meal_meals.csv`, `meal_items.csv`) and restore them in `BackupService.restoreBackup()`. Adds `var id: UUID = UUID()` to `MealPlan`, `MealPlanMeal`, `MealPlanMealItem` as SchemaV5 (lightweight migration — no explicit plan wired). Folds T-12-BackupTest (full round-trip XCTest suite, 22 tests). **Committed:** feat: T-12-RestoreUpdate (a245a14)
**Why:** Export-only is a half-loop. Until this ships, a restore from a V4+ backup silently drops all meal plan data.
**Pros:** Completes the backup/restore guarantee for the app. Zero data loss on reinstall.
**Context:** Deliberately excluded from T-12-v2 per /plan-eng-review 2026-03-30. Plan reviewed 2026-04-03.
**CSV schema:** `meal_plans.csv` (id, weekStartDate) · `meal_meals.csv` (id, planId, date, mealType, name) · `meal_items.csv` (id, mealId, recipeId, foodItemId, servingSizeId, note, servingCount).
**Import order:** foods → servings → logs → recipes → ingredients → meal_plans → meal_meals → meal_items.
**Merge-mode dedup:** UUID-based skip + weekStartDate secondary dedup for MealPlan (prevents duplicate weeks when destination already has a plan for that week under a different UUID).
**XOR validation:** import skips MealPlanMealItem rows where all of recipeId/foodItemId/note are empty.
**Ship checklist:** Must validate SchemaV5 migration on a physical device with existing V4 data before submitting.
**Depends on:** T-12-v2 | **Effort:** S (human: ~1 day / CC: ~20 min) | **Priority:** P2

---

### T-12-MealTemplates: Reusable Named Meal Clusters
**What:** Allow user to save a named `MealPlanMeal` as a reusable template (e.g., "PB Night" = PB + bread + honey). Templates appear in a "Templates" section in MealEntrySheet, separate from "Recently Made."
**Why:** Once the cluster model ships, templates are the natural next step. The "PB Night" naming UX was specifically called out as a user goal in the CEO plan.
**Pros:** High-value once user has established dinner patterns. The data model already supports it — `MealPlanMeal.name` + `items` are exactly the template structure.
**Cons:** Requires a persistent "template" flag or a new `MealTemplate` model (separate from per-week planning). New schema version (V5).
**Context:** Deferred from T-12-v2 per CEO review 2026-03-29. The cluster model foundation is required first.
**Depends on:** T-12-v2 | **Effort:** M (human: ~3 days / CC: ~20 min) | **Priority:** P3

---

### T-12-AllMealTypes: Breakfast/Lunch/Snack Cluster UI
**What:** Expose Breakfast, Lunch, and Snack slots in the expanded day row, each with their own MealPlanMeal cluster and "Recently Made" history (sourced from FoodLog records for the respective mealType).
**Why:** The model supports all MealType values today. The dinner-only UI is a v1 scope decision, not a model limitation.
**Pros:** Completes the planning surface. Users who eat the same breakfast daily would benefit most.
**Cons:** 4 clusters per day × 7 days = 28 potential clusters. The "Recently Made" chip source becomes mealType-scoped (breakfast chips for breakfast slots, etc.). `loadRecentDinnerOccasions()` becomes `loadRecentOccasions(for: mealType)`.
**Context:** Deferred from T-12-v2 per CEO review 2026-03-29. Dinner is the highest-variance slot and the primary planning use case.
**Depends on:** T-12-v2 | **Effort:** M (human: ~2 days / CC: ~15 min) | **Priority:** P3

---

### T-12-iPad: Meal Planning — iPad Calendar Grid
**What:** Full-week calendar grid layout for iPad (`.regular` sizeClass). Drag-and-drop meal assignment between day cells. Replaces the collapsible list layout on iPad.
**Context:** Same SwiftData models as T-12 iPhone. Requires T-12 to ship first. Deferred from T-12 v1 per CEO review 2026-03-29.
**Effort:** M (human: ~1 week / CC: ~30 min) | **Priority:** P3 | **Depends on:** T-12

---

### T-12-WeekSummary: Meal Planning — Week Nutrition Summary
**What:** Weekly nutrition summary card at the top of MealPlannerView showing totals vs. UserPreferences goals (Cal/P/C/F). Includes % of goal hit for the week.
**Context:** Per-day pills (4 pills: Cal/P/C/F) are sufficient for v1. Week summary adds a goals layer. Deferred from T-12 v1 per CEO review 2026-03-29. Requires UserPreferences nutrition goals to be set.
**Effort:** S (human: ~1 day / CC: ~15 min) | **Priority:** P3 | **Depends on:** T-12

---

### T-12-TodayView: Plan-Aware TodayView in BiteLedger
**What:** BiteLedger's TodayView shows today's planned meals (from MealPlanEntry) alongside logged FoodLog entries. "Planned" section shows what's scheduled; "Logged" shows what's been recorded.
**Context:** Cross-app data read — BiteLedger reads MealPlan/MealPlanEntry from the shared store. Deferred from T-12 v1 per CEO review 2026-03-29 (cross-app integration is v2).
**Effort:** M (human: ~3 days / CC: ~20 min) | **Priority:** P3 | **Depends on:** T-12

---

### T-12-ShoppingCart: ShoppingCart SwiftData Persistence
**What:** Migrate ShoppingCart from UserDefaults to SwiftData so the cart persists across app restarts and could eventually sync across devices.
**Context:** ShoppingCart is currently UserDefaults-backed (`BitePlan/BitePlan/ShoppingCart.swift`). Works for v1. Deferred from T-12 per CEO review 2026-03-29.
**Effort:** S (human: ~1 day / CC: ~15 min) | **Priority:** P3 | **Depends on:** T-12

---

### T-13: Pantry Filter / "What can I make?"
**What:** Adaptive layout: iPhone shows ingredient chip filter bar at top of RecipesListView ("I have chicken + garlic" → filters recipes). iPad shows full pantry inventory sidebar panel.
**Context:** Reuses `IngredientMatching.swift` scoring logic. More useful after library has 20+ recipes. iPhone-first interaction (standing at fridge); iPad gets full management view.
**Effort:** M (human: ~2 days / CC: ~20 min) | **Priority:** P3 | **Depends on:** Recipe library maturity

---

---

### ~~D-9: BitePlan Toolbar Consolidation~~ — COMPLETED feature/v1-ship (2026-03-31)
**Shipped:** `RecipesListView` toolbar consolidated to gear (Settings, leading) + `+` Menu (Import from URL / Scan Recipe Card / Create Manually, trailing). Compliant with DESIGN.md max-2-leading-items rule. Grid cells use `.frame(maxHeight: .infinity, alignment: .top)` for consistent card heights.

---

## Completed

- **T-14: SchemaV2 — FoodHistoryEntry (Personal Food History Index)** — New `FoodHistoryEntry` @Model (one record per (FoodItem, MealType)), lightweight V1→V2 migration in both apps, `FoodLog.create()` extended with `context:` param to drive upsert at all 6 call sites, chunked @MainActor backfill guarded by `UserPreferences.hasBackfilledFoodHistory`, `RecentFoodsForMealView` migrated to O(1) history-based query, 12 unit tests. **Completed:** feature/v1-ship (2026-03-22)

- **T-20: Document SchemaV3 targets in CLAUDE.md** — Added schema version roadmap (V1/V2/V3 with owners) to workspace CLAUDE.md "Schema Migration Policy" section. **Completed:** feature/v1-ship (2026-03-22)

- **Nutrient Spotlight (Phase 2, Feature 1):** `NutrientSpotlightEngine` pure struct (5 spotlight nutrients, 120%/3-of-7 defaults, injectable params); `SpotlightResult` with `Sendable` Nutrient; `Nutrient.spotlightDisplayName` + `Nutrient.value(from:)` extensions; `NutrientSpotlightCard` in HistoryView (ElevatedCard, 2 nutrient rows, VoiceOver combined); spotlight chip in TodayView (Capsule, eye.fill icon, tap→History tab, swipe/xmark dismiss, AppStorage day-persistence, ≥2 meal-types gate); 7 unit tests all passing. **Completed:** feature/v1-ship (2026-03-21)

- **E-1: Startup Backfill Completion Flags** — `has*` flags added to `UserPreferences`; each backfill skips on subsequent launches. **Completed:** v0.1.0.0 (2026-03-20)
- **E-2: Replace fatalError with AppStoreErrorView** — Graceful error screen + Retry button on store init failure. **Completed:** v0.1.0.0 (2026-03-20)
- **E-3: Move `defaultGoalValue` to `Nutrient` enum** — Removed duplicated switch statements from SettingsView and GoalRow. **Completed:** v0.1.0.0 (2026-03-20)
- **E-4: Write Unit Tests for Critical Math Paths** — 17 `NutritionCalculator` tests, 38 ingredient-matching tests. All pass. **Completed:** v0.1.0.0 (2026-03-20)
- **E-5: Fix O(n²) cleanUpDuplicates** — Single fetch + `[UUID: [FoodLog]]` dictionary. **Completed:** pre-v0.1.0.0
- **T-02: Quick-Add Recent/Frequent Foods** — Top 8 most-frequently logged foods per meal type, 3+ day gate, excludes already-logged-today. **Completed:** 2026-03-20
- **T-03: Streak Milestone Celebrations** — `lastCelebratedMilestone` in UserPreferences; milestones [3,7,14,30,60,100] trigger haptic + toast overlay. **Completed:** 2026-03-20
- **T-04: Schema Migration (VersionedSchema)** — `BiteLedgerMigrationPlan` + `BitePlanMigrationPlan` wired into both apps. **Completed:** 2026-03-20
- **T-05: NutritionTile VoiceOver Accessibility** — Both tiles have `.accessibilityElement(children: .ignore)` + synthesized labels with goal context. **Completed:** pre-v0.1.0.0
- **NEW-1: Weekly Logging Recap Share Card** — `ImageRenderer` share card from HistoryView toolbar. **Completed:** v0.1.0.0 (2026-03-20)
- **Local Search Word-Order Fix** — `matchesQuery()` in FoodSearchView: exact phrase first, then all words any order. Fixes "margherita pizza" → "pizza, margherita". **Completed:** 2026-03-20
- **T-11: BitePlan Kitchen Intelligence (v1.1 — Features 1–3)** — Recipe Scaling (already in RecipeDetailView), Cooking Mode (`CookingModeView` full-screen step navigation, screen always-on), Shopping List (`ShoppingCart` @Observable + UserDefaults persistence, `ShoppingListView` with categorized sections, swipe actions, share sheet). Feature 4 (Log to BiteLedger) deferred to v1.2. **Completed:** v0.1.1.0 (2026-03-20)
- **v1.2 Phase 1 — Search quality + micro-celebration:** (1) USDA data types changed from SR Legacy + Survey (FNDDS) to Foundation + SR Legacy + Branded; `USDAFoodDetail.toProductInfo()` now branches on Branded to populate *Serving fields from FDA label serving size; `ProductInfo` gains `dataType: String?`; (2) 3-day gate removed from `RecentFoodsForMealView` — recent foods show immediately on first log; (3) T-08 micro-celebration shipped (`hasSeenFirstLogCelebration: Bool?` in UserPreferences, haptic + 2s overlay in TodayView fires exactly once); (4) `AddFoodView.swift` dead code deleted; (5) 5 tests added: USDA Branded/Foundation/SR Legacy branching + micro-celebration flag. **Completed:** feature/v1-ship (2026-03-21)
- **Backup & Restore (both apps):** ZIP-based backup/restore via `BackupService` in BiteLedgerCore. `createBackup` stages manifest.json + 5 CSVs + recipe images into a temp dir, zips with ZIPFoundation, returns shareable URL. `restoreBackup` extracts, validates, and imports with `.replaceAll` or `.merge` (UUID-based skip). `resetDatabase` supports 4 scopes (logsOnly/allFoodData/recipesOnly/everything). Both BiteLedger and BitePlan have `BackupRestoreView` + `SettingsView` accessed from their respective settings/toolbar gear. `CSVImporter.importBiteLedger` gained `skipExistingUUIDs: Bool` with O(n) seed map pre-fetch. **Completed:** feature/v1-ship (2026-03-21)
