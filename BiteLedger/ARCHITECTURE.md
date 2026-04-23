# BiteLedger Architecture Rules

## Nutrition Storage
- FoodItem has `nutritionMode: NutritionMode` enum (.per100g or .perServing)
- Per100g foods: USDA, OpenFoodFacts, packaged foods with known gram weights
- PerServing foods: manual entry, recipes, FatSecret no-gram items, LoseIt imports
- 100g is NEVER shown to users. It is internal storage only.

## ServingSize
- Stores: label (String), gramWeight (Double?), isDefault (Bool)
- NO multipliers. NO math logic. NO baseServingDescription on FoodItem.
- gramWeight is nil for dimensionless foods (sandwich, slice, serving)

## FoodLog
- Nutrition is FROZEN at log time (caloriesAtLogTime, proteinAtLogTime, etc.)
- Editing a FoodItem never rewrites log history

## Nutrition Math
- Lives ONLY in NutritionCalculator.swift
- Zero math in views, pickers, or models
- per100g: (gramWeight / 100) × nutritionPer100g × quantity
- perServing: nutritionPerServing × quantity

## CSV
- Must support LoseIt import format
- Must support full round-trip export/import with zero data loss

## Backup & Restore (BackupService)
- `BackupService` lives in `BiteLedgerCore` — shared by both apps
- `createBackup` produces a single `.zip`: manifest.json + 8 CSVs + recipe images
  (foods, servings, logs, recipes, ingredients, meal_plans, meal_meals, meal_items — SchemaV5)
- `restoreBackup` supports `.replaceAll` (wipe then import) and `.merge` (UUID-based skip)
- `resetDatabase` supports 4 scopes: logsOnly / allFoodData / recipesOnly / everything
- ZIP entry paths are validated against extract directory (no path traversal)

## Nutrient Spotlight (NutrientSpotlightEngine)
- Pure struct in `BiteLedgerCore` — no SwiftData dependency, fully unit-testable
- Operates on pre-fetched `[FoodLog]` — caller owns the 7-day window filter
- 5 spotlight nutrients (high-side only, v1): sodium, saturatedFat, fat, cholesterol, carbs
- Threshold: `nutrient.defaultGoalValue × dvMultiplier` (default 1.2 = 120% DV)
- Qualifies if a nutrient exceeds threshold on ≥ `minDaysAbove` days (default 3 of 7)
- Parameters are injectable — no schema fields, no user preferences
- `Nutrient.value(from: FoodLog) -> Double?` maps each nutrient to its `*AtLogTime` field