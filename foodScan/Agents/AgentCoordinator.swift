//
//  AgentCoordinator.swift
//  foodScan
//
//  ╔══════════════════════════════════════════════════════════════════════╗
//  ║ AGENT COORDINATOR (ORCHESTRATOR)                                      ║
//  ╠══════════════════════════════════════════════════════════════════════╣
//  ║ PERAN : Merangkai keempat Agent menjadi satu pipeline dan menjadi     ║
//  ║         satu-satunya titik kontak bagi ViewModel.                     ║
//  ║ POLA  : Pipeline / Chain — output Agent N menjadi input Agent N+1.    ║
//  ║ KOLAB : Melaporkan tiap tahap lewat AgentEventDelegate.               ║
//  ║                                                                       ║
//  ║   gambar ─▶[A1 Recognition]─▶ prediction ─▶[A2 Estimation]           ║
//  ║          ─▶ estimate ─▶[A3 Persistence]─▶ record                      ║
//  ║          ─▶[A4 Recommendation]─▶ recommendation ─▶ UI                 ║
//  ╚══════════════════════════════════════════════════════════════════════╝
//

import UIKit

/// Hasil akhir satu kali proses scan, dikumpulkan dari seluruh Agent.
struct ScanPipelineResult {
    let record: ScanRecord
    let recommendation: DailyRecommendation
}

final class AgentCoordinator {

    // Agent yang dikoordinasikan.
    private let recognitionAgent: ImageRecognitionAgent
    private let estimationAgent: CalorieEstimationAgent
    private let persistenceAgent: PersistenceAgent
    private let recommendationAgent: RecommendationAgent
    private let visionAgent: VisionFoodAnalysisAgent   // jalur VLM ChatGPT (opsional)

    // Lapisan A2A: agent vision diekspos sebagai server A2A, dan Coordinator
    // memanggilnya sebagai KLIEN lewat protokol JSON-RPC (bukan panggilan
    // langsung). Inilah komunikasi Agent-to-Agent berbasis protokol.
    private let a2aNetwork: A2ANetwork
    private let a2aClient: A2AClient

    /// Observer (biasanya ViewModel) untuk progres tiap tahap.
    weak var delegate: AgentEventDelegate?

    init(
        recognitionAgent: ImageRecognitionAgent,
        estimationAgent: CalorieEstimationAgent,
        persistenceAgent: PersistenceAgent,
        recommendationAgent: RecommendationAgent,
        visionAgent: VisionFoodAnalysisAgent = VisionFoodAnalysisAgent()
    ) {
        self.recognitionAgent = recognitionAgent
        self.estimationAgent = estimationAgent
        self.persistenceAgent = persistenceAgent
        self.recommendationAgent = recommendationAgent
        self.visionAgent = visionAgent

        // Registrasi agent ke jaringan A2A + siapkan klien.
        let network = A2ANetwork(servers: [VisionA2AServer(agent: visionAgent)])
        self.a2aNetwork = network
        self.a2aClient = A2AClient(network: network)
    }

    /// Direktori AgentCard yang terdaftar di jaringan A2A (untuk laporan/diagnostik).
    var a2aDirectory: [AgentCard] { a2aNetwork.directory }

    /// Factory standar untuk produksi.
    /// `useMockClassifier == true` memaksa mode demo (tanpa model .mlmodel).
    static func makeDefault(
        store: HistoryStoring = FileHistoryStore(),
        useMockClassifier: Bool = false
    ) -> AgentCoordinator {
        let classifier: FoodClassifying = useMockClassifier
            ? MockFoodClassifier()
            : FoodClassifierService()
        return AgentCoordinator(
            recognitionAgent: ImageRecognitionAgent(classifier: classifier),
            estimationAgent: CalorieEstimationAgent(),
            persistenceAgent: PersistenceAgent(store: store),
            recommendationAgent: RecommendationAgent()
        )
    }

    /// Akses langsung Persistence Agent untuk kebutuhan layar Riwayat.
    var persistence: PersistenceAgent { persistenceAgent }

    /// Memperbarui target kalori harian (dari menu Target Kalori) sehingga
    /// rekomendasi & progres memakai nilai pilihan pengguna.
    func updateDailyTarget(_ target: Int) {
        recommendationAgent.dailyTarget = target
    }

    /// Menjalankan seluruh pipeline untuk satu gambar.
    func run(image: UIImage) async throws -> ScanPipelineResult {

        // ── TAHAP 1: Image Recognition Agent ───────────────────────────────
        delegate?.agentDidStart(stage: .recognition)
        let prediction: FoodPrediction
        do {
            prediction = try await recognitionAgent.perform(image)
        } catch FoodScanError.modelNotFound {
            // Fallback elegan: model belum di-download -> pakai mock agar app
            // tetap berjalan untuk demo/laporan.
            delegate?.agentDidFinish(stage: .recognition, detail: "Model not available — demo mode active")
            let mockAgent = ImageRecognitionAgent(classifier: MockFoodClassifier())
            prediction = try await mockAgent.perform(image)
        } catch {
            delegate?.agentDidFail(stage: .recognition, error: error)
            throw error
        }
        delegate?.agentDidFinish(stage: .recognition,
                                 detail: "\(prediction.displayName) (\(Int(prediction.confidence * 100))%)")

        // ── TAHAP 2: Calorie Estimation Agent ──────────────────────────────
        delegate?.agentDidStart(stage: .estimation)
        let estimate = try await estimationAgent.perform(prediction)
        delegate?.agentDidFinish(stage: .estimation, detail: "\(estimate.caloriesPerServing) kcal")

        // ── TAHAP 3: Persistence Agent ─────────────────────────────────────
        delegate?.agentDidStart(stage: .persistence)
        let imageFileName = ImageStore.save(image)
        let record = try await persistenceAgent.perform(
            PersistenceInput(estimate: estimate, imageFileName: imageFileName)
        )
        delegate?.agentDidFinish(stage: .persistence, detail: "Saved")

        // ── TAHAP 4: Recommendation Agent ──────────────────────────────────
        delegate?.agentDidStart(stage: .recommendation)
        let recommendation = try await recommendationAgent.perform(persistenceAgent.allRecords())
        delegate?.agentDidFinish(stage: .recommendation, detail: recommendation.status.rawValue)

        return ScanPipelineResult(record: record, recommendation: recommendation)
    }

    /// `true` bila API key OpenAI tersedia → jalur VLM ChatGPT dipakai.
    func isVisionConfigured() async -> Bool {
        await visionAgent.isConfigured()
    }

    /// Pipeline berbasis VLM ChatGPT: satu panggilan menganalisis foto →
    /// nama makanan + kalori + gizi lengkap, lalu disimpan & dibuat rekomendasi.
    /// Record yang dikembalikan SUDAH memuat `nutrition`, sehingga ViewModel
    /// tak perlu memanggil Groq untuk gizi lagi.
    func runWithVision(image: UIImage) async throws -> ScanPipelineResult {

        // ── TAHAP 1+2+5 sekaligus: Vision Food Analysis Agent ──────────────
        delegate?.agentDidStart(stage: .recognition)
        let analysis: VisionFoodAnalysis
        do {
            // Panggil agent vision LEWAT PROTOKOL A2A (JSON-RPC message/send),
            // bukan pemanggilan langsung. Foto dikirim sebagai bagian file.
            analysis = try await requestVisionViaA2A(image)
        } catch {
            delegate?.agentDidFail(stage: .recognition, error: error)
            throw error
        }
        guard analysis.isFood else {
            let err = FoodScanError.classificationFailed("This photo wasn't recognized as food.")
            delegate?.agentDidFail(stage: .recognition, error: err)
            throw err
        }
        delegate?.agentDidFinish(stage: .recognition,
                                 detail: "\(analysis.name) (\(Int(analysis.confidence * 100))%)")
        delegate?.agentDidFinish(stage: .estimation, detail: "\(analysis.calories) kcal")

        // ── TAHAP 3: Persistence Agent (record sudah lengkap dengan gizi) ───
        delegate?.agentDidStart(stage: .persistence)
        let imageFileName = ImageStore.save(image)
        let record = ScanRecord(
            foodLabel: analysis.name.lowercased(),
            displayName: analysis.name,
            calories: analysis.calories,
            confidence: analysis.confidence,
            date: Date(),
            imageFileName: imageFileName,
            portionRatio: 1.0,
            nutrition: analysis.nutrition
        )
        try persistenceAgent.add(record)
        delegate?.agentDidFinish(stage: .persistence, detail: "Saved")

        // ── TAHAP 4: Recommendation Agent ──────────────────────────────────
        delegate?.agentDidStart(stage: .recommendation)
        let recommendation = try await recommendationAgent.perform(persistenceAgent.allRecords())
        delegate?.agentDidFinish(stage: .recommendation, detail: recommendation.status.rawValue)

        return ScanPipelineResult(record: record, recommendation: recommendation)
    }

    /// Mengirim foto ke Vision Agent MELALUI protokol A2A dan men-decode
    /// VisionFoodAnalysis dari artifact Task yang dikembalikan.
    private func requestVisionViaA2A(_ image: UIImage) async throws -> VisionFoodAnalysis {
        guard let jpeg = image.jpegData(compressionQuality: 0.7) else {
            throw FoodScanError.classificationFailed("Photo could not be encoded for analysis.")
        }
        // Bangun pesan A2A: instruksi (text) + foto (file).
        let message = A2AMessage(role: .user, parts: [
            .text("Analyze this food photo and return full nutrition with every ingredient."),
            .file(name: "food.jpg", mimeType: "image/jpeg", bytesBase64: jpeg.base64EncodedString())
        ])

        // Kirim sebagai tugas A2A dan tunggu Task hasilnya.
        let task = try await a2aClient.sendMessage(to: VisionA2AServer.agentName, message)

        guard task.status.state == .completed,
              let json = task.firstArtifactDataJSON,
              let data = json.data(using: .utf8) else {
            throw FoodScanError.classificationFailed("Vision agent returned no analysis.")
        }
        return try JSONDecoder().decode(VisionFoodAnalysis.self, from: data)
    }

    /// Dipakai Home untuk menghitung ulang rekomendasi tanpa scan baru.
    func recomputeRecommendation() async throws -> DailyRecommendation {
        try await recommendationAgent.perform(persistenceAgent.allRecords())
    }

    /// Klasifikasi gambar saja (tanpa simpan) — dipakai fitur Portion Hint.
    /// Tetap punya fallback mock bila model belum tersedia.
    func recognize(image: UIImage) async throws -> FoodPrediction {
        do {
            return try await recognitionAgent.perform(image)
        } catch FoodScanError.modelNotFound {
            return try await ImageRecognitionAgent(classifier: MockFoodClassifier()).perform(image)
        }
    }
}
