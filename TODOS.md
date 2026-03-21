# TODOS.md — Food Apps

Tracked design and product work. Created by /plan-design-review on 2026-03-19.
Engineering items added by /plan-eng-review on 2026-03-19.
Product vision + new items added by /plan-ceo-review on 2026-03-19.
Post-v1 roadmap + iPad strategy added by /plan-ceo-review on 2026-03-20.

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
2. **RecipeCard-only** — manage/cook recipes, no food diary
3. **Both apps** — power user who logs recipes from RecipeCard into BiteLedger

Future implication: BiteLedger needs manual + URL recipe creation for segment 1.
RecipeCard's differentiators: URL import, OCR, cooking mode, shopping list.

### iPad Strategy (from /plan-ceo-review 2026-03-20)
**Adaptive layout, not exclusive.** Meal planning and pantry use `horizontalSizeClass` to adapt:
- `.compact` (iPhone): simplified list views (7-day planner as list, ingredient filter chips)
- `.regular` (iPad): full grid views (week calendar with drag-and-drop, pantry inventory sidebar)
Same SwiftData models underneath. Same App Store download. iPhone users get full planning features in list form; iPad users get the full grid experience.

### Schema Compatibility Policy (from /plan-ceo-review)
Before shipping any SchemaV2+ change: verify that a SchemaV1 app can open a V2 store without crashing. If backwards compat fails, require simultaneous App Store release of both apps.

---

## P3 — Future

### T-16: RecipeCard — Auto-total time unit tests
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

### T-10: Recipe Creation in BiteLedger (Manual + URL)
**What:** Allow BiteLedger-only users to create recipes — both manual and URL import. No OCR, no photos (RecipeCard differentiators).
**Effort:** L | **Priority:** P3 | **Depends on:** Stable RecipeCard recipe model + SchemaV3

---

### T-11: Log to BiteLedger (v1.2 — Feature 4 only)
**What:** Allow RecipeCard users to log a recipe directly into BiteLedger's food diary from RecipeDetailView.
- Build RecipeServingSheet (meal type + quantity picker)
- BiteLedger declares `biteledger://` URL scheme in Info.plist
- RecipeCard adds `biteledger` to LSApplicationQueriesSchemes
- RecipeDetailView shows "Log to BiteLedger" button when `UIApplication.canOpenURL(biteledger://)` returns true
- `FoodLog.create(food: recipe.foodItem, serving: nil, quantity: selectedQty)` writes to shared store
**Effort:** M | **Priority:** P1 (v1.2) | **Depends on:** v1.1 shipped (done)

---

### T-12: Meal Planning
**What:** Adaptive layout: iPhone shows 7-day list planner (Mon: Chicken Soup); iPad shows full week calendar grid with drag-and-drop. Shopping list generates from the full week's plan.
**Context:** SchemaV2 required — needs `MealPlan` model. iPhone uses `.compact` sizeClass (list), iPad uses `.regular` (grid). Depends on T-11 shopping list shipping first.
**Effort:** L (human: ~1 week / CC: ~1 hour) | **Priority:** P3 | **Depends on:** T-11, T-14 (SchemaV2)

---

### T-13: Pantry Filter / "What can I make?"
**What:** Adaptive layout: iPhone shows ingredient chip filter bar at top of RecipesListView ("I have chicken + garlic" → filters recipes). iPad shows full pantry inventory sidebar panel.
**Context:** Reuses `IngredientMatching.swift` scoring logic. More useful after library has 20+ recipes. iPhone-first interaction (standing at fridge); iPad gets full management view.
**Effort:** M (human: ~2 days / CC: ~20 min) | **Priority:** P3 | **Depends on:** Recipe library maturity

---

### T-14: SchemaV2 Migration
**What:** Add `MealPlan` model (enables T-12 meal planning). `steps: [String]` is no longer needed — `recipe.directions: [String]` already exists in the model stored as `directionsData: Data?`.
**Context:** Coordinated release of both apps required per schema policy. Export via CSV before migrating during development. SchemaV2 scope is now smaller than planned.
**Effort:** S (human: ~1 day / CC: ~15 min) | **Priority:** P2 | **Depends on:** T-11 shipped, both apps stable

---

### D-9: RecipeCard Toolbar Consolidation
**What:** Consolidate RecipeCard's `RecipesListView` toolbar actions into a `.menu` button to stay compliant with DESIGN.md's max-2-leading-items rule. Adding the Settings gear icon during the Backup & Restore feature will push the toolbar beyond 4 items.
**Why:** DESIGN.md explicitly flags 4+ leading toolbar items as an anti-pattern. A menu button groups Import/Scan/Import-OCR behind a single `+` or `ellipsis` icon.
**Pros:** Cleaner toolbar, consistent with iOS conventions, room for future toolbar additions.
**Cons:** Minor interaction change for existing users (import taps go through one extra tap).
**Context:** RecipesListView currently has: Edit, Import (URL), Scan (OCR), + (new recipe). Adding a gear icon will make 5. DESIGN.md toolbar rule: max 1-2 leading items. This was deferred when adding Settings gear in the Backup & Restore feature (feature/v1-ship).
**Effort:** XS (human: ~1 hour / CC: ~10 min) | **Priority:** P2 | **Depends on:** Backup & Restore shipped

---

## Completed

- **E-1: Startup Backfill Completion Flags** — `has*` flags added to `UserPreferences`; each backfill skips on subsequent launches. **Completed:** v0.1.0.0 (2026-03-20)
- **E-2: Replace fatalError with AppStoreErrorView** — Graceful error screen + Retry button on store init failure. **Completed:** v0.1.0.0 (2026-03-20)
- **E-3: Move `defaultGoalValue` to `Nutrient` enum** — Removed duplicated switch statements from SettingsView and GoalRow. **Completed:** v0.1.0.0 (2026-03-20)
- **E-4: Write Unit Tests for Critical Math Paths** — 17 `NutritionCalculator` tests, 38 ingredient-matching tests. All pass. **Completed:** v0.1.0.0 (2026-03-20)
- **E-5: Fix O(n²) cleanUpDuplicates** — Single fetch + `[UUID: [FoodLog]]` dictionary. **Completed:** pre-v0.1.0.0
- **T-02: Quick-Add Recent/Frequent Foods** — Top 8 most-frequently logged foods per meal type, 3+ day gate, excludes already-logged-today. **Completed:** 2026-03-20
- **T-03: Streak Milestone Celebrations** — `lastCelebratedMilestone` in UserPreferences; milestones [3,7,14,30,60,100] trigger haptic + toast overlay. **Completed:** 2026-03-20
- **T-04: Schema Migration (VersionedSchema)** — `BiteLedgerMigrationPlan` + `RecipeCardMigrationPlan` wired into both apps. **Completed:** 2026-03-20
- **T-05: NutritionTile VoiceOver Accessibility** — Both tiles have `.accessibilityElement(children: .ignore)` + synthesized labels with goal context. **Completed:** pre-v0.1.0.0
- **NEW-1: Weekly Logging Recap Share Card** — `ImageRenderer` share card from HistoryView toolbar. **Completed:** v0.1.0.0 (2026-03-20)
- **Local Search Word-Order Fix** — `matchesQuery()` in FoodSearchView: exact phrase first, then all words any order. Fixes "margherita pizza" → "pizza, margherita". **Completed:** 2026-03-20
- **T-11: RecipeCard Kitchen Intelligence (v1.1 — Features 1–3)** — Recipe Scaling (already in RecipeDetailView), Cooking Mode (`CookingModeView` full-screen step navigation, screen always-on), Shopping List (`ShoppingCart` @Observable + UserDefaults persistence, `ShoppingListView` with categorized sections, swipe actions, share sheet). Feature 4 (Log to BiteLedger) deferred to v1.2. **Completed:** v0.1.1.0 (2026-03-20)
- **v1.2 Phase 1 — Search quality + micro-celebration:** (1) USDA data types changed from SR Legacy + Survey (FNDDS) to Foundation + SR Legacy + Branded; `USDAFoodDetail.toProductInfo()` now branches on Branded to populate *Serving fields from FDA label serving size; `ProductInfo` gains `dataType: String?`; (2) 3-day gate removed from `RecentFoodsForMealView` — recent foods show immediately on first log; (3) T-08 micro-celebration shipped (`hasSeenFirstLogCelebration: Bool?` in UserPreferences, haptic + 2s overlay in TodayView fires exactly once); (4) `AddFoodView.swift` dead code deleted; (5) 5 tests added: USDA Branded/Foundation/SR Legacy branching + micro-celebration flag. **Completed:** feature/v1-ship (2026-03-21)
- **Backup & Restore (both apps):** ZIP-based backup/restore via `BackupService` in BiteLedgerCore. `createBackup` stages manifest.json + 5 CSVs + recipe images into a temp dir, zips with ZIPFoundation, returns shareable URL. `restoreBackup` extracts, validates, and imports with `.replaceAll` or `.merge` (UUID-based skip). `resetDatabase` supports 4 scopes (logsOnly/allFoodData/recipesOnly/everything). Both BiteLedger and RecipeCard have `BackupRestoreView` + `SettingsView` accessed from their respective settings/toolbar gear. `CSVImporter.importBiteLedger` gained `skipExistingUUIDs: Bool` with O(n) seed map pre-fetch. **Completed:** feature/v1-ship (2026-03-21)
