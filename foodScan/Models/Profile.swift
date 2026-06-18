//
//  Profile.swift
//  foodScan
//
//  Model profil pengguna + kalkulator target kalori/macro (gaya Cal AI).
//  Memakai rumus Mifflin-St Jeor untuk BMR, dikalikan faktor aktivitas (TDEE),
//  lalu disesuaikan dengan goal (turun/jaga/naik berat).
//

import Foundation

// MARK: - Komponen profil

enum BiologicalSex: String, CaseIterable, Identifiable {
    case male, female
    var id: String { rawValue }
    var label: String { self == .male ? "Male" : "Female" }
}

enum ActivityLevel: String, CaseIterable, Identifiable {
    case sedentary, light, moderate, active, veryActive
    var id: String { rawValue }

    var factor: Double {
        switch self {
        case .sedentary:  return 1.2
        case .light:      return 1.375
        case .moderate:   return 1.55
        case .active:     return 1.725
        case .veryActive: return 1.9
        }
    }

    var label: String {
        switch self {
        case .sedentary:  return "Rarely exercise"
        case .light:      return "Light (1–3x/week)"
        case .moderate:   return "Moderate (3–5x/week)"
        case .active:     return "Active (6–7x/week)"
        case .veryActive: return "Very active"
        }
    }
}

enum WeightGoal: String, CaseIterable, Identifiable {
    case lose, maintain, gain
    var id: String { rawValue }

    /// Penyesuaian kalori harian terhadap TDEE.
    var calorieDelta: Int {
        switch self {
        case .lose:     return -500
        case .maintain: return 0
        case .gain:     return 400
        }
    }

    /// Protein per kg berat badan (gram) sesuai goal.
    var proteinPerKg: Double {
        switch self {
        case .lose:     return 2.0
        case .maintain: return 1.8
        case .gain:     return 1.6
        }
    }

    var label: String {
        switch self {
        case .lose:     return "Lose weight"
        case .maintain: return "Maintain weight"
        case .gain:     return "Gain weight"
        }
    }
}

// MARK: - Kalkulator target

enum GoalCalculator {

    /// BMR (kkal/hari) — Mifflin-St Jeor.
    static func bmr(sex: BiologicalSex, weightKg: Double, heightCm: Double, age: Int) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        return sex == .male ? base + 5 : base - 161
    }

    /// Target kalori harian = TDEE ± penyesuaian goal.
    static func dailyCalories(sex: BiologicalSex, weightKg: Double, heightCm: Double,
                              age: Int, activity: ActivityLevel, goal: WeightGoal) -> Int {
        let tdee = bmr(sex: sex, weightKg: weightKg, heightCm: heightCm, age: age) * activity.factor
        let result = Int(tdee.rounded()) + goal.calorieDelta
        return max(1200, result) // jaga batas aman minimum
    }

    /// Pecahan macro (gram): protein dari berat badan, lemak 25% kkal, sisanya karbo.
    static func macros(calories: Int, weightKg: Double, goal: WeightGoal) -> (protein: Int, carbs: Int, fat: Int) {
        let protein = Int((weightKg * goal.proteinPerKg).rounded())
        let fat = Int((Double(calories) * 0.25 / 9).rounded())
        let remaining = calories - protein * 4 - fat * 9
        let carbs = max(0, Int((Double(remaining) / 4).rounded()))
        return (protein, carbs, fat)
    }
}

// MARK: - Waktu makan

enum MealTime: String, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch:     return "Lunch"
        case .dinner:    return "Dinner"
        case .snack:     return "Snack"
        }
    }

    var icon: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch:     return "sun.max.fill"
        case .dinner:    return "moon.fill"
        case .snack:     return "takeoutbag.and.cup.and.straw.fill"
        }
    }

    /// Slot waktu makan berdasarkan jam catatan.
    static func from(_ date: Date) -> MealTime {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11:  return .breakfast
        case 11..<16: return .lunch
        case 16..<21: return .dinner
        default:      return .snack
        }
    }
}
