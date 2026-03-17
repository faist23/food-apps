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
```

**Step 2: Start every Claude Code session with this prompt**
```
Before writing any code, read the in the project root. 
All models, logic, and views must comply with those rules. 
If you're about to do something that conflicts, stop and tell me first.
```

**Step 3: When Claude drifts** (and it will), redirect it:
```
That conflicts with ARCHITECTURE.md — we don't store multipliers. 
Rewrite using the centralized NutritionCalculator approach.
