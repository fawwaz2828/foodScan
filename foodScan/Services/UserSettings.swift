//
//  UserSettings.swift
//  foodScan
//
//  Preferensi & profil pengguna (gaya Cal AI), persisten di UserDefaults.
//  Menyimpan data profil (umur, tinggi, berat, jenis kelamin, aktivitas, goal),
//  lalu menurunkan target kalori & macro otomatis lewat GoalCalculator.
//

import SwiftUI

@MainActor
final class UserSettings: ObservableObject {

    private let defaults: UserDefaults

    private enum Keys {
        static let userName = "settings.userName"
        static let age = "settings.age"
        static let heightCm = "settings.heightCm"
        static let weightKg = "settings.weightKg"
        static let sex = "settings.sex"
        static let activity = "settings.activity"
        static let goal = "settings.goal"
        static let dailyCalorieTarget = "settings.dailyCalorieTarget"
        static let notificationsEnabled = "settings.notificationsEnabled"
        static let onboardingCompleted = "settings.onboardingCompleted"
        static let openAIKey = "settings.openAIKey"
        static let reduceAIUsage = "settings.reduceAIUsage"
    }

    /// Kunci UserDefaults yang dibaca langsung oleh service (di luar @MainActor).
    enum SharedKeys {
        static let openAIKey = "settings.openAIKey"
        static let reduceAIUsage = "settings.reduceAIUsage"
    }

    // MARK: Identitas & profil

    @Published var userName: String { didSet { defaults.set(userName, forKey: Keys.userName) } }
    @Published var age: Int { didSet { defaults.set(age, forKey: Keys.age) } }
    @Published var heightCm: Double { didSet { defaults.set(heightCm, forKey: Keys.heightCm) } }
    @Published var weightKg: Double { didSet { defaults.set(weightKg, forKey: Keys.weightKg) } }
    @Published var sex: BiologicalSex { didSet { defaults.set(sex.rawValue, forKey: Keys.sex) } }
    @Published var activity: ActivityLevel { didSet { defaults.set(activity.rawValue, forKey: Keys.activity) } }
    @Published var goal: WeightGoal { didSet { defaults.set(goal.rawValue, forKey: Keys.goal) } }

    /// Target kalori harian (otomatis dari profil, bisa di-override manual).
    @Published var dailyCalorieTarget: Int { didSet { defaults.set(dailyCalorieTarget, forKey: Keys.dailyCalorieTarget) } }
    @Published var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled) } }
    @Published var onboardingCompleted: Bool { didSet { defaults.set(onboardingCompleted, forKey: Keys.onboardingCompleted) } }

    /// API key OpenAI yang diisi pengguna (override key bawaan). Kosong = pakai default.
    @Published var openAIKey: String { didSet { defaults.set(openAIKey, forKey: Keys.openAIKey) } }
    /// Bila true, lewati panggilan AI proaktif (What-If & portion) demi hemat biaya.
    @Published var reduceAIUsage: Bool { didSet { defaults.set(reduceAIUsage, forKey: Keys.reduceAIUsage) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.age: 25,
            Keys.heightCm: 170.0,
            Keys.weightKg: 62.0,
            Keys.dailyCalorieTarget: 2000,
            Keys.notificationsEnabled: true
        ])

        userName = defaults.string(forKey: Keys.userName) ?? "FoodScan User"
        age = defaults.integer(forKey: Keys.age)
        heightCm = defaults.double(forKey: Keys.heightCm)
        weightKg = defaults.double(forKey: Keys.weightKg)
        sex = BiologicalSex(rawValue: defaults.string(forKey: Keys.sex) ?? "") ?? .male
        activity = ActivityLevel(rawValue: defaults.string(forKey: Keys.activity) ?? "") ?? .light
        goal = WeightGoal(rawValue: defaults.string(forKey: Keys.goal) ?? "") ?? .maintain
        dailyCalorieTarget = defaults.integer(forKey: Keys.dailyCalorieTarget)
        notificationsEnabled = defaults.bool(forKey: Keys.notificationsEnabled)
        onboardingCompleted = defaults.bool(forKey: Keys.onboardingCompleted)
        openAIKey = defaults.string(forKey: Keys.openAIKey) ?? ""
        reduceAIUsage = defaults.bool(forKey: Keys.reduceAIUsage)
    }

    // MARK: Target macro (gram) — turunan dari kalori, berat, goal

    private var macroSplit: (protein: Int, carbs: Int, fat: Int) {
        GoalCalculator.macros(calories: dailyCalorieTarget, weightKg: weightKg, goal: goal)
    }
    var proteinTarget: Int { macroSplit.protein }
    var carbsTarget: Int { macroSplit.carbs }
    var fatTarget: Int { macroSplit.fat }

    /// Hitung ulang target kalori dari profil saat ini (dipanggil saat onboarding
    /// selesai atau profil diubah).
    func recomputeTargets() {
        dailyCalorieTarget = GoalCalculator.dailyCalories(
            sex: sex, weightKg: weightKg, heightCm: heightCm,
            age: age, activity: activity, goal: goal
        )
    }

    /// Pratinjau target tanpa menyimpan (untuk layar onboarding).
    var previewCalorieTarget: Int {
        GoalCalculator.dailyCalories(
            sex: sex, weightKg: weightKg, heightCm: heightCm,
            age: age, activity: activity, goal: goal
        )
    }
}
