//
//  NutritionFactAgent.swift
//  foodScan
//
//  ╔══════════════════════════════════════════════════════════════════════╗
//  ║ AGENT 5 — NUTRITION FACT AGENT (RAG via ChatGPT)                       ║
//  ╠══════════════════════════════════════════════════════════════════════╣
//  ║ PERAN : Memperkaya hasil scan dengan rincian gizi + skor kesehatan.   ║
//  ║ SKILL : - Memanggil ChatGPT (LLM) untuk protein/karbo/lemak/serat     ║
//  ║         - Menghasilkan health_score (1-10) + insight singkat          ║
//  ║         - Memetakan skor ke HealthCategory (haptic & warna overlay)   ║
//  ║ INPUT : NutritionInput (nama makanan, kalori, rasio porsi)            ║
//  ║ OUTPUT: NutritionalInfo                                                ║
//  ║ KOLAB : Dipanggil setelah Agent 1-3; output dipakai UI Intelligence.  ║
//  ╚══════════════════════════════════════════════════════════════════════╝
//
//  TICKET #A5
//   - As: pengguna
//   - I want: tahu rincian gizi (protein/karbo/lemak/serat) & skor sehat
//   - So that: saya bisa menilai kualitas makanan, bukan cuma kalorinya
//   - Acceptance: makro & health_score (1-10) ditampilkan; gagal diam-diam
//     bila API key belum diset (tidak menghentikan pipeline inti).
//

import Foundation

struct NutritionInput {
    let foodName: String
    let calories: Int
    let portionRatio: Double
}

final class NutritionFactAgent: Agent {
    let name = "NutritionFactAgent"
    let role = "Mengambil rincian gizi & skor kesehatan via ChatGPT (OpenAI)."
    let skills = [
        "Query ChatGPT untuk makronutrien (protein/karbo/lemak/serat)",
        "Menentukan health score 1-10 + insight",
        "Memetakan skor ke kategori haptic & warna"
    ]

    private let ai: OpenAIService
    init(ai: OpenAIService = .shared) { self.ai = ai }

    func perform(_ input: NutritionInput) async throws -> NutritionalInfo {
        try await ai.requestNutrition(
            foodName: input.foodName,
            calories: input.calories,
            portionRatio: input.portionRatio
        )
    }
}
