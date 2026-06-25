//
//  VisionA2AServer.swift
//  foodScan
//
//  ╔══════════════════════════════════════════════════════════════════════╗
//  ║ VISION A2A SERVER — membungkus VisionFoodAnalysisAgent sebagai agent  ║
//  ║ A2A yang bisa dipanggil lewat protokol (JSON-RPC `message/send`).     ║
//  ╠══════════════════════════════════════════════════════════════════════╣
//  ║ INPUT  : A2AMessage berisi bagian file (foto makanan, image/jpeg).    ║
//  ║ OUTPUT : A2ATask completed dengan artifact data = VisionFoodAnalysis  ║
//  ║          (JSON).                                                       ║
//  ║ ERROR  : bila bukan makanan / gagal analisis → balasan error JSON-RPC. ║
//  ╚══════════════════════════════════════════════════════════════════════╝
//
//  TICKET #A2A-1
//   - As: AgentCoordinator (klien A2A)
//   - I want: mengirim foto ke agent vision lewat protokol A2A dan menerima
//     VisionFoodAnalysis sebagai artifact
//   - So that: orkestrasi antar-agent memakai kontrak protokol standar, bukan
//     pemanggilan langsung — agent bisa dipindah ke proses/host lain.
//

import UIKit

final class VisionA2AServer: A2AServer {

    /// Nama kanonik agent (dipakai untuk discovery & routing).
    static let agentName = "VisionFoodAnalysisAgent"

    private let agent: VisionFoodAnalysisAgent
    private let encoder = JSONEncoder()

    init(agent: VisionFoodAnalysisAgent = VisionFoodAnalysisAgent()) {
        self.agent = agent
    }

    // MARK: Agent Card (discovery)

    var card: AgentCard {
        AgentCard(
            name: Self.agentName,
            description: "Analyzes a food photo and returns full nutrition plus every detected ingredient.",
            url: "a2a://local/agents/vision-food-analysis",
            version: "1.0.0",
            capabilities: AgentCapabilities(streaming: false),
            skills: [
                AgentSkill(
                    id: "analyze-food-photo",
                    name: "Analyze food photo",
                    description: "Detect the dish, estimate calories & macros, and list every ingredient from one image.",
                    tags: ["vision", "nutrition", "food"]
                )
            ]
        )
    }

    // MARK: JSON-RPC handler

    func handle(_ request: A2ARequest) async -> A2AResponse {
        guard request.method == "message/send" else {
            return .failure(id: request.id, code: -32601, message: "Method not found: \(request.method)")
        }

        // Ambil bagian file (foto) dari pesan masuk.
        guard let file = request.params.message.parts.firstFile,
              let bytes = Data(base64Encoded: file.bytesBase64),
              let image = UIImage(data: bytes) else {
            return .failure(id: request.id, code: -32602,
                            message: "Invalid params: expected an image file part")
        }

        do {
            let analysis = try await agent.perform(image)
            let json = String(data: try encoder.encode(analysis), encoding: .utf8) ?? "{}"
            let artifact = A2AArtifact(name: "food-analysis", parts: [.data(json: json)])
            let task = A2ATask(
                status: A2ATaskStatus(state: .completed),
                artifacts: [artifact]
            )
            return A2AResponse(id: request.id, result: task)
        } catch {
            return .failure(id: request.id, code: -32000, message: error.localizedDescription)
        }
    }
}
