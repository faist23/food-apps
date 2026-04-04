# DESIGN.md — Food Apps Design System

Inferred from BiteLedger's production code. Applies to both BiteLedger and BitePlan.
Last updated: 2026-03-19 by /plan-design-review.

---

## Aesthetic & Voice

**Personality:** Precise, calm, trustworthy. Like a well-designed kitchen scale — shows you exactly what you need, nothing more. Not clinical (no cold blues/grays), not cheerful (no cartoon food). The FDA label format is intentional: this app treats nutrition data with the same respect the government does.

**Mood:** Confident utility. Dark-mode-first energy. The kind of app that feels competent before you use it.

---

## Color Tokens

All colors live in `BiteLedger/Assets.xcassets`. BitePlan has these same tokens in its own `Assets.xcassets` (added in v0.1.1.0). BitePlan also has two additional CookingMode tokens: `CookingModeSurface` and `CookingModeText` (full-screen cooking overlay). Never use raw system colors (`Color.secondary`, `.accentColor`) in new code — always use a named token.

### Brand
| Token | Usage |
|---|---|
| `BrandPrimary` | Interactive elements, navigation, date picker highlights |
| `BrandAccent` | Tint for segmented pickers, progress bars (minimum goal met), links |
| `BrandGlow` | Glow effects, active state halos |

### Surfaces
| Token | Usage |
|---|---|
| `SurfacePrimary` | Screen background (root view) |
| `SurfaceCard` | Card/tile fill — slightly lighter than SurfacePrimary |
| `SurfaceElevated` | Sheets, modals, popovers |

### Text
| Token | Usage |
|---|---|
| `TextPrimary` | Main readable content |
| `TextSecondary` | Supporting labels, secondary info |
| `TextTertiary` | Hints, placeholders, disabled states |

### Utility
| Token | Usage |
|---|---|
| `DividerSubtle` | 1pt borders on cards, row dividers |

### Macro Colors
| Token | Usage |
|---|---|
| `MacroProtein` | Protein percentage text and progress indicators |
| `MacroCarbs` | Carbs percentage text and progress indicators |
| `MacroFat` | Fat percentage text and progress indicators |

### Semantic Progress Colors (dynamic — no token needed)
| State | Color |
|---|---|
| Goal met (minimum) | `.green` |
| On track | `BrandAccent` (blue) |
| Approaching maximum | `.yellow` |
| Near limit | `.orange` |
| Over limit | `.orange` (intentional — less anxiety than red) |

---

## Typography Scale

All text uses `.system()` — no custom fonts. The rounded design variant is reserved for large numeric displays.

| Role | Spec | Usage |
|---|---|---|
| Dashboard value | `system(20, .bold, .rounded)` | NutritionTile values |
| Tile label | `system(10, .semibold)` uppercased | NutritionTile labels |
| Unit label | `system(11)` | Unit suffixes next to values |
| Section header | `.headline` | Meal sections, recipe section headers |
| Body | `.body` | Ingredient rows, directions |
| Supporting | `.subheadline` | Food log rows, metadata rows |
| Caption | `.caption` | Quantity descriptions, time labels, source domains |
| Micro | `.caption2` | Footnotes, source badges |
| FDA Calories | 32–44pt, `.black` weight | DetailedNutritionView only |

---

## Spacing Scale

| Name | Value | Usage |
|---|---|---|
| `xs` | 4pt | Micro gaps (between label and unit) |
| `sm` | 8pt | Between items within a tile |
| `md` | 12pt | Card internal padding (small tiles), grid gaps |
| `lg` | 16pt | Vertical section padding, top padding |
| `xl` | 20pt | Horizontal screen margins, ElevatedCard internal padding |
| `xxl` | 24pt | — |

---

## Corner Radius

| Context | Radius | Style |
|---|---|---|
| Screen-level cards (ElevatedCard) | 24pt | `.continuous` |
| Inline cards (NutritionSummaryCard, time chips) | 14pt | default |
| Small tiles (NutritionTile, MacroBalanceTile) | 12pt | default |
| Search bar | 14pt | default |
| Recipe thumbnails | 8pt | default |
| Tags / pills | Capsule | — |
| Progress bars | 2pt | — |

---

## Elevation & Shadow

| Component | Shadow |
|---|---|
| `ElevatedCard` | `black.opacity(0.35)`, radius 16, y 8 |
| Small tiles (`NutritionTile`) | No shadow — rely on `DividerSubtle` border |
| Sheets / popovers | System default |

---

## Component Library

### NutritionTile
- 12pt corner radius, `SurfaceCard` fill, 1pt `DividerSubtle` border
- 12pt internal padding
- Label: 10pt semibold uppercased `TextSecondary`
- Value: 20pt bold rounded `TextPrimary`
- Unit: 11pt `TextTertiary` at firstTextBaseline
- Optional progress bar: 4pt height, 2pt corner radius

### ElevatedCard
- 24pt continuous corner radius
- `SurfaceCard` fill
- 1pt `DividerSubtle` border
- Shadow: radius 16, y 8, opacity 0.35
- Default 20pt padding (override to 0 for FDA label insets)

### SearchBar
- 14pt corner, `SurfaceCard` fill, 1pt `DividerSubtle` border
- 14pt internal padding
- Leading magnifier icon in `TextSecondary`
- Trailing: ProgressView when searching, xmark.circle.fill when text present

### SegmentedPicker
- `.pickerStyle(.segmented)`
- `.tint(BrandAccent)`

### RecipeRowView (List row)
- Thumbnail: 56×56, rounded 8pt
- Placeholder: gradient + `fork.knife` icon centered in `SurfaceCard` fill (shipped D-3)
- Title: `.headline`
- Metadata: `.caption` in `.secondary`

---

## Empty States

Empty states are features — not fallbacks. Every empty state must have:
1. A recognizable icon (SF Symbol, not generic)
2. A warm, human headline (not "No X found")
3. A brief supportive line
4. A primary action button (not just text)

| Screen | Current | Required |
|---|---|---|
| `MealSection` (no logs) | "No items logged" in tertiary text | **Warm prompt + "+ Add Food" button** |
| `RecipesListView` (empty) | ContentUnavailableView generic | **Improve: add primary import action** |
| `RecipeDetailView` (no photo) | Nearly invisible gray | **Icon placeholder with camera affordance** |
| `RecipeDetailView` (no ingredients) | "No ingredients added yet." plain text | **Icon + action to add first ingredient** |
| `HistoryView` (no logs) | "Log some food to see your trend" — no action button (correct per product philosophy) | ✅ Shipped T-01 |
| `FoodSearchView` (no results) | Unknown — needs check | **"No results for X" + suggest manual entry** |

---

## Image Handling

- **Remote (https://):** `AsyncImage(url:)` — always provide a visible placeholder, not transparent/invisible gray
- **Local (file://):** `AsyncImage(url:)` handles both natively
- **Thumbnail placeholder:** SF Symbol `fork.knife` (recipe) or `photo` centered in `SurfaceCard` background at 24pt `TextTertiary` — NOT `Color.secondary.opacity(0.12)`
- **Hero image placeholder:** Full-width band, `SurfaceCard` fill, centered icon — not nearly-transparent gray

---

## Navigation Patterns

### BiteLedger
- `TabView` root: Today / History / Settings
- Food addition: sheet presentation of `FoodSearchView` with 4-tab segmented picker

### BitePlan
- `TabView` root: Recipes / Meal Planner / Shopping Cart (added v0.2.0.0)
- `NavigationStack` inside each tab
- Toolbar pattern: **gear (Settings) leading, `+` Menu trailing** — D-9 shipped v0.2.0.0

### Toolbar Rule
- Leading: max 1–2 items (prefer icon-only for non-destructive actions)
- Trailing: primary action (`+`, "Edit", "Done")
- Never put 4+ items in leading toolbar — use a menu (`.menu` button style) to consolidate

---

## FDA Label Format

Required for all nutrition display surfaces. See `CLAUDE.md` for the full spec. Design tokens:
- "Nutrition Facts" header: large, bold black text with heavy divider below
- Calories: 32–44pt, black weight, right-aligned value
- Top nutrients: **bold**
- Sub-nutrients: `padding(.leading, 20)`, regular weight
- % DV column: right-aligned
- Dividers: 1pt (`height: 1`) thin, 8pt (`height: 8`) heavy

---

## Interaction States

Every interactive feature must define all 5 states:

| State | Definition |
|---|---|
| Loading | Activity indicator (ProgressView), not blank screen |
| Empty | Warm empty state with icon + primary action (see Empty States table) |
| Error | Inline error message with retry affordance |
| Partial | Partial data visible with indicator (e.g., "some ingredients unmatched") |
| Success | Content displayed; no success toast for read operations |

---

## Accessibility

- Minimum touch target: 44×44pt
- All icons paired with labels or `.accessibilityLabel`
- Color is never the sole differentiator (progress color states also have numeric values)
- Dynamic Type: all text uses `.font()` modifiers (no hardcoded UIFont)
- No reduced-motion animations implemented yet — flag for future

---

## What BitePlan Must Adopt

BitePlan's `Assets.xcassets` currently has only `AccentColor` and `AppIcon`. To align with BiteLedger:

1. **Add all BiteLedger color tokens** to `BitePlan/Assets.xcassets` (or reference them from a shared xcassets)
2. ✅ **Shipped D-6** — `Color.secondary` → `Color("TextSecondary")` applied throughout
3. ✅ **Shipped D-6** — `.accentColor` → `Color("BrandAccent")` applied throughout
4. ✅ **Shipped D-6** — `.regularMaterial` on cards → `Color("SurfaceCard")` applied throughout
5. ✅ **Shipped D-3** — thumbnail placeholder `Color.secondary.opacity(0.12)` → gradient + fork-knife icon

---

## Anti-Patterns (Do Not Repeat)

- `Color.secondary` or `.accentColor` directly — use named tokens
- Nearly-invisible image placeholders (`opacity(0.08)`, `opacity(0.12)`)
- "No items found." as the entire empty state
- 4+ toolbar items in leading position
- Progress bars without a value label (accessibility gap)
- `rescue StandardError` equivalent: silently returning `.zero` nutrition with no UI indicator
