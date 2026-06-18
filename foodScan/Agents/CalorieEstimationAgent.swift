//
//  CalorieEstimationAgent.swift
//  foodScan
//
//  ╔══════════════════════════════════════════════════════════════════════╗
//  ║ AGENT 2 — CALORIE ESTIMATION AGENT                                    ║
//  ╠══════════════════════════════════════════════════════════════════════╣
//  ║ PERAN : Menerjemahkan hasil klasifikasi menjadi estimasi kalori.      ║
//  ║ SKILL : - Lookup kalori dari knowledge base (CalorieDatabase)         ║
//  ║         - Normalisasi nama untuk ditampilkan                          ║
//  ║         - Fallback ke nilai default bila label tak dikenal            ║
//  ║ INPUT : FoodPrediction                                                 ║
//  ║ OUTPUT: CalorieEstimate                                                ║
//  ║ KOLAB : Menerima output Agent 1, hasilnya dikirim ke Agent 3          ║
//  ║         (Persistence) lewat Coordinator.                              ║
//  ╚══════════════════════════════════════════════════════════════════════╝
//
//  TICKET #A2
//   - As: pipeline
//   - I want: label makanan dikonversi ke kalori per porsi
//   - So that: pengguna tahu asupan kalori dari makanan tsb
//   - Acceptance: label tak dikenal tetap menghasilkan estimasi (default),
//     bukan crash.
//

import Foundation

final class CalorieEstimationAgent: Agent {
    let name = "CalorieEstimationAgent"
    let role = "Mengonversi label makanan menjadi estimasi kalori per porsi."
    let skills = [
        "Lookup tabel kalori 101 jenis makanan",
        "Fallback default untuk label tak dikenal",
        "Pembentukan nama tampilan yang rapi"
    ]

    func perform(_ input: FoodPrediction) async throws -> CalorieEstimate {
        let calories = CalorieDatabase.calories(for: input.rawLabel)
        return CalorieEstimate(
            foodLabel: input.rawLabel,
            displayName: input.displayName,
            caloriesPerServing: calories,
            confidence: input.confidence
        )
    }
}
