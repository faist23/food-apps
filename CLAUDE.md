# CLAUDE.md — Food Apps Workspace

Two standalone iOS apps sharing a common data layer:

- **BiteLedger** (`BiteLedger/`) — privacy-first food & nutrition tracker
- **RecipeCard** (`RecipeCard/`) — recipe manager and importer
- **BiteLedgerCore** (`BiteLedgerCore/`) — shared Swift package (models, services, calculators)

Platform: iOS 18.3+, Swift 6.0, SwiftUI + SwiftData, Xcode 16.3.

Both apps ship independently on the App Store. When both are installed they share
the same SwiftData store via App Groups and can read each other's data.

Each app has its own `CLAUDE.md` for app-specific rules. This file covers everything
that applies to both.

---

## Shared Data Store (Critical)

- **App Group ID:** `group.com.ridepro.biteledger`
- **Store file:** `biteledger.store`

Both `BiteLedgerApp.swift` and `RecipeCardApp.swift` open the same physical store.
The `Schema([...])` list in both files **must always be identical and in the same
order**. If one app registers a model the other does not, the shared store will
fail to open on whichever app launches second.

**Any schema change requires a coordinated release of both apps.**

### Current schema (9 models — must match in both apps)

| Model | Purpose |
|---|---|
| `FoodItem` | Food definition with nutrition data (per100g or perServing mode) |
| `ServingSize` | A serving option for a food (label + optional gramWeight) |
| `FoodLog` | Logged meal entry with frozen nutrition snapshot |
| `UserPreferences` | Goals, pinned nutrients, display settings (JSON-encoded) |
| `Recipe` | A saved recipe with yield and source URL |
| `RecipeIngredient` | One ingredient line in a recipe, linked to a FoodItem |
| `CanonicalFood` | Reference food with authoritative serving → gram conversions (e.g. "Peanut Butter": 1 tbsp = 16g). Seeded once by `CanonicalFoodSeeder`. |
| `ServingConversion` | Unit → gram mapping for a CanonicalFood (e.g. tbsp = 16g, cup = 258g) |
| `FallbackSource` | Links a FoodItem to its enrichment source (USDA or FatSecret) for provenance and future re-enrichment |

### Relationships
- `FoodItem` → `ServingSize[]` (cascade delete)
- `FoodItem` → `FoodLog[]` (nullify on delete — logs survive food deletion)
- `ServingSize` → `FoodLog[]` (nullify on delete)
- `Recipe` → `RecipeIngredient[]` (cascade delete)
- `RecipeIngredient` → `FoodItem` (nullify on delete)
- `RecipeIngredient` → `ServingSize` (nullify on delete — **no declared inverse**;
  must be manually nullified before deleting ServingSizes or the app will crash
  with "model instance was invalidated")

### Schema Migration Policy (Critical — Read Before Any Schema Change)

**Current state:** both apps handle schema mismatches by deleting and recreating
the store. Acceptable during development with no external users. Must be replaced
before shipping.

**Required for all future schema changes:**
- Use `VersionedSchema` and `SchemaMigrationPlan` — never delete and recreate the store
- Every change needs a new schema version + migration stage
- Migrations must be non-destructive: add nullable fields, migrate data forward,
  never drop columns with live data
- Both apps must ship the migration in the same release
- Export via CSV before any schema change during development (developer safety net)

---

## Architecture Rules (Enforced — Do Not Deviate)

### Nutrition Math Lives Only in `NutritionCalculator.swift`
- Zero nutrition math in views, pickers, models, or extensions
- **per100g formula:** `(gramWeight / 100) × nutritionPer100g × quantity`
- **perServing formula:** `nutritionPerServing × quantity`
- Use `NutritionCalculator.preview()` for live picker previews (not stored)
- Use `NutritionCalculator.calculate()` only when creating a new `FoodLog`
- Use `NutritionCalculator.fromLog()` when displaying existing log entries

### FoodItem Nutrition Modes
- `NutritionMode.per100g` — USDA, OpenFoodFacts, packaged foods with known gram
  weights. Nutrition values are per 100g.
- `NutritionMode.perServing` — manual entry, recipes, FatSecret no-gram items,
  LoseIt imports. Nutrition values are per 1 default serving.
- `100g` is **never shown to users** — it is internal storage only.

### ServingSize Rules
- `label` has the quantity baked in (`"1 cup"`, `"2 cookies"`) — never store
  quantity separately
- `gramWeight` is `nil` for perServing foods and dimensionless servings (sandwich, slice)
- `gramWeight` is **never estimated** — if unknown, store `nil`
- No multipliers stored anywhere — all math is done at calculation time
- `unit: String?` — stored explicitly at creation time so views never parse it back
  out of `label`. All creation paths must populate this when the unit is known.
  `ServingSizeParser` is the fallback for records where `unit` is `nil`.

### FoodLog Nutrition is Frozen at Log Time
- `*AtLogTime` fields are set **once** by `FoodLog.create()` and never recalculated
- Editing a `FoodItem` never rewrites log history
- Always use `FoodLog.create(mealType:quantity:food:serving:)` — it is the only
  correct way to create a log entry
- When displaying a log entry, read `*AtLogTime` fields; never call
  `NutritionCalculator` on existing logs

---

## Food Data Sources

`UnifiedFoodSearchService` fans out to three APIs in parallel and merges results:

1. **USDA FoodData Central** — whole foods, fruits, vegetables (prefix: `usda_`)
2. **FatSecret** — restaurant foods, OAuth 1.0, credentials in `fatsecret.plist`
   (prefix: `fatsecret_`)
3. **Open Food Facts** — packaged/barcoded products (no prefix)

Result ordering: USDA → FatSecret → OpenFoodFacts, then sorted by relevance
(exact brand match > exact name match > starts-with > contains).
OpenFoodFacts results with no serving size or only "100g" data are filtered out.

### Key Credentials
- **FatSecret:** OAuth 1.0 credentials in `BiteLedger/fatsecret.plist`
  (not committed — create from template if missing)
- **USDA API key:** hardcoded in `USDAFoodDataService.swift`

---

## Nutrition Display — FDA Label Format (Enforced)

Every view showing nutrition for a food, meal, or day must resemble an FDA
nutrition facts label. Do not regress this pattern.

- "Nutrition Facts" header in large black bold text, followed by a heavy black divider
- Serving description line (`"1 cup (240g)"`, `"Today's Diary"`, etc.)
- Calories displayed extra-large (32–44pt, black weight), value right-aligned
- Heavy divider after Calories
- "% Daily Value*" right-aligned header before nutrient rows
- Thin black dividers (`height: 1`) between every row
- Top-level nutrients (Total Fat, Cholesterol, Sodium, Total Carbohydrate, Protein)
  in **bold**
- Sub-nutrients (Saturated Fat, Trans Fat, Dietary Fiber, Total Sugars) indented
  `padding(.leading, 20)`, regular weight
- % DV column: right-aligned, uses user goals if set, FDA 2000-cal defaults otherwise
- Heavy divider (`height: 8`) before the vitamins/minerals section
- FDA disclaimer footnote at the bottom (full labels only)

**FDA daily values:**
Total Fat 78g, Saturated Fat 20g, Cholesterol 300mg, Sodium 2300mg,
Total Carbohydrate 275g, Dietary Fiber 28g, Protein 50g, Vitamin D 20mcg,
Calcium 1300mg, Iron 18mg, Potassium 4700mg.

---

## Nutrient Tracking

`Nutrient` enum in `UserPreferences.swift` is the canonical list of all trackable
nutrients. It defines units, categories (macros/minerals/vitamins/special), and
default goal types (minimum/maximum/range). When adding new nutrients, update
`FoodItem`, `FoodLog`, and `NutritionCalculator` together — they must stay in sync.
