//
//  VisionFoodAnalysisAgent.swift
//  foodScan
//
//  ╔══════════════════════════════════════════════════════════════════════╗
//  ║ AGENT 1B — VISION FOOD ANALYSIS AGENT (VLM ChatGPT)                    ║
//  ╠══════════════════════════════════════════════════════════════════════╣
//  ║ PERAN : Menganalisis foto makanan langsung dengan VLM (ChatGPT) →     ║
//  ║         nama makanan + kalori + gizi lengkap dalam satu langkah.      ║
//  ║ SKILL : - Mengirim gambar ke OpenAI Vision (multimodal chat)          ║
//  ║         - Menerjemahkan balasan JSON ke VisionFoodAnalysis            ║
//  ║ INPUT : UIImage                                                        ║
//  ║ OUTPUT: VisionFoodAnalysis (isFood, name, calories, protein, dll)     ║
//  ║ KOLAB : Menggantikan jalur Core ML (Agent 1+2+5) bila API key OpenAI  ║
//  ║         tersedia. Bila tidak, Coordinator fallback ke pipeline lama.  ║
//  ╚══════════════════════════════════════════════════════════════════════╝
//
//  TICKET #A7
//   - As: pengguna
//   - I want: cukup memotret makanan dan langsung dapat nama, kalori, gizi,
//     serta SETIAP bahan penyusunnya
//   - So that: pencatatan akurat tanpa perlu mengetik atau menebak porsi
//   - Acceptance: satu panggilan VLM menghasilkan VisionFoodAnalysis lengkap;
//     foto non-makanan ditolak (is_food=false); dipakai hanya bila API key ada.
//

import UIKit

final class VisionFoodAnalysisAgent: Agent {
    let name = "VisionFoodAnalysisAgent"
    let role = "Menganalisis foto makanan dengan VLM ChatGPT menjadi gizi lengkap."
    let skills = [
        "Mengirim gambar ke OpenAI Vision (gpt-4o-mini)",
        "Estimasi kalori, protein, karbo, lemak, serat dari foto",
        "Deteksi apakah gambar memang makanan"
    ]

    private let service: OpenAIService

    init(service: OpenAIService = .shared) {
        self.service = service
    }

    /// `true` bila API key OpenAI sudah diset (menentukan apakah jalur VLM dipakai).
    func isConfigured() async -> Bool {
        await service.isConfigured
    }

    func perform(_ input: UIImage) async throws -> VisionFoodAnalysis {
        try await service.analyzeFood(image: input)
    }
}
