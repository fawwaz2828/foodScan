//
//  A2ANetwork.swift
//  foodScan
//
//  ╔══════════════════════════════════════════════════════════════════════╗
//  ║ A2A NETWORK + CLIENT                                                   ║
//  ╠══════════════════════════════════════════════════════════════════════╣
//  ║ A2ANetwork : "registry + transport" lokal. Menyimpan agent-server     ║
//  ║              berdasarkan AgentCard, lalu meneruskan JSON-RPC ke agent  ║
//  ║              tujuan. Untuk MENIRU batas jaringan A2A yang sebenarnya,  ║
//  ║              setiap request & response BENAR-BENAR di-serialize ke     ║
//  ║              JSON lalu di-decode ulang di sisi seberang. Mengganti     ║
//  ║              transport ini dengan HTTP tidak mengubah kontrak agent.   ║
//  ║ A2AClient  : sisi pemanggil. Menemukan agent (discovery) lalu mengirim ║
//  ║              Message sebagai tugas dan menunggu Task hasilnya.         ║
//  ╚══════════════════════════════════════════════════════════════════════╝
//

import Foundation

/// Transport + directory A2A in-process. Daftar agent ditetapkan saat init
/// (immutable) sehingga aman dipakai dari banyak task tanpa data race.
final class A2ANetwork {

    private let servers: [String: A2AServer]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(servers: [A2AServer]) {
        var map: [String: A2AServer] = [:]
        for s in servers { map[s.card.name] = s }
        self.servers = map
    }

    // MARK: Discovery

    /// AgentCard satu agent (capability discovery).
    func agentCard(named name: String) -> AgentCard? { servers[name]?.card }

    /// Direktori seluruh AgentCard yang terdaftar (untuk laporan/diagnostik).
    var directory: [AgentCard] { servers.values.map(\.card).sorted { $0.name < $1.name } }

    // MARK: Transport

    /// Mengirim satu permintaan JSON-RPC ke agent tujuan.
    ///
    /// Langkah-langkahnya sengaja meniru komunikasi lintas-proses:
    ///   encode(request) → byte JSON → decode di sisi server → handle →
    ///   encode(response) → byte JSON → decode di sisi klien.
    /// Round-trip ganda ini membuktikan kontrak benar-benar lewat protokol,
    /// bukan sekadar pemanggilan fungsi langsung.
    func send(to name: String, _ request: A2ARequest) async throws -> A2AResponse {
        guard let server = servers[name] else {
            throw A2AErrorObject(code: -32004, message: "Agent not found: \(name)")
        }

        // Klien → (wire) → Server
        let outboundWire = try encoder.encode(request)
        let deliveredRequest = try decoder.decode(A2ARequest.self, from: outboundWire)

        let rawResponse = await server.handle(deliveredRequest)

        // Server → (wire) → Klien
        let inboundWire = try encoder.encode(rawResponse)
        return try decoder.decode(A2AResponse.self, from: inboundWire)
    }
}

/// Sisi pemanggil protokol A2A. Membungkus pembuatan amplop JSON-RPC dan
/// penanganan error sehingga agent-pemanggil cukup berpikir "kirim pesan".
struct A2AClient {
    let network: A2ANetwork

    /// Menemukan agent berdasarkan nama (discovery).
    func discover(_ agentName: String) -> AgentCard? {
        network.agentCard(named: agentName)
    }

    /// Mengirim satu pesan ke agent tujuan dan mengembalikan Task hasilnya.
    /// Melempar `A2AErrorObject` bila agent mengembalikan error JSON-RPC.
    func sendMessage(to agentName: String, _ message: A2AMessage) async throws -> A2ATask {
        let request = A2ARequest(params: A2AMessageSendParams(message: message))
        let response = try await network.send(to: agentName, request)

        if let error = response.error { throw error }
        guard let task = response.result else {
            throw A2AErrorObject(code: -32603, message: "Empty A2A result from \(agentName)")
        }
        return task
    }
}
