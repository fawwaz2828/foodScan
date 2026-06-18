//
//  Agent.swift
//  foodScan
//
//  ============================================================================
//  KONSEP AI AGENT DALAM APLIKASI INI
//  ============================================================================
//  Aplikasi mengadopsi arsitektur *multi-agent*: tiap Agent adalah unit mandiri
//  dengan SATU tanggung jawab (Single Responsibility), memiliki sekumpulan
//  "skill", dan berkomunikasi dengan Agent lain HANYA lewat protocol/delegate —
//  tidak saling mengakses isi internal. Orkestrasi dilakukan oleh
//  `AgentCoordinator` yang merangkai output satu Agent menjadi input Agent
//  berikutnya (pola pipeline / chain-of-responsibility).
//
//  DAFTAR AGENT (7 agent + tools bersama)
//  ----------------------------------------------------------------------------
//  Agent 1  — ImageRecognitionAgent     : UIImage -> FoodPrediction (Core ML)
//  Agent 2  — CalorieEstimationAgent    : FoodPrediction -> CalorieEstimate
//  Agent 3  — PersistenceAgent          : Estimate/Record -> ScanRecord (saved)
//  Agent 4  — RecommendationAgent       : [ScanRecord] -> DailyRecommendation
//  Agent 5  — NutritionFactAgent        : NutritionInput -> NutritionalInfo
//  Agent 6  — EnhancedRecommendationAgent: [ScanRecord] -> PersonalAdvice/WhatIf
//  Agent 7  — VisionFoodAnalysisAgent   : UIImage -> VisionFoodAnalysis (VLM)
//
//  TOOLS BERSAMA (dipakai agent, bukan Agent itu sendiri):
//   - OpenAIService  : klien ChatGPT (vision + teks, JSON mode) untuk Agent 5/6/7
//   - FoodGateService: gerbang Core ML on-device "makanan / bukan" (hemat biaya)
//
//  ALUR KOLABORASI (SEQUENCE) — jalur utama: VLM ChatGPT
//  ----------------------------------------------------------------------------
//   User ── ambil/pilih foto ──▶ ScanViewModel.scan()
//     │
//     ├─▶ FoodGateService  (Core ML)  ── bukan makanan? ──▶ tolak (hemat API)
//     │
//     ▼  makanan
//   AgentCoordinator.runWithVision(image:)
//     │ 1. Agent 7  VisionFoodAnalysisAgent ─▶ VisionFoodAnalysis (nama,kalori,
//     │                                         gizi, SETIAP bahan)
//     │ 2. Agent 3  PersistenceAgent        ─▶ ScanRecord (saved, + nutrition)
//     │ 3. Agent 4  RecommendationAgent     ─▶ DailyRecommendation
//     ▼
//   ScanViewModel.enrich()  (proaktif, bisa dimatikan via "Reduce AI usage")
//     │ Agent 6  EnhancedRecommendationAgent ─▶ What-If (2 swap)
//     │ + portion hint (OpenAIService)        ─▶ PortionHint
//     ▼
//   ViewModel (UI di-update)
//
//  FALLBACK (tanpa API key) — jalur Core ML klasik:
//   AgentCoordinator.run(image:)
//     Agent 1 (Recognition) ─▶ Agent 2 (Estimation) ─▶ Agent 3 (Persistence)
//     ─▶ Agent 5 (Nutrition, via ChatGPT) ─▶ Agent 4 (Recommendation)
//
//  Setiap langkah melaporkan progres lewat `AgentEventDelegate` sehingga UI
//  bisa menampilkan status ("Recognizing food...", "Estimating calories...").
//  ============================================================================
//

import Foundation

// MARK: - Protocol dasar untuk semua Agent

/// Kontrak generik tiap Agent: punya identitas, peran, skill, dan satu
/// operasi `perform(input:)` yang mentransformasi Input -> Output.
protocol Agent {
    associatedtype Input
    associatedtype Output

    /// Nama Agent (untuk logging & dokumentasi).
    var name: String { get }
    /// Deskripsi peran/tanggung jawab Agent.
    var role: String { get }
    /// Daftar "skill" / kemampuan yang dimiliki Agent.
    var skills: [String] { get }

    /// Tugas inti Agent. Bersifat async karena sebagian Agent melakukan
    /// pekerjaan berat (inferensi ML, I/O disk).
    func perform(_ input: Input) async throws -> Output
}

// MARK: - Komunikasi antar-Agent (delegate / event bus)

/// Tahapan pipeline, dipakai untuk melaporkan progres ke UI.
enum AgentStage: String {
    case recognition = "Recognizing food"
    case estimation  = "Estimating calories"
    case persistence = "Saving history"
    case recommendation = "Building recommendation"
}

/// Protocol komunikasi: Coordinator memberi tahu observer (ViewModel)
/// setiap kali sebuah Agent mulai/selesai bekerja. Ini wujud "kolaborasi
/// lewat delegate" yang diminta pada spesifikasi.
protocol AgentEventDelegate: AnyObject {
    func agentDidStart(stage: AgentStage)
    func agentDidFinish(stage: AgentStage, detail: String)
    func agentDidFail(stage: AgentStage, error: Error)
}

/// Implementasi delegate opsional agar tidak wajib mengisi semua method.
extension AgentEventDelegate {
    func agentDidStart(stage: AgentStage) {}
    func agentDidFinish(stage: AgentStage, detail: String) {}
    func agentDidFail(stage: AgentStage, error: Error) {}
}
