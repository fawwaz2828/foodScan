//
//  FoodModels.swift
//  foodScan
//
//  Model data inti yang dipakai lintas-Agent.
//  Semua tipe di sini bersifat `Codable` & `Sendable` agar mudah:
//   - dikirim antar-Agent lewat protocol/delegate
//   - disimpan oleh Persistence Agent (ke JSON / UserDefaults)
//

import Foundation

// MARK: - Hasil klasifikasi gambar (output Image Recognition Agent)

/// Hasil mentah dari klasifikasi Core ML.
/// Diproduksi oleh `ImageRecognitionAgent`, dikonsumsi oleh `CalorieEstimationAgent`.
struct FoodPrediction: Codable, Equatable {
    /// Label kelas mentah dari model Food101, contoh: "apple_pie".
    let rawLabel: String
    /// Tingkat keyakinan model 0.0 – 1.0.
    let confidence: Double

    /// Label yang sudah dirapikan untuk ditampilkan ke pengguna, contoh: "Apple Pie".
    var displayName: String {
        rawLabel
            .split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

// MARK: - Estimasi kalori (output Calorie Estimation Agent)

/// Hasil estimasi kalori untuk satu makanan.
/// Diproduksi oleh `CalorieEstimationAgent`.
struct CalorieEstimate: Codable, Equatable {
    let foodLabel: String          // raw label, mis. "pizza"
    let displayName: String        // "Pizza"
    let caloriesPerServing: Int    // kkal per porsi
    let confidence: Double         // diteruskan dari FoodPrediction
}

// MARK: - Catatan riwayat scan (dikelola Persistence Agent)

/// Satu entri riwayat yang disimpan secara persisten.
struct ScanRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let foodLabel: String
    let displayName: String
    let calories: Int
    let confidence: Double
    let date: Date
    /// Path file gambar (opsional) yang disimpan di Documents directory.
    let imageFileName: String?
    /// Rasio porsi relatif (1.0 = satu porsi standar). Diisi Portion Hint / Voice.
    let portionRatio: Double?
    /// Rincian gizi dari NutritionFactAgent (diisi setelah enrichment Groq).
    let nutrition: NutritionalInfo?
    /// Waktu makan yang di-set manual (opsional). Bila nil, diturunkan dari `date`.
    let mealTimeRaw: String?

    /// Waktu makan efektif: override manual bila ada, jika tidak dari jam `date`.
    var mealTime: MealTime {
        mealTimeRaw.flatMap(MealTime.init(rawValue:)) ?? MealTime.from(date)
    }

    init(
        id: UUID = UUID(),
        foodLabel: String,
        displayName: String,
        calories: Int,
        confidence: Double,
        date: Date = Date(),
        imageFileName: String? = nil,
        portionRatio: Double? = 1.0,
        nutrition: NutritionalInfo? = nil,
        mealTimeRaw: String? = nil
    ) {
        self.id = id
        self.foodLabel = foodLabel
        self.displayName = displayName
        self.calories = calories
        self.confidence = confidence
        self.date = date
        self.imageFileName = imageFileName
        self.portionRatio = portionRatio
        self.nutrition = nutrition
        self.mealTimeRaw = mealTimeRaw
    }

    /// Membuat salinan dengan sebagian field diubah (struct field `let`).
    /// Dipakai Voice Correction & enrichment gizi untuk memperbarui record.
    func applying(
        displayName: String? = nil,
        calories: Int? = nil,
        portionRatio: Double? = nil,
        nutrition: NutritionalInfo? = nil,
        mealTime: MealTime? = nil
    ) -> ScanRecord {
        ScanRecord(
            id: id,
            foodLabel: foodLabel,
            displayName: displayName ?? self.displayName,
            calories: calories ?? self.calories,
            confidence: confidence,
            date: date,
            imageFileName: imageFileName,
            portionRatio: portionRatio ?? self.portionRatio,
            nutrition: nutrition ?? self.nutrition,
            mealTimeRaw: mealTime?.rawValue ?? self.mealTimeRaw
        )
    }
}

// MARK: - Rekomendasi (output Recommendation Agent)

enum CalorieStatus: String, Codable {
    case low        // di bawah target
    case onTrack    // dalam rentang sehat
    case high       // melebihi target harian
}

/// Saran harian berbasis total kalori.
/// Diproduksi oleh `RecommendationAgent`.
struct DailyRecommendation: Codable, Equatable {
    let totalCaloriesToday: Int
    let dailyTarget: Int
    let status: CalorieStatus
    let message: String
}

// MARK: - Error lintas-Agent

enum FoodScanError: LocalizedError, Equatable {
    case modelNotFound
    case classificationFailed(String)
    case invalidImage
    case persistenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "The Food101.mlmodel hasn't been added to the project. Using demo mode."
        case .classificationFailed(let reason):
            return "Classification failed: \(reason)"
        case .invalidImage:
            return "Invalid image."
        case .persistenceFailed(let reason):
            return "Saving failed: \(reason)"
        }
    }
}
