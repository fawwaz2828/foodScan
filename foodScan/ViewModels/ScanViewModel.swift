//
//  ScanViewModel.swift
//  foodScan
//
//  Penghubung UI ↔ Agent. Selain pipeline inti (Agent 1-4), kini juga
//  mengorkestrasi fitur Groq: enrichment gizi, What-If, voice correction,
//  portion hint, haptic & notifikasi.
//

import SwiftUI

@MainActor
final class ScanViewModel: ObservableObject {

    // Pipeline inti
    @Published var selectedImage: UIImage?
    @Published var isProcessing = false
    @Published var statusText = "Pick or take a food photo"
    @Published var result: ScanPipelineResult?
    @Published var errorMessage: String?

    // Fitur AI (Groq)
    @Published var nutrition: NutritionalInfo?
    @Published var healthCategory: HealthCategory?
    @Published var whatIfAlternatives: [WhatIfAlternative] = []
    @Published var portionHint: PortionHint?
    @Published var isEnriching = false
    @Published var aiError: String?
    @Published var chatMessages: [FoodChatMessage] = []
    @Published var isAskingAI = false
    @Published var recipe: GeneratedRecipe?
    @Published var isGeneratingRecipe = false

    private let coordinator: AgentCoordinator
    private let nutritionAgent: NutritionFactAgent
    private let enhancedRec: EnhancedRecommendationAgent
    private let ai: OpenAIService

    init(coordinator: AgentCoordinator,
         nutritionAgent: NutritionFactAgent = NutritionFactAgent(),
         enhancedRec: EnhancedRecommendationAgent = EnhancedRecommendationAgent(),
         ai: OpenAIService = .shared) {
        self.coordinator = coordinator
        self.nutritionAgent = nutritionAgent
        self.enhancedRec = enhancedRec
        self.ai = ai
        self.coordinator.delegate = self
    }

    // MARK: - Pipeline inti + enrichment AI

    func scan() async {
        guard let image = selectedImage else { errorMessage = "No image yet."; return }
        isProcessing = true
        errorMessage = nil
        resetAIState()

        // Food gate on-device: tolak foto non-makanan sebelum panggil ChatGPT
        // (hemat biaya API). Konservatif — hanya blokir bila model SANGAT yakin
        // ini bukan makanan; selebihnya biarkan VLM (punya cek is_food sendiri).
        // Bila model tak tersedia, evaluate() -> nil = lolos.
        statusText = "Checking photo…"
        if let verdict = await FoodGateService.shared.evaluate(image: image),
           !verdict.isFood, verdict.confidence >= 0.95 {
            errorMessage = "This doesn't look like food. Try taking a photo of the meal."
            statusText = "Not food"
            isProcessing = false
            return
        }

        // Butuh API key untuk analisis VLM — jangan tampilkan data palsu.
        guard await coordinator.isVisionConfigured() else {
            errorMessage = "Add your OpenAI API key in Settings to analyze food."
            statusText = "API key needed"
            isProcessing = false
            return
        }

        do {
            let output = try await coordinator.runWithVision(image: image)
            result = output
            statusText = "Done"
            isProcessing = false
            await enrich(result: output)            // gizi (bila perlu) + What-If + porsi
        } catch {
            errorMessage = "Couldn't analyze the photo. Check your connection and tap Retry."
            statusText = "Failed"
            isProcessing = false
        }
    }

    /// Memperkaya hasil scan dengan gizi (Agent 5), What-If, haptic & notifikasi.
    private func enrich(result output: ScanPipelineResult) async {
        isEnriching = true
        defer { isEnriching = false }

        let record = output.record
        let todayTotal = output.recommendation.totalCaloriesToday

        // 1) Gizi + skor → haptic + overlay.
        //    Jika VLM ChatGPT sudah mengisi gizi pada record, pakai langsung
        //    (hemat 1 panggilan). Jika belum, minta NutritionFactAgent (Groq).
        if let info = record.nutrition {
            nutrition = info
            let category = HealthCategory(score: info.healthScore)
            healthCategory = category
            Haptics.play(for: category)                      // 5) Haptic Intelligence
        } else {
            do {
                let info = try await nutritionAgent.perform(
                    NutritionInput(foodName: record.displayName,
                                   calories: record.calories,
                                   portionRatio: record.portionRatio ?? 1.0)
                )
                nutrition = info
                let category = HealthCategory(score: info.healthScore)
                healthCategory = category
                Haptics.play(for: category)                  // 5) Haptic Intelligence

                // Simpan gizi ke record (persisten)
                let updated = record.applying(nutrition: info)
                try? coordinator.persistence.update(updated)
                result = ScanPipelineResult(record: updated, recommendation: output.recommendation)
            } catch {
                aiError = "Nutrition: \(error.localizedDescription)"
            }
        }

        // Mode hemat: lewati panggilan AI proaktif (portion + What-If).
        let reduceAIUsage = UserDefaults.standard.bool(forKey: UserSettings.SharedKeys.reduceAIUsage)
        if !reduceAIUsage {
            // 2) Estimasi porsi otomatis — HANYA pada jalur fallback Core ML.
            //    Pada jalur VLM, kalori sudah dihitung untuk porsi yang terlihat,
            //    jadi panggilan ini redundan → dilewati (hemat 1 panggilan AI).
            if record.nutrition == nil {
                await autoEstimatePortion(for: record)
            }

            // 3) What-If proaktif (2 alternatif)
            do {
                let last3 = Array(coordinator.persistence.allRecords().prefix(3)).map { $0.displayName }
                whatIfAlternatives = try await enhancedRec.whatIf(
                    lastScanned: record.displayName,
                    todayTotal: todayTotal,
                    last3Meals: last3
                )
            } catch {
                aiError = (aiError.map { $0 + " | " } ?? "") + "What-If: \(error.localizedDescription)"
            }
        }

        // 4) Notifikasi 18:00 bila sisa kalori < 500
        enhancedRec.scheduleEveningReminder(todayTotal: todayTotal)
    }

    private func autoEstimatePortion(for record: ScanRecord) async {
        guard selectedImage != nil else { return }
        do {
            let base = CalorieDatabase.calories(for: record.foodLabel)
            portionHint = try await ai.requestPortionHint(
                foodName: record.displayName,
                referenceObject: "the plate size and the visual proportion of the food in the photo",
                baseCalories: base
            )
        } catch {
            aiError = (aiError.map { $0 + " | " } ?? "") + "Portion: \(error.localizedDescription)"
        }
    }

    // MARK: - Portion Hint (pakai objek referensi, mis. koin)

    func requestPortionHint() async {
        guard let image = selectedImage else { return }
        aiError = nil
        do {
            let prediction = try await coordinator.recognize(image: image)
            let base = CalorieDatabase.calories(for: prediction.rawLabel)
            let hint = try await ai.requestPortionHint(
                foodName: prediction.displayName,
                referenceObject: "a coin (~24 mm diameter) next to the food",
                baseCalories: base
            )
            portionHint = hint
        } catch {
            aiError = "Portion: \(error.localizedDescription)"
        }
    }

    // MARK: - Voice Correction

    func applyVoiceCorrection(transcript: String) async {
        guard !transcript.isEmpty, let current = result?.record else { return }
        aiError = nil
        do {
            let corr = try await ai.requestVoiceCorrection(
                transcript: transcript,
                currentFood: current.displayName,
                currentCalories: current.calories
            )
            guard corr.action == "update" else { return }

            let updated = current.applying(
                displayName: corr.correctedFoodName,
                calories: corr.newCalories,
                portionRatio: corr.portionRatio
            )
            try? coordinator.persistence.update(updated)
            if let rec = result?.recommendation {
                result = ScanPipelineResult(record: updated, recommendation: rec)
            }
        } catch {
            aiError = "Voice: \(error.localizedDescription)"
        }
    }

    // MARK: - Food Chat

    var quickChatSuggestions: [String] {
        guard let record = result?.record else { return [] }
        return [
            "If I eat this at night, is it still within my daily target?",
            "What's a healthier version of \(record.displayName)?",
            "What's the ideal portion size for this?"
        ]
    }

    func askFoodQuestion(_ question: String) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let current = result?.record else { return }

        aiError = nil
        isAskingAI = true
        chatMessages.append(.init(role: .user, text: trimmed))
        defer { isAskingAI = false }

        do {
            let answer = try await ai.requestFoodChat(
                foodName: current.displayName,
                calories: current.calories,
                portion: portionHint?.estimatedPortion ?? current.portionRatio,
                nutrition: nutrition,
                userQuestion: trimmed
            )
            chatMessages.append(.init(role: .assistant, text: answer))
        } catch {
            aiError = "Chat: \(error.localizedDescription)"
            chatMessages.append(.init(role: .assistant, text: "Sorry, I can't answer right now. Please try again shortly."))
        }
    }

    // MARK: - Barcode (Open Food Facts)

    /// Cari produk via barcode, simpan sebagai entri, dan tampilkan seperti hasil scan.
    func logBarcode(_ code: String) async {
        isProcessing = true
        errorMessage = nil
        resetAIState()
        statusText = "Looking up barcode…"
        do {
            guard let product = try await OpenFoodFactsService.shared.lookup(barcode: code) else {
                errorMessage = "Product not found in Open Food Facts. Try scanning the meal photo instead."
                statusText = "Not found"
                isProcessing = false
                return
            }
            let record = ScanRecord(
                foodLabel: product.name.lowercased(),
                displayName: product.name,
                calories: product.calories,
                confidence: 1.0,
                date: Date(),
                imageFileName: nil,
                portionRatio: 1.0,
                nutrition: product.nutrition
            )
            try? coordinator.persistence.add(record)
            let recommendation = try await coordinator.recomputeRecommendation()
            result = ScanPipelineResult(record: record, recommendation: recommendation)
            nutrition = product.nutrition
            let category = HealthCategory(score: product.nutrition.healthScore)
            healthCategory = category
            Haptics.play(for: category)
            statusText = "Done"
            isProcessing = false
        } catch {
            errorMessage = "Couldn't look up the barcode. Check your connection and try again."
            statusText = "Failed"
            isProcessing = false
        }
    }

    // MARK: - Recipe

    /// Generate resep dari makanan yang baru dipindai.
    func generateRecipe() async {
        guard let record = result?.record, !isGeneratingRecipe else { return }
        aiError = nil
        isGeneratingRecipe = true
        defer { isGeneratingRecipe = false }
        do {
            recipe = try await ai.requestRecipe(
                foodName: record.displayName,
                calories: record.calories,
                ingredients: nutrition?.ingredients ?? record.nutrition?.ingredients
            )
        } catch {
            aiError = "Recipe: \(error.localizedDescription)"
        }
    }

    // MARK: - Reset

    func reset() {
        selectedImage = nil
        result = nil
        errorMessage = nil
        statusText = "Pick or take a food photo"
        resetAIState()
    }

    private func resetAIState() {
        nutrition = nil
        healthCategory = nil
        whatIfAlternatives = []
        portionHint = nil
        aiError = nil
        chatMessages = []
        isAskingAI = false
        recipe = nil
        isGeneratingRecipe = false
    }
}

// MARK: - Event kolaborasi antar-Agent

extension ScanViewModel: AgentEventDelegate {
    nonisolated func agentDidStart(stage: AgentStage) {
        Task { @MainActor in self.statusText = "\(stage.rawValue)…" }
    }
    nonisolated func agentDidFinish(stage: AgentStage, detail: String) {
        Task { @MainActor in self.statusText = "\(stage.rawValue): \(detail)" }
    }
    nonisolated func agentDidFail(stage: AgentStage, error: Error) {
        Task { @MainActor in self.errorMessage = "[\(stage.rawValue)] \(error.localizedDescription)" }
    }
}
