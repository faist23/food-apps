//
//  NutritionFacts.swift
//  BiteLedger
//
//  Created by Craig Faist on 2/16/26.
//


import Foundation

public struct NutritionFacts: Codable {
    public var caloriesPer100g: Double
    public var proteinPer100g: Double
    public var carbsPer100g: Double
    public var fatPer100g: Double
    public var fiberPer100g: Double?
    public var sugarPer100g: Double?
    public var sodiumPer100g: Double?
    public var saturatedFatPer100g: Double?
    public var transFatPer100g: Double?
    public var monounsaturatedFatPer100g: Double?
    public var polyunsaturatedFatPer100g: Double?
    public var cholesterolPer100g: Double?
    
    // Additional minerals
    public var magnesiumPer100g: Double?
    public var zincPer100g: Double?
    
    // Vitamins
    public var vitaminAPer100g: Double?
    public var vitaminCPer100g: Double?
    public var vitaminDPer100g: Double?
    public var vitaminEPer100g: Double?
    public var vitaminKPer100g: Double?
    public var vitaminB6Per100g: Double?
    public var vitaminB12Per100g: Double?
    public var folatePer100g: Double?
    public var cholinePer100g: Double?
    
    // Minerals
    public var calciumPer100g: Double?
    public var ironPer100g: Double?
    public var potassiumPer100g: Double?
    
    // Special tracking
    public var caffeinePer100g: Double?

    public init(
        caloriesPer100g: Double, proteinPer100g: Double, carbsPer100g: Double, fatPer100g: Double,
        fiberPer100g: Double? = nil, sugarPer100g: Double? = nil,
        sodiumPer100g: Double? = nil, saturatedFatPer100g: Double? = nil,
        transFatPer100g: Double? = nil, monounsaturatedFatPer100g: Double? = nil,
        polyunsaturatedFatPer100g: Double? = nil, cholesterolPer100g: Double? = nil,
        magnesiumPer100g: Double? = nil, zincPer100g: Double? = nil,
        vitaminAPer100g: Double? = nil, vitaminCPer100g: Double? = nil,
        vitaminDPer100g: Double? = nil, vitaminEPer100g: Double? = nil,
        vitaminKPer100g: Double? = nil, vitaminB6Per100g: Double? = nil,
        vitaminB12Per100g: Double? = nil, folatePer100g: Double? = nil,
        cholinePer100g: Double? = nil, calciumPer100g: Double? = nil,
        ironPer100g: Double? = nil, potassiumPer100g: Double? = nil,
        caffeinePer100g: Double? = nil
    ) {
        self.caloriesPer100g = caloriesPer100g; self.proteinPer100g = proteinPer100g
        self.carbsPer100g = carbsPer100g; self.fatPer100g = fatPer100g
        self.fiberPer100g = fiberPer100g; self.sugarPer100g = sugarPer100g
        self.sodiumPer100g = sodiumPer100g; self.saturatedFatPer100g = saturatedFatPer100g
        self.transFatPer100g = transFatPer100g
        self.monounsaturatedFatPer100g = monounsaturatedFatPer100g
        self.polyunsaturatedFatPer100g = polyunsaturatedFatPer100g
        self.cholesterolPer100g = cholesterolPer100g
        self.magnesiumPer100g = magnesiumPer100g; self.zincPer100g = zincPer100g
        self.vitaminAPer100g = vitaminAPer100g; self.vitaminCPer100g = vitaminCPer100g
        self.vitaminDPer100g = vitaminDPer100g; self.vitaminEPer100g = vitaminEPer100g
        self.vitaminKPer100g = vitaminKPer100g; self.vitaminB6Per100g = vitaminB6Per100g
        self.vitaminB12Per100g = vitaminB12Per100g; self.folatePer100g = folatePer100g
        self.cholinePer100g = cholinePer100g; self.calciumPer100g = calciumPer100g
        self.ironPer100g = ironPer100g; self.potassiumPer100g = potassiumPer100g
        self.caffeinePer100g = caffeinePer100g
    }
}