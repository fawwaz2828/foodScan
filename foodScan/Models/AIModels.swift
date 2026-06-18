//
//  AIModels.swift
//  foodScan
//
//  Struktur data untuk fitur berbasis VLM/LLM ChatGPT (OpenAI).
//  Semua Codable + `convertFromSnakeCase` agar cocok dengan JSON keluaran model
//  (mis. `protein_gram` -> `proteinGram`).
//

import Foundation

// MARK: - Bahan/komponen makanan (output deteksi VLM)

/// Satu bahan/komponen yang terdeteksi pada makanan (mis. "Nasi putih",
/// "Ayam goreng", "Telur", "Sambal"). Dipakai untuk menampilkan rincian
/// penyusun makanan beserta perkiraan berat & kalorinya.
struct FoodIngredient: Codable, Equatable, Identifiable {
    var id = UUID()
    let name: String
    let estimatedGrams: Double   // perkiraan berat bahan (gram)
    let calories: Int            // perkiraan kalori bahan tsb

    // `id` tidak ada di JSON model → dikecualikan dari decoding.
    private enum CodingKeys: String, CodingKey {
        case name, estimatedGrams, calories
    }

    init(id: UUID = UUID(), name: String, estimatedGrams: Double, calories: Int) {
        self.id = id; self.name = name; self.estimatedGrams = estimatedGrams; self.calories = calories
    }

    // Toleran: angka boleh integer/desimal; field hilang → default aman.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        estimatedGrams = (try? c.decode(Double.self, forKey: .estimatedGrams)) ?? 0
        calories = Int((try? c.decode(Double.self, forKey: .calories)) ?? 0)
    }
}

// MARK: - Nutrisi (output NutritionFactAgent)

/// Rincian gizi + skor kesehatan dari LLM, plus daftar bahan (bila tersedia).
struct NutritionalInfo: Codable, Equatable {
    let proteinGram: Double
    let carbsGram: Double
    let fatGram: Double
    let fiberGram: Double
    let healthScore: Double      // 1.0 – 10.0
    let insight: String
    /// Bahan/komponen yang terdeteksi (opsional — hanya dari analisis foto VLM).
    let ingredients: [FoodIngredient]?

    init(proteinGram: Double, carbsGram: Double, fatGram: Double, fiberGram: Double,
         healthScore: Double, insight: String, ingredients: [FoodIngredient]? = nil) {
        self.proteinGram = proteinGram
        self.carbsGram = carbsGram
        self.fatGram = fatGram
        self.fiberGram = fiberGram
        self.healthScore = healthScore
        self.insight = insight
        self.ingredients = ingredients
    }
}

// MARK: - Estimasi makanan manual/teks (output requestManualEstimate)

struct ManualFoodEstimate: Codable, Equatable {
    let name: String
    let calories: Int
    let proteinGram: Double
    let carbsGram: Double
    let fatGram: Double
    let fiberGram: Double
    let healthScore: Double
    let insight: String
    let ingredients: [FoodIngredient]?

    var nutrition: NutritionalInfo {
        NutritionalInfo(
            proteinGram: proteinGram, carbsGram: carbsGram,
            fatGram: fatGram, fiberGram: fiberGram,
            healthScore: healthScore, insight: insight, ingredients: ingredients
        )
    }
}

// MARK: - Analisis foto via VLM ChatGPT (output OpenAIService.analyzeFood)

/// Hasil analisis satu foto makanan langsung dari VLM (gambar → gizi + bahan).
struct VisionFoodAnalysis: Codable, Equatable {
    let isFood: Bool
    let name: String
    let calories: Int
    let proteinGram: Double
    let carbsGram: Double
    let fatGram: Double
    let fiberGram: Double
    let healthScore: Double      // 1.0 – 10.0
    let confidence: Double       // 0.0 – 1.0
    let insight: String
    /// Setiap bahan/komponen yang terlihat pada makanan.
    let ingredients: [FoodIngredient]

    enum CodingKeys: String, CodingKey {
        case isFood, name, calories, proteinGram, carbsGram, fatGram,
             fiberGram, healthScore, confidence, insight, ingredients
    }

    // Toleran terhadap field hilang / angka desimal agar scan tidak gagal
    // hanya karena balasan LLM sedikit menyimpang dari skema.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isFood = (try? c.decode(Bool.self, forKey: .isFood)) ?? true
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        calories = Int((try? c.decode(Double.self, forKey: .calories)) ?? 0)
        proteinGram = (try? c.decode(Double.self, forKey: .proteinGram)) ?? 0
        carbsGram = (try? c.decode(Double.self, forKey: .carbsGram)) ?? 0
        fatGram = (try? c.decode(Double.self, forKey: .fatGram)) ?? 0
        fiberGram = (try? c.decode(Double.self, forKey: .fiberGram)) ?? 0
        healthScore = (try? c.decode(Double.self, forKey: .healthScore)) ?? 5
        confidence = (try? c.decode(Double.self, forKey: .confidence)) ?? 0.8
        insight = (try? c.decode(String.self, forKey: .insight)) ?? ""
        ingredients = (try? c.decode([FoodIngredient].self, forKey: .ingredients)) ?? []
    }

    /// Konversi ke gizi internal yang dipakai layar detail & enrichment.
    var nutrition: NutritionalInfo {
        NutritionalInfo(
            proteinGram: proteinGram, carbsGram: carbsGram,
            fatGram: fatGram, fiberGram: fiberGram,
            healthScore: healthScore, insight: insight, ingredients: ingredients
        )
    }
}

// MARK: - Resep yang di-generate dari makanan hasil scan (output requestRecipe)

/// Resep lengkap untuk memasak ulang makanan yang dipindai.
struct GeneratedRecipe: Codable, Equatable {
    let title: String
    let servings: Int
    let totalTimeMinutes: Int
    /// Daftar bahan + takaran, mis. "2 eggs", "200 g rice".
    let ingredients: [String]
    /// Langkah memasak berurutan.
    let steps: [String]
    /// Tip singkat opsional.
    let tips: String?
}

// MARK: - Rekomendasi personal (output EnhancedRecommendationAgent)

struct PersonalAdvice: Codable, Equatable {
    let advice: String           // saran personal berbasis pola 7 hari
    let simulation: String?      // simulasi "what if ..." opsional
}

// MARK: - What-If swap (output requestWhatIf)

/// Satu alternatif tukar makanan untuk menghemat kalori.
struct WhatIfAlternative: Codable, Equatable, Identifiable {
    var id = UUID()
    let swapFrom: String
    let swapTo: String
    let calorieSaved: Int
    let reason: String

    // `id` tidak ada di JSON Groq -> dikecualikan dari decoding.
    private enum CodingKeys: String, CodingKey {
        case swapFrom, swapTo, calorieSaved, reason
    }
}

// MARK: - Voice correction (output requestVoiceCorrection)

struct VoiceCorrectionResult: Codable, Equatable {
    let action: String           // "update" | "none"
    let correctedFoodName: String?
    let portionRatio: Double?
    let newCalories: Int?
}

// MARK: - Portion hint (output requestPortionHint)

struct PortionHint: Codable, Equatable {
    let estimatedPortion: Double // 0.5 | 1.0 | 1.5 | 2.0
    let suggestion: String
}

// MARK: - Food chat

/// Satu bubble pesan pada chatbot makanan.
struct FoodChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    let text: String

    enum Role: Equatable {
        case user
        case assistant
    }
}
