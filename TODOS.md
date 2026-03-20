# TODOS.md — Food Apps

Tracked design and product work. Created by /plan-design-review on 2026-03-19.
Engineering items added by /plan-eng-review on 2026-03-19.
Product vision + new items added by /plan-ceo-review on 2026-03-19.

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

### Schema Compatibility Policy (from /plan-ceo-review)
Before shipping any SchemaV2+ change: verify that a SchemaV1 app can open a V2 store without crashing. If backwards compat fails, require simultaneous App Store release of both apps.

---

## P3 — Future

### T-06: HistoryView Design Overhaul
**What:** Redesign HistoryView to be the "look back" surface. Ideal: trend chart + calendar strip + day detail.
**Effort:** L | **Priority:** P3

---

### T-07: Meal Reminder Notifications
**What:** Optional push notifications at configured meal times: "Haven't logged lunch yet."
**Context:** Requires `UNUserNotificationCenter` permission request. Store reminder times in UserPreferences. Send local notifications. Must not be annoying — off by default, easy to dismiss/disable.
**Effort:** M | **Priority:** P3

---

### T-08: First-Log Micro-Celebration
**What:** A brief, delightful animation when the user logs their very first food item ever.
**Context:** Detect: `logs.count == 1` after saving, and `UserPreferences.hasEverLogged == false`. Set flag, fire haptic, show 2-second overlay.
**Effort:** XS | **Priority:** P3

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

### T-11: RecipeCard Cooking Mode + Shopping List
**What:** Full-screen step-by-step cooking mode + grocery list from recipe ingredients.
**Context:** RecipeCard differentiators vs BiteLedger. Build after initial App Store ship.
**Effort:** L | **Priority:** P3 | **Depends on:** RecipeCard core stability

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
