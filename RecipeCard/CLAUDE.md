# CLAUDE.md — RecipeCard

Recipe import, management, and nutritional tracking app.
See `../CLAUDE.md` for shared workspace rules (schema, nutrition math,
data sources, FDA label format).

---

## Build & Run

```bash
# Build
xcodebuild -project RecipeCard.xcodeproj -scheme RecipeCard \
  -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run all tests
xcodebuild test -project RecipeCard.xcodeproj -scheme RecipeCard \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

---

## Recipe Import Flow

### URL import
1. User provides a URL → `RecipeImportService.import(url:)` fetches the page
   and parses Schema.org `Recipe` JSON-LD
2. `fallbackParse(_:)` cleans each raw ingredient string into a searchable term:
   - Strips nested parentheses (3 passes via regex)
   - Strips everything after the first comma
   - Removes prep-note words (`"chopped"`, `"diced"`, `"unsalted"`, `"roasted"`,
     `"jarred"`, `"organic"`, `"grass-fed"`, `"rotisserie"`, etc.)
   - **`"canned"` is NOT stripped** — "canned chicken" is a distinct food item
3. `RecipeImportReviewView` runs `autoMatch()` then lets user review/save

### OCR import (scan a physical recipe card)
Three-screen flow — all in the same `NavigationStack` owned by `OCRRecipeImportView`:

1. **`OCRRecipeImportView`** — camera + photo library picker; "Scan Photo" button
   runs Vision OCR on every selected image, calls `service.preprocessOCRLines()`
   on the raw lines, then navigates to `OCRTextReviewView`.
   - Vision coordinate system: Y=0 = bottom of image, Y=1 = top.
     Sort uses `dy < 0` (not `dy > 0`) to get top-to-bottom order.

2. **`OCRTextReviewView`** — shows preprocessed OCR lines in an editable `TextEditor`
   (monospaced font). User fixes remaining handwriting misreads before Claude sees
   the text. Also has a source field (auto-filled from `result.detectedSource` if
   the user leaves it blank). "Process Recipe" button calls
   `service.importFromOCRLines()` and navigates to `RecipeImportReviewView`.

3. **`RecipeImportReviewView`** — standard ingredient match/review/save screen.

### `RecipeImportService.preprocessOCRLines(_:)` — public, two-pass
Called by `OCRRecipeImportView` before showing lines to the user, and again
internally by `importFromOCRLines` (idempotent).

**Pass 1 — character normalisation:**
- Strips parenthesised leading quantities: `(4) tbsp` → `4 tbsp`
- Expands unit abbreviations: `T` → `tbsp`, `t` → `tsp` (case-sensitive, word-boundary)
- Fixes OCR misreads: `+bsp` → `tbsp`, `lbsp` → `tbsp`, `tbps` → `tbsp`, etc.

**Pass 2 — noise filtering (drops lines that can't be recipe content):**
- Fewer than 2 characters
- No letters at all
- Alphanumeric density < 40 % (mostly symbols/punctuation from card artwork)
- No word with 3+ consecutive letters AND doesn't start with a quantity
  (catches single-letter OCR artifacts from decorative card lettering)

### `RecipeImportResult.detectedSource`
New `String?` field. Claude extracts "from the kitchen of / recipe by / submitted by"
style attributions from the OCR text and returns them here. `OCRTextReviewView`
auto-fills the source field if the user left it blank.

### OCR Claude prompt — key rules
- `[N]` line-number prefix on every ingredient (e.g. `"[7] 2 cups sugar"`) —
  code sorts by N after parsing, guaranteeing original card order regardless of
  how Claude internally reasons.
- Anti-hallucination: only ingredients explicitly written in OCR lines.
- Parenthesised quantities `(4)` explained as amounts, not step numbers.
- Sub-sections (`For top:`, `For frosting:`) included with label prefix.
- Servings: handles `yield X`, `makes X dozen` (× 12), default = 4.

### Key rule: `MatchedIngredient.editedRawText` and `editedUnit`
- Always use `editedRawText` (not `parsed.rawString`) for the ingredient's
  human-visible text — rows, food picker title, saved `rawText` on `RecipeIngredient`
- `editedUnit` (not `parsed.unit`) must be used in `matchSingle` and
  `IngredientFoodPickerView.selectFood` for `resolveGrams` calls — `parsed` is
  immutable and won't reflect unit changes the user makes when editing text.
- `matchVersion += 1` must be called after `matchSingle` completes from a text
  edit to trigger a nutrition-header refresh (same mechanism as food picker).

---

## IngredientSeeder

Seeds ~410 common ingredients from `ingredients.json` (bundled in BiteLedgerCore
via `Bundle.module`) into the shared store on first launch.

- **Current version:** `usda_seed_v4` — bump this string to force a re-seed
- Cleanup deletes any food where `source.hasPrefix("usda_seed") && source != currentVersion`
- `cal >= 0` guard (not `> 0`) — allows zero-calorie foods like salt
- **Critical — before deleting old seed foods:** explicitly nullify
  `RecipeIngredient.servingSize` and `FoodLog.servingSize` references pointing
  to those foods' ServingSizes. `ServingSize` has no declared inverse relationship
  to `RecipeIngredient`, so SwiftData's nullify delete rule cannot fire automatically.
  Skipping this step causes a fatal crash: "model instance was invalidated because
  its backing data could no longer be found in the store".

---

## autoMatch() — Ingredient Matching

Located in `RecipeImportReviewView`. Runs once on view appear for all ingredients.

### Term preparation (applied in order)
1. **`termAliases`** dict maps ambiguous terms to specific ones:
   - `"pepper"` → `"black pepper"`
   - `"ground pepper"` → `"black pepper"`
   - `"black pepper ground"` → `"black pepper"`
   - `"seasoning"` → `"salt"`
   - `"chicken cutlet"` / `"chicken cutlets"` → `"chicken breast"`
   - `"canned chicken"` / `"chicken canned"` → `"chicken breast"` (nutritional proxy)
2. **Cheese stripping** — drop trailing `" cheese"` unless the full term is a
   recognised compound (`"cream cheese"`, `"cottage cheese"`, `"goat cheese"`,
   `"american cheese"`, `"swiss cheese"`, `"blue cheese"`, `"brie cheese"`).
   This makes `"mozzarella cheese"` → `"mozzarella"` for an exact DB match.

### Local DB search (always runs first)
- `FetchDescriptor<FoodItem>` with `localizedStandardContains(term)`
- Scored with `ingredientScore(foodName:term:)` (see below)
- Seeded/built-in foods get **+20 bonus** (`source.hasPrefix("usda_seed")` or
  `source.hasPrefix("built_in")`)
- On tied scores, shorter name wins (more specific match)
- Accept threshold: score ≥ 30

### `localIsAuthoritative` — skipping the live API
If the local match has a `usda_seed` or `built_in` source prefix, skip the live
API entirely. Prevents a live USDA call from overriding a correctly seeded food.

### Live API fallback
Only runs when local match is absent or from an untrustworthy source.
Uses `UnifiedFoodSearchService.searchAllDatabases(query:)`.
Creates and persists a `FoodItem` via `createOrFetchUSDAFood(product:)`.
Falls back gracefully to the local candidate if the API call fails.

---

## ingredientScore()

```
100 — exact name match
 50 — food name starts with the term, followed by space or end of string
      (comma is NOT a valid boundary — prevents "Pepper, banana, raw"
       from scoring 50 for term "pepper")
 30 — every word in the term appears as a standalone word in the food name
      (basic plural normalisation: "breasts" → "breast", "tomatoes" → "tomato")
 10 — raw substring match only (treated as no match; callers threshold at 30)
-20 — penalty applied when score == 30 and the food name contains a processed-
      food word: "breaded", "battered", "fried", "tenders", "nuggets", "strips",
      "patty", "patties", "canned", "stewed", "flavored", "flavoured", "product",
      "seasoned", "prepared", "tri-color", "tri", "multicolor"
```

Score floor is 0 (never negative).

---

## resolveGrams() — Gram Amount Resolution

Free function in `RecipeImportReviewView.swift`. Converts a recipe ingredient's
`quantity + unit` to a gram amount using the matched food's servings.

**Must be called in two places:**
1. `autoMatch()` — when a food is first matched
2. `IngredientFoodPickerView` — when the user manually selects a different food

Never carry over a `resolvedGramAmount` from the previous food — always re-run
`resolveGrams` against the new food's servings.

### 3 passes
1. **Exact unit match** — finds a food serving whose `unit` field matches the
   recipe unit (e.g. recipe `"cup"` → serving `"1 cup"` with `gramWeight = 112`).
   Returns `(quantity / serving.amount) × gramWeight`.
2. **Cross-unit volume** — converts both the recipe quantity and the serving
   to tablespoon equivalents, then scales (e.g. `"1/2 cup"` → 8 tbsp,
   serving `"1 tbsp = 14.2g"` → 113.6g).
3. **Weight constants** — oz × 28.3495, lb × 453.592, g × 1.0.

Returns `(gramAmount: Double?, serving: ServingSize?)`. `gramAmount` is `nil`
when the unit is unrecognised — the fallback `quantity × matchedServing` path
is used instead.

---

## Calorie Consistency — Review Screen vs Saved Recipe (Critical)

`MatchedIngredient.displayCalories`:
- If `resolvedGramAmount` is set: `NutritionCalculator.calculate(food, gramAmount)`
- Else: `NutritionCalculator.calculate(food, serving, quantity)`

`save()` must store `savedQuantity` in serving units, **not raw recipe units**:
```swift
if let gram = m.resolvedGramAmount,
   let gw = m.matchedServing?.gramWeight, gw > 0 {
    savedQuantity = gram / gw   // e.g. 224g ÷ 112g-per-cup = 2.0 cups
} else {
    savedQuantity = m.quantity
}
```
The recipe detail view recalculates `savedQuantity × serving.gramWeight × cal/100g`,
so both screens must use the same gram basis or the displayed calories will diverge.

---

## Safari Share Extension (RecipeCardShare target)

`RecipeCardShare/ShareViewController.swift` — a Share Extension that lets users
send a recipe URL from Safari directly to RecipeCard.

### Flow
1. User taps Share in Safari → selects RecipeCard
2. `ShareViewController.viewDidLoad` extracts the URL from the extension context
3. URL is written to shared `UserDefaults(suiteName: "group.com.ridepro.biteledger")`
   under key `"pendingRecipeURL"`
4. Extension walks the responder chain to open `recipecard://import` (URL scheme
   registered on the RecipeCard target — do not use `UIApplication.shared` or
   `extensionContext?.open`, neither works in Share Extensions)
5. Main app receives the URL via `.onOpenURL` → `consumePendingRecipeURL()` in
   `RecipeCardApp` posts a `Notification.Name.recipeCardImportURL` notification
   **without removing the key** (key stays so `ImportRecipeView` can read it directly)
6. `RecipesListView` receives the notification → sets `pendingImportURL` →
   presents `ImportRecipeView` sheet
7. `ImportRecipeView.onAppear` uses `prefilledURL` param if set, otherwise reads
   directly from `UserDefaults` as a fallback (handles cold-launch timing).
   Removes the key once consumed.

### Key invariant
Do NOT remove `"pendingRecipeURL"` from UserDefaults in `consumePendingRecipeURL()`.
Only remove it in `ImportRecipeView.onAppear` after it has been read, otherwise a
race condition causes the URL to disappear before the view loads.

---

## IngredientFoodPickerView

Sheet presented when the user taps an ingredient row to change its match.

- **Source badges** on each search result indicate food origin:
  - **DB** (green) — `usda_seed` or `built_in` prefix (seeded, authoritative)
  - **USDA** (blue) — live USDA API result
  - **FS** (orange) — FatSecret
  - **OFx** (purple) — Open Food Facts / barcode scan
- Search runs against local DB first, then live API for novel results
  (foods not already in the local DB are created and saved)
- On food selection: call `resolveGrams(quantity:unit:food:)` to update both
  `matched.resolvedGramAmount` and `matched.matchedServing` for the new food.
  This ensures `displayCalories` in the ingredient row reflects the correct
  calories immediately after the sheet dismisses.
