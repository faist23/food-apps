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

## Engineering Decisions (from /plan-eng-review)


## P1 — Ship-Quality

### T-01: 7-Day Rolling Average History View (revised by /plan-ceo-review)
**What:** 7-day rolling average chart as hero of HistoryView. Tab picker for Cal / Protein / Carbs / Fat. Calm line chart — no red/green goal coloring, no daily target lines. FDA daily values shown as a subtle reference line only when goals are off.
**Why:** Aligns with product philosophy: the weekly pattern matters, not the daily scorecard. Rolling average naturally smooths outlier days and frames nutrition as a long-term habit. Replaces original T-01 (daily bar chart).
**Pros:** All data already in FoodLog with timestamps. `NutritionCalculator.rollingAverage()` is pure math (no queries). SwiftUI Charts does the rendering. Calm design builds trust with reluctant loggers.
**Cons:** Must handle < 7 days gracefully (fresh install, sparse data). Line chart with tab picker needs design care to stay calm.
**Context:** Math lives in `NutritionCalculator.rollingAverage(logs:days:nutrient:)`. Chart sits at top of existing `HistoryView` (chart hero, day log list below). Use `FetchDescriptor` with date predicate — do NOT fetch all logs. Wrap in `ElevatedCard`, use `BrandAccent` line color, `SurfaceCard` background. Empty state: "Log some food to see your trend" (no action button needed).
**Effort:** M (human: ~1 week / CC: ~30 min)
**Priority:** P1
**Depends on:** None

---


## P2 — Retention & Polish

## P3 — Future

### T-06: HistoryView Design Overhaul
**What:** Redesign HistoryView to be the "look back" surface. Today: unknown (needs review). Ideal: trend chart (from T-01) + calendar strip + day detail.
**Why:** HistoryView is the second tab in BiteLedger's nav and currently underserved. Adding T-01 (weekly chart) is the first step; a full calendar/history view is the second.
**Effort:** L (human: ~2 weeks / CC: ~1 hr)
**Priority:** P3
**Depends on:** T-01

---

### T-07: Meal Reminder Notifications
**What:** Optional push notifications at configured meal times: "Haven't logged lunch yet."
**Why:** Habit formation requires prompts. Most nutrition apps lose users because they forget to log. Even a single 12pm notification significantly improves retention.
**Context:** Requires `UNUserNotificationCenter` permission request. Store reminder times in UserPreferences. Send local notifications. Must not be annoying — off by default, easy to dismiss/disable.
**Effort:** M (human: ~3 days / CC: ~30 min)
**Priority:** P3
**Depends on:** None

---

### T-08: First-Log Micro-Celebration
**What:** A brief, delightful animation when the user logs their very first food item ever.
**Why:** The first log is the highest-leverage habit moment. A small acknowledgment ("First log! You're building a streak.") anchors the behavior.
**Context:** Detect: `logs.count == 1` after saving, and `UserPreferences.hasEverLogged == false`. Set flag, fire haptic, show 2-second overlay.
**Effort:** XS (human: ~1 hr / CC: ~5 min)
**Priority:** P3
**Depends on:** None

---

## New Items (from /plan-ceo-review, 2026-03-19)

### NEW-1: Weekly Logging Recap Share Card (IN SCOPE — v1.0)
**What:** A shareable weekly recap image: "6 of 7 days logged. 42 foods tracked. ~2,200 cal/day avg. 🔥 Day 12 streak." Generated via SwiftUI `ImageRenderer` → UIImage → `UIActivityViewController`.
**Why:** Celebrates logging behavior (not goal achievement). Organic marketing — users share because it feels good, not because it's a scorecard.
**Pros:** No server needed. `ImageRenderer` is iOS 16+ (meets minimum). Data already in FoodLog + UserPreferences.cachedStreak.
**Cons:** Needs `lastShareCardGeneratedWeek: Date?` in UserPreferences (SchemaV2 field). Need dedup logic: same week → "already shared this week" instead of regenerating.
**Context:** Style: FDA-label aesthetic (BiteLedger's design language). Content: days logged of 7, total unique foods, 7-day avg calorie, streak. No goal comparison, no macro breakdown — logging habit only. Share button location: HistoryView toolbar or TodayView share icon.
**Effort:** S (human: ~4 hrs / CC: ~15 min)
**Priority:** P1 (in v1.0 scope)
**Depends on:** SchemaV2 (for lastShareCardGeneratedWeek field)

---

### T-09: HealthKit Integration
**What:** Write nutrition data to Apple Health on every FoodLog creation (opt-in via `healthKitEnabled: Bool = false` in UserPreferences). All 15 nutrients map to HealthKit identifiers.
**Why:** Makes BiteLedger data durable (survives app deletion). Integrates with Apple's health ecosystem. App Store visibility in Health app.
**Pros:** Architecture is ready — `FoodLog.create()` is the single correct hook. Write path is one `HKHealthStore.save()` call.
**Cons:** Requires HealthKit entitlement + `NSHealthShareUsageDescription` + `NSHealthUpdateUsageDescription` in Info.plist for both apps. App Store privacy description review required.
**Context:** Deferred until app is stable. Wait for initial App Store ship before adding HealthKit complexity. `healthKitEnabled` should be SchemaV3 field to avoid mixing with SchemaV2.
**Effort:** M (human: ~1 week / CC: ~30 min)
**Priority:** P2 (post-ship, after stability)
**Depends on:** SchemaV3

---

### T-10: Recipe Creation in BiteLedger (Manual + URL)
**What:** Allow BiteLedger-only users to create recipes directly in BiteLedger — both manual (name + ingredients + yield) and URL import (same URL parsing as RecipeCard). Lightweight editor, not a full recipe management suite.
**Why:** Three user segments: BiteLedger-only, RecipeCard-only, both. Segment 1 (BiteLedger-only) is blocked from the one-tap recipe logging workflow today.
**Pros:** Uses existing `Recipe` + `RecipeIngredient` models from BiteLedgerCore. FoodSearchView's Recipes tab already exists. Manual creation minimal UI.
**Cons:** URL import replicates RecipeCard's core feature — need careful scope definition to avoid making RecipeCard redundant. Risk of feature creep.
**Context:** BiteLedger recipe creation should be 'lite': manual entry + URL parsing only. No OCR, no photos (those remain RecipeCard differentiators). RecipeCard = cookbook management, cooking assistance, shopping. BiteLedger = quick 'my usual meals' creation for logging.
**Effort:** L (human: ~2 weeks / CC: ~45 min)
**Priority:** P3
**Depends on:** Stable RecipeCard recipe model + SchemaV3

---

### T-11: RecipeCard Cooking Mode + Shopping List
**What:** Two features for the active cook:
1. **Cooking Mode** — full-screen step-by-step view, screen stays on, tap to advance steps
2. **Shopping List** — tap ingredients from any recipe to add to a grocery list; check off while shopping
**Why:** Differentiates RecipeCard from BiteLedger. Makes RecipeCard a kitchen companion (active use) not just a recipe reference (passive use). Strong standalone value prop for RecipeCard-only users.
**Pros:** Natural evolution once core import flows are stable. Cooking mode needs no new data. Shopping list needs a `ShoppingListItem` model.
**Cons:** Significant UI work. Shopping list persistence: shared store or local RecipeCard-only store?
**Context:** RecipeCard's three differentiators vs BiteLedger: URL import, OCR, and kitchen assistance (cooking mode + shopping list). Build after initial App Store ship and stabilization of both apps.
**Effort:** L (human: ~2 weeks / CC: ~1 hr)
**Priority:** P3
**Depends on:** RecipeCard core stability

---

## Completed

- **E-1: Startup Backfill Completion Flags** — `has*` flags added to `UserPreferences`; each backfill skips on subsequent launches. **Completed:** v0.1.0.0 (2026-03-20)

- **E-2: Replace fatalError with AppStoreErrorView** — BiteLedger and RecipeCard app init now shows graceful error screen + Retry button instead of crashing. **Completed:** v0.1.0.0 (2026-03-20)

- **E-3: Move `defaultGoalValue` to `Nutrient` enum** — Consolidated into `NutritionCalculator.DailyValues` + `Nutrient.defaultGoalValue`; removed duplicated switch statements from SettingsView and GoalRow. **Completed:** v0.1.0.0 (2026-03-20)

- **E-4: Write Unit Tests for Critical Math Paths** — 17 `NutritionCalculator` tests in BiteLedgerTests, 38 ingredient-matching tests in RecipeCardTests. All pass. **Completed:** v0.1.0.0 (2026-03-20)

- **T-01: 7-Day Rolling Average History View** — Hero chart in HistoryView with Catmull-Rom line, FDA DV reference, nutrient tab picker, graceful empty state. **Completed:** v0.1.0.0 (2026-03-20)

- **NEW-1: Weekly Logging Recap Share Card** — Shareable `ImageRenderer` card with days-logged, avg calories, streak. Available from HistoryView toolbar. **Completed:** v0.1.0.0 (2026-03-20)

- **E-5: Fix O(n²) cleanUpDuplicates** — Already fixed prior to this session. Single fetch + `[UUID: [FoodLog]]` dictionary replaces per-group DB scans. **Completed:** pre-v0.1.0.0

- **T-03: Streak Milestone Celebrations** — `lastCelebratedMilestone: Int?` added to `UserPreferences`. `.onChange(of: currentStreak)` calls `checkStreakMilestone()` in TodayView; milestones [3,7,14,30,60,100] trigger haptic + `StreakMilestoneToast` overlay (2s auto-dismiss). **Completed:** 2026-03-20

- **T-05: NutritionTile VoiceOver Accessibility** — Already implemented prior to this session. Both `NutritionTile` and `MacroBalanceTile` have `.accessibilityElement(children: .ignore)` + synthesized labels with goal context. **Completed:** pre-v0.1.0.0

- **T-02: Quick-Add Recent/Frequent Foods** — Top 8 most-frequently logged foods per meal type shown when search is empty (after 3+ distinct log days). Frequency sort, excludes already-logged-today foods. **Completed:** 2026-03-20

- **Local Search Word-Order Fix** — `matchesQuery()` free function in `FoodSearchView.swift` replaces bare `contains` in My Foods, Meals, and Recipes tab filters. Matches exact phrase first, then falls back to all words present in any order. "margherita pizza" now finds "pizza, margherita". **Completed:** 2026-03-20

- **T-04: Schema Migration (VersionedSchema)** — `BiteLedgerMigrationPlan` + `RecipeCardMigrationPlan` active; both apps use `Schema(versionedSchema:)` + `migrationPlan:` in `ModelContainer`. `BiteLedgerSchema.swift` and `RecipeCardSchema.swift` are the single sources of truth for version history. **Completed:** v0.1.0.0 (2026-03-20)
